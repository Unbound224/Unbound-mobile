import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import 'models_test.dart' show quoteJson;

typedef Handler = FutureOr<void> Function(HttpRequest req, String body);

/// Real HTTP over loopback to a local stub. The stub is a TEST double of unbound-core, not the real service.
Future<(HttpServer, HttpCoreApi, List<(String, String, Map<String, String>)>)>
boot(Handler h, {Duration? timeout, String? token = 'tok'}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final seen = <(String, String, Map<String, String>)>[];
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    seen.add((
      req.method,
      req.uri.toString(),
      {
        'authorization': req.headers.value('authorization') ?? '',
        'idempotency-key': req.headers.value('idempotency-key') ?? '',
        'body': body,
      },
    ));
    await h(req, body);
    await req.response.close();
  });
  final api = HttpCoreApi(
    baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    tokenProvider: () => token,
    timeout: timeout ?? const Duration(seconds: 5),
  );
  return (server, api, seen);
}

void reply(HttpRequest r, int status, Object body) {
  r.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

final intentJson = {
  'id': 'int_1',
  'state': 'AWAITING_SIGNATURE',
  'quoteId': 'q_1',
  'txHash': 'a' * 64,
  'unsignedXdr': 'AAAA',
  'failureReason': null,
  'amountOutActual': null,
  'ledger': null,
};

void main() {
  portfolioTests();
  test(
    'sends bearer token and Idempotency-Key as headers, never in the URL',
    () async {
      final (s, api, seen) = await boot((r, _) => reply(r, 201, intentJson));
      addTearDown(() => s.close(force: true));
      final v = await api.createIntent(
        quoteId: 'q_1',
        idempotencyKey: 'key-123456789',
      );
      expect(v.state, IntentState.awaitingSignature);
      final (m, url, h) = seen.single;
      expect(m, 'POST');
      expect(url, '/v1/exchange/intents');
      expect(h['authorization'], 'Bearer tok');
      expect(h['idempotency-key'], 'key-123456789');
      expect(jsonDecode(h['body']!), {'quoteId': 'q_1'});
    },
  );

  test(
    'requestQuote posts the TESTNET contract body and parses the nested quote',
    () async {
      final (s, api, seen) = await boot(
        (r, _) => reply(r, 201, {'quote': quoteJson(), 'requestId': 'r'}),
      );
      addTearDown(() => s.close(force: true));
      final q = await api.requestQuote(
        source: const AssetRef('SHOP', 'GSHOP'),
        target: const AssetRef('USDC', 'GUSDC'),
        sourceAmount: '80',
        slippageBps: 100,
        destinationAccount: 'GME',
      );
      expect(q.quoteId, 'q_1');
      final body = jsonDecode(seen.single.$3['body']!) as Map<String, Object?>;
      expect(body['network'], 'TESTNET');
      expect(body['schemaVersion'], '1.0');
    },
  );

  test('maps the core error envelope', () async {
    final (s, api, _) = await boot(
      (r, _) => reply(r, 409, {
        'error': {
          'code': 'INVALID_STATE',
          'message': 'nope',
          'requestId': 'req_7',
        },
      }),
    );
    addTearDown(() => s.close(force: true));
    await expectLater(
      api.getIntent('int_1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'INVALID_STATE')
            .having((e) => e.requestId, 'requestId', 'req_7')
            .having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse),
      ),
    );
  });

  test('non-JSON bodies and contract violations are BAD_RESPONSE (outcome unknown)', () async {
    var n = 0;
    final (s, api, _) = await boot((r, _) {
      n++;
      if (n == 1) {
        r.response
          ..statusCode = 502
          ..write('<html>bad gateway</html>');
      } else {
        reply(r, 200, {...intentJson, 'state': 'SETTLED'});
      }
    });
    addTearDown(() => s.close(force: true));
    await expectLater(
      api.getIntent('x'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'BAD_RESPONSE'),
      ),
    );
    await expectLater(
      api.getIntent('x'),
      throwsA(
        isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', isTrue),
      ),
    );
  });

  test(
    'timeouts and refused connections are NETWORK with unknown outcome',
    () async {
      final (s, api, _) = await boot(
        (r, _) async => Future<void>.delayed(const Duration(milliseconds: 500)),
        timeout: const Duration(milliseconds: 100),
      );
      addTearDown(() => s.close(force: true));
      await expectLater(
        api.getIntent('x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
      );
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);
      final api2 = HttpCoreApi(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        tokenProvider: () => null,
      );
      await expectLater(
        api2.listAssets(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            isTrue,
          ),
        ),
      );
    },
  );

  test('ids are URL-encoded', () async {
    final (s, api, seen) = await boot((r, _) => reply(r, 200, intentJson));
    addTearDown(() => s.close(force: true));
    await api.getIntent('a/b c');
    expect(seen.single.$2, '/v1/exchange/intents/a%2Fb%20c');
  });

  test(
    'listAssets refuses suspended programs smuggled into the eligible list',
    () async {
      final (s, api, _) = await boot(
        (r, _) => reply(r, 200, {
          'assets': [
            {
              'id': 'p',
              'assetCode': 'SHOP',
              'issuer': 'G',
              'status': 'SUSPENDED',
              'policy': {
                'unitOfAccount': 'u',
                'expiresAt': '2027-01-01T00:00:00Z',
                'jurisdiction': 'j',
                'refundPolicy': 'r',
                'contact': 'c',
              },
            },
          ],
        }),
      );
      addTearDown(() => s.close(force: true));
      await expectLater(
        api.listAssets(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'BAD_RESPONSE'),
        ),
      );
    },
  );
}

