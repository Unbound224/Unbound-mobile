import 'package:test/test.dart';
import 'package:unbound_mobile/domain/models.dart';

Map<String, Object?> quoteJson([Map<String, Object?> over = const {}]) => {
  'schemaVersion': '1.0',
  'quoteId': 'q_1',
  'network': 'TESTNET',
  'networkPassphrase': testnetPassphrase,
  'sourceAsset': {'code': 'SHOP', 'issuer': 'GSHOP'},
  'targetAsset': {'code': 'USDC', 'issuer': 'GUSDC'},
  'sourceAmount': '80.0000000',
  'expectedDestinationAmount': '72.0000000',
  'minDestinationAmount': '71.2800000',
  'slippageBps': 100,
  'path': <Object?>[],
  'estimatedFeeStroops': 100,
  'issuedAt': '2026-11-02T12:00:00.000Z',
  'expiresAt': '2026-11-02T12:01:00.000Z',
  'warnings': <Object?>['Indicative quote only'],
  ...over,
};

void main() {
  group('Quote.fromJson', () {
    test('parses a valid quote', () {
      final q = Quote.fromJson(quoteJson());
      expect(q.minDestination.toString(), '71.2800000');
      expect(q.expiresAt.isUtc, isTrue);
    });

    test('fails closed on other networks, versions, and bad amounts', () {
      expect(
        () => Quote.fromJson(quoteJson({'network': 'PUBLIC'})),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => Quote.fromJson(quoteJson({'schemaVersion': '2.0'})),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => Quote.fromJson(quoteJson({'sourceAmount': '1e3'})),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => Quote.fromJson(quoteJson({'expiresAt': 'soon'})),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => Quote.fromJson(quoteJson({'slippageBps': '100'})),
        throwsA(isA<ContractException>()),
      );
    });
  });

  group('states', () {
    test('unknown states are refused, not guessed', () {
      expect(
        () => IntentState.parse('SETTLED'),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => RedemptionState.parse('PAID'),
        throwsA(isA<ContractException>()),
      );
    });
    test('terminal flags', () {
      expect(IntentState.reconciling.isTerminal, isFalse);
      expect(IntentState.confirmed.isTerminal, isTrue);
      expect(RedemptionState.returnConfirmed.isTerminal, isFalse);
    });
  });

  test('EligibleAsset rejects suspended programs', () {
    final base = {
      'id': 'prg_1',
      'assetCode': 'SHOP',
      'issuer': 'GSHOP',
      'status': 'SUSPENDED',
      'policy': {
        'unitOfAccount': '1 SHOP = 1 USD',
        'expiresAt': '2027-11-02T00:00:00.000Z',
        'jurisdiction': 'Testland',
        'refundPolicy': 'r',
        'contact': 'c',
      },
    };
    expect(
      () => EligibleAsset.fromJson(base),
      throwsA(isA<ContractException>()),
    );
    expect(
      EligibleAsset.fromJson({...base, 'status': 'ACTIVE'}).asset.code,
      'SHOP',
    );
  });

  test('IntentView parses amountOutActual exactly', () {
    final v = IntentView.fromJson({
      'id': 'int_1',
      'state': 'CONFIRMED',
      'quoteId': 'q_1',
      'txHash': 'a' * 64,
      'unsignedXdr': null,
      'failureReason': null,
      'amountOutActual': '72.0000000',
      'ledger': 7,
    });
    expect(v.amountOutActual.toString(), '72.0000000');
  });
}
