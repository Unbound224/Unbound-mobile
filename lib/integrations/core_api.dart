import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';

class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status = 0, this.requestId});
  final String code;
  final String message;
  final int status;
  final String? requestId;

  /// True when no definitive answer was received (timeout, connection loss, bad body on 2xx).
  /// For writes this means the outcome is UNKNOWN, not failed.
  bool get outcomeUnknown =>
      status == 0 || status >= 500 || code == 'BAD_RESPONSE';

  @override
  String toString() => 'ApiException($code, $status)';
}

/// Port to unbound-core (/v1). The mobile app owns no business rules beyond presentation and signing.
abstract class CoreApi {
  Future<List<EligibleAsset>> listAssets();

  /// Assets a holder may receive in an exchange (admin-curated; not redeemable credit).
  Future<List<AssetRef>> listTargets();
  Future<WalletChallenge> walletChallenge(String publicKey);

  /// Exchanges a signed challenge for a session token; the caller stores it in memory only.
  Future<String> walletVerify({
    required String challengeId,
    required String signatureBase64,
  });
  Future<PortfolioView> portfolio();
  Future<Quote> requestQuote({
    required AssetRef source,
    required AssetRef target,
    required String sourceAmount,
    required int slippageBps,
    required String destinationAccount,
  });
  Future<IntentView> createIntent({
    required String quoteId,
    required String idempotencyKey,
  });
  Future<IntentView> getIntent(String id);
  Future<IntentView> submitIntent({
    required String id,
    required String signedXdr,
    required String idempotencyKey,
  });
  Future<RedemptionView> createRedemption({
    required AssetRef asset,
    required String amount,
    required String holder,
    required String idempotencyKey,
  });
  Future<RedemptionView> getRedemption(String id);
  Future<RedemptionView> submitRedemptionReturn({
    required String id,
    required String signedXdr,
  });
}

typedef Json = Map<String, Object?>;

