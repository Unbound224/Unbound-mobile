import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/approval_guard.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/flows/redemption_flow.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import 'support/fakes.dart';

/// TEST ADAPTER: canned decoder for a payment of 30 SHOP back to the issuer.
class PaymentInspector implements TransactionInspector {
  String destination = 'GSHOP';
  String amount = '30';
  String op = 'payment';
  @override
  TxSummary inspect(String unsignedXdr) => TxSummary(
    networkPassphrase: testnetPassphrase,
    sourceAccount: 'GME',
    operationType: op,
    sendAsset: const AssetRef('SHOP', 'GSHOP'),
    sendAmount: Amount.parse(amount),
    destAsset: const AssetRef('SHOP', 'GSHOP'),
    destMin: Amount.parse(amount),
    destination: destination,
    path: const [],
    hash: hash64,
    operationCount: 1,
  );
}

const shop = AssetRef('SHOP', 'GSHOP');

({
  FakeCoreApi api,
  FakeSigner signer,
  PaymentInspector insp,
  RedemptionFlow flow,
  PendingStore store,
})
rig([PendingStore? s]) {
  final api = FakeCoreApi();
  final signer = FakeSigner();
  final insp = PaymentInspector();
  final store = s ?? InMemoryPendingStore();
  return (
    api: api,
    signer: signer,
    insp: insp,
    store: store,
    flow: RedemptionFlow(
      api: api,
      signer: signer,
      inspector: insp,
      store: store,
      delay: (_) async {},
      maxPolls: 5,
    ),
  );
}

void main() {
  test('happy path ends FULFILLED only after the merchant confirms', () async {
    final r = rig();
    r.api.redemptionScript = [
      redemptionView(RedemptionState.returnSubmitted),
      redemptionView(RedemptionState.returnConfirmed),
      redemptionView(RedemptionState.fulfilled),
    ];
    final res = await r.flow.redeem(asset: shop, amount: Amount.parse('30'));
    expect(res.kind, RedemptionOutcomeKind.terminal);
    expect(res.redemption!.state, RedemptionState.fulfilled);
    expect(r.signer.signCalls, 1);
    expect(r.api.returnCalls, 1);
  });

  test('waiting on the merchant is in-flight, not done', () async {
    final r = rig();
    r.api.redemptionScript = [redemptionView(RedemptionState.returnConfirmed)];
    final res = await r.flow.redeem(asset: shop, amount: Amount.parse('30'));
    expect(res.kind, RedemptionOutcomeKind.inFlight);
    expect(res.redemption!.state, RedemptionState.returnConfirmed);
  });

  test(
    'unsupported credit: server refusal is surfaced and nothing is signed',
    () async {
      final r = rig();
      r.api.createRedemptionResult = ApiException(
        'REDEMPTION_UNAVAILABLE',
        'no active program',
        status: 422,
      );
      await expectLater(
        r.flow.redeem(asset: shop, amount: Amount.parse('30')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'REDEMPTION_UNAVAILABLE',
          ),
        ),
      );
      expect(r.signer.signCalls, 0);
    },
  );

  for (final bad in <String, void Function(PaymentInspector)>{
    'a payment to a non-issuer address': (i) => i.destination = 'GATTACKER',
    'a different amount': (i) => i.amount = '300',
    'a non-payment operation': (i) => i.op = 'pathPaymentStrictSend',
  }.entries) {
    test('refuses to sign ${bad.key}', () async {
      final r = rig();
      bad.value(r.insp);
      final res = await r.flow.redeem(asset: shop, amount: Amount.parse('30'));
      expect(res.kind, RedemptionOutcomeKind.refused);
      expect([r.signer.signCalls, r.api.returnCalls], [0, 0]);
    });
  }

  test('cancelled signing sends nothing', () async {
    final r = rig();
    r.signer.cancel = true;
    expect(
      (await r.flow.redeem(asset: shop, amount: Amount.parse('30'))).kind,
      RedemptionOutcomeKind.cancelled,
    );
    expect(r.api.returnCalls, 0);
  });

  test(
    'unknown outcome on the return is tracked; the same key is reused on retry',
    () async {
      final store = InMemoryPendingStore();
      final r = rig(store);
      r.api.returnResult = ApiException('NETWORK', 'timeout');
      r.api.redemptionScript = [
        redemptionView(RedemptionState.returnSubmitted),
        redemptionView(RedemptionState.fulfilled),
      ];
      expect(
        (await r.flow.redeem(asset: shop, amount: Amount.parse('30'))).kind,
        RedemptionOutcomeKind.terminal,
      );
      final r2 = rig(store);
      await r2.flow.redeem(asset: shop, amount: Amount.parse('30'));
      expect(r2.api.redemptionKeys.single, r.api.redemptionKeys.single);
    },
  );

  test(
    'rejected-with-refund is terminal and carries the refund flag',
    () async {
      final r = rig();
      r.api.redemptionScript = [
        redemptionView(RedemptionState.rejected, refund: true),
      ];
      final res = await r.flow.redeem(asset: shop, amount: Amount.parse('30'));
      expect(res.redemption!.refundDue, isTrue);
    },
  );

  test('offline polling returns the last known state flagged stale', () async {
    final r = rig();
    r.api.redemptionScript = [ApiException('NETWORK', 'offline')];
    final res = await r.flow.redeem(asset: shop, amount: Amount.parse('30'));
    expect(res.kind, RedemptionOutcomeKind.inFlight);
    expect(res.stale, isTrue);
  });
}