void portfolioTests() {
  test('portfolio, targets and wallet login parse the core contract', () async {
    var n = 0;
    final (s, api, seen) = await boot((r, _) {
      n++;
      switch (n) {
        case 1:
          reply(r, 200, {
            'targets': [
              {'code': 'USDC', 'issuer': 'GUSDC'},
            ],
          });
        case 2:
          reply(r, 200, {
            'challengeId': 'chl_1',
            'message': 'unbound-auth:v1:TESTNET:n:GME',
            'expiresAt': 'x',
          });
        case 3:
          reply(r, 200, {
            'token': 'tok_abc',
            'userId': 'usr_1',
            'publicKey': 'GME',
          });
        default:
          reply(r, 200, {
            'asOf': 'x',
            'wallets': ['GME'],
            'native': <Object?>[],
            'notice': 'Only REDEEMABLE credit can be exchanged or redeemed.',
            'holdings': [
              {
                'wallet': 'GME',
                'asset': {'code': 'SHOP', 'issuer': 'GSHOP'},
                'balance': '20.0000000',
                'status': 'REDEEMABLE',
                'program': {
                  'id': 'p',
                  'unitOfAccount': '1 SHOP = 1 USD',
                  'expiresAt': '2027-01-01T00:00:00.000Z',
                  'jurisdiction': 'T',
                  'contact': 'c',
                },
              },
              {
                'wallet': 'GME',
                'asset': {'code': 'RND', 'issuer': 'GZ'},
                'balance': '5.0000000',
                'status': 'UNVERIFIED',
              },
            ],
          });
      }
    });
    addTearDown(() => s.close(force: true));
    expect((await api.listTargets()).single, const AssetRef('USDC', 'GUSDC'));
    final ch = await api.walletChallenge('GME');
    expect(ch.message, contains('GME'));
    expect(
      await api.walletVerify(
        challengeId: ch.challengeId,
        signatureBase64: 'c2ln',
      ),
      'tok_abc',
    );
    final p = await api.portfolio();
    expect(p.holdings.map((h) => h.status), [
      HoldingStatus.redeemable,
      HoldingStatus.unverified,
    ]);
    expect(p.holdings.first.usable, isTrue);
    expect(p.holdings.last.usable, isFalse);
    expect(p.holdings.last.unitOfAccount, isNull);
    expect(seen.map((e) => e.$2), [
      '/v1/targets',
      '/v1/wallets/challenge',
      '/v1/wallets/verify',
      '/v1/portfolio',
    ]);
  });

  test(
    'portfolio with an unknown holding status is a contract error',
    () async {
      final (s, api, _) = await boot(
        (r, _) => reply(r, 200, {
          'notice': 'n',
          'holdings': [
            {
              'wallet': 'G',
              'asset': {'code': 'A', 'issuer': 'G'},
              'balance': '1.0000000',
              'status': 'GOLDEN',
            },
          ],
        }),
      );
      addTearDown(() => s.close(force: true));
      await expectLater(
        api.portfolio(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'BAD_RESPONSE'),
        ),
      );
    },
  );
}