class HttpCoreApi implements CoreApi {
  HttpCoreApi({
    required this.baseUri,
    required this.tokenProvider,
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient();

  final Uri baseUri;

  /// Session bearer token; never logged or put in a URL.
  final String? Function() tokenProvider;
  final Duration timeout;
  final HttpClient _client;

  Future<Object?> _send(
    String method,
    String path, {
    Json? body,
    String? idempotencyKey,
    Map<String, String>? query,
  }) async {
    final uri = baseUri.replace(path: path, queryParameters: query);
    try {
      final req = await _client.openUrl(method, uri).timeout(timeout);
      req.headers.set('accept', 'application/json');
      final t = tokenProvider();
      if (t != null) req.headers.set('authorization', 'Bearer $t');
      if (idempotencyKey != null) {
        req.headers.set('idempotency-key', idempotencyKey);
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw ApiException(
          'BAD_RESPONSE',
          'Server returned a non-JSON response.',
          status: res.statusCode,
        );
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
      if (decoded is Json && decoded['error'] is Json) {
        final e = decoded['error']! as Json;
        throw ApiException(
          '${e['code']}',
          '${e['message']}',
          status: res.statusCode,
          requestId: e['requestId'] as String?,
        );
      }
      throw ApiException(
        'BAD_RESPONSE',
        'Unexpected error response.',
        status: res.statusCode,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('NETWORK', 'The request timed out.');
    } on SocketException {
      throw ApiException('NETWORK', 'Cannot reach the Unbound service.');
    } on HttpException {
      throw ApiException('NETWORK', 'Connection problem.');
    }
  }

  T _parse<T>(Object? j, T Function(Json) f) {
    if (j is! Json) {
      throw ApiException('BAD_RESPONSE', 'Unexpected response shape.');
    }
    try {
      return f(j);
    } on ContractException catch (e) {
      throw ApiException('BAD_RESPONSE', e.message);
    }
  }

  @override
  Future<List<EligibleAsset>> listAssets() async {
    final j = await _send('GET', '/v1/assets');
    return _parse(j, (m) {
      final list = m['assets'];
      if (list is! List<Object?>) throw ContractException('assets missing');
      return [for (final a in list) EligibleAsset.fromJson(a! as Json)];
    });
  }

  @override
  Future<List<AssetRef>> listTargets() async {
    final j = await _send('GET', '/v1/targets');
    return _parse(j, (m) {
      final list = m['targets'];
      if (list is! List<Object?>) {
        throw ContractException('targets missing');
      }
      return [for (final t in list) AssetRef.fromJson(t! as Json)];
    });
  }

  @override
  Future<WalletChallenge> walletChallenge(String publicKey) async => _parse(
    await _send(
      'POST',
      '/v1/wallets/challenge',
      body: {'publicKey': publicKey},
    ),
    (m) {
      final id = m['challengeId'];
      final msg = m['message'];
      if (id is! String || msg is! String) {
        throw ContractException('challenge malformed');
      }
      return WalletChallenge(id, msg);
    },
  );

  @override
  Future<String> walletVerify({
    required String challengeId,
    required String signatureBase64,
  }) async => _parse(
    await _send(
      'POST',
      '/v1/wallets/verify',
      body: {'challengeId': challengeId, 'signature': signatureBase64},
    ),
    (m) {
      final t = m['token'];
      if (t is! String || t.isEmpty) {
        throw ContractException('token missing');
      }
      return t;
    },
  );

  @override
  Future<PortfolioView> portfolio() async =>
      _parse(await _send('GET', '/v1/portfolio'), PortfolioView.fromJson);

  @override
  Future<Quote> requestQuote({
    required AssetRef source,
    required AssetRef target,
    required String sourceAmount,
    required int slippageBps,
    required String destinationAccount,
  }) async {
    final j = await _send(
      'POST',
      '/v1/exchange/quote',
      body: {
        'schemaVersion': '1.0',
        'sourceAsset': source.toJson(),
        'targetAsset': target.toJson(),
        'sourceAmount': sourceAmount,
        'slippageBps': slippageBps,
        'destinationAccount': destinationAccount,
        'network': 'TESTNET',
      },
    );
    return _parse(j, (m) {
      final q = m['quote'];
      if (q is! Json) throw ContractException('quote missing');
      return Quote.fromJson(q);
    });
  }

  @override
  Future<IntentView> createIntent({
    required String quoteId,
    required String idempotencyKey,
  }) async => _parse(
    await _send(
      'POST',
      '/v1/exchange/intents',
      body: {'quoteId': quoteId},
      idempotencyKey: idempotencyKey,
    ),
    IntentView.fromJson,
  );

  @override
  Future<IntentView> getIntent(String id) async => _parse(
    await _send('GET', '/v1/exchange/intents/${Uri.encodeComponent(id)}'),
    IntentView.fromJson,
  );

  @override
  Future<IntentView> submitIntent({
    required String id,
    required String signedXdr,
    required String idempotencyKey,
  }) async => _parse(
    await _send(
      'POST',
      '/v1/exchange/intents/${Uri.encodeComponent(id)}/submit',
      body: {'signedXdr': signedXdr},
      idempotencyKey: idempotencyKey,
    ),
    IntentView.fromJson,
  );

  @override
  Future<RedemptionView> createRedemption({
    required AssetRef asset,
    required String amount,
    required String holder,
    required String idempotencyKey,
  }) async => _parse(
    await _send(
      'POST',
      '/v1/redemptions',
      body: {'asset': asset.toJson(), 'amount': amount, 'holder': holder},
      idempotencyKey: idempotencyKey,
    ),
    RedemptionView.fromJson,
  );

  @override
  Future<RedemptionView> getRedemption(String id) async => _parse(
    await _send('GET', '/v1/redemptions/${Uri.encodeComponent(id)}'),
    RedemptionView.fromJson,
  );

  @override
  Future<RedemptionView> submitRedemptionReturn({
    required String id,
    required String signedXdr,
  }) async => _parse(
    await _send(
      'POST',
      '/v1/redemptions/${Uri.encodeComponent(id)}/return',
      body: {'signedXdr': signedXdr},
    ),
    RedemptionView.fromJson,
  );

  void close() => _client.close(force: true);
}
