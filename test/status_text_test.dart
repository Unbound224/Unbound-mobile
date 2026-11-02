import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/domain/status_text.dart';

IntentView iv(IntentState s, {String? reason, Amount? out}) => IntentView(
  id: 'i',
  state: s,
  quoteId: 'q',
  txHash: null,
  unsignedXdr: null,
  failureReason: reason,
  amountOutActual: out,
  ledger: null,
);

void main() {
  test('only CONFIRMED may say the exchange is complete', () {
    for (final s in IntentState.values) {
      final t = exchangeStatus(iv(s));
      final claimsDone =
          '${t.headline} ${t.detail}'.toLowerCase().contains('complete') ||
          t.headline.toLowerCase().contains('received');
      expect(claimsDone, s == IntentState.confirmed, reason: '$s');
    }
  });

  test('submitted and reconciling warn not to retry and never offer retry', () {
    for (final s in [IntentState.submitted, IntentState.reconciling]) {
      final t = exchangeStatus(iv(s));
      expect(t.warnDoNotRetry, isTrue);
      expect(t.showRetry, isFalse);
    }
  });

  test('confirmed shows the ledger-derived amount; failed offers a fresh start without promising a refund', () {
    expect(
      exchangeStatus(iv(IntentState.confirmed, out: Amount.parse('72'))).detail,
      contains('72.00'),
    );
    final f = exchangeStatus(
      iv(IntentState.failed, reason: 'MIN_OUTPUT_VIOLATION'),
    );
    expect(f.showRetry, isTrue);
    expect(f.detail, contains('MIN_OUTPUT_VIOLATION'));
  });

  test('redemption: returned is not redeemed; refund-owed is surfaced', () {
    RedemptionView rv(RedemptionState s, {bool refund = false}) =>
        RedemptionView(
          id: 'r',
          state: s,
          asset: const AssetRef('SHOP', 'G'),
          amount: Amount.parse('5'),
          returnTxHash: null,
          unsignedXdr: null,
          refundDue: refund,
        );
    expect(
      redemptionStatus(rv(RedemptionState.returnConfirmed)).headline,
      isNot('Redeemed'),
    );
    expect(
      redemptionStatus(rv(RedemptionState.fulfilled)).headline,
      'Redeemed',
    );
    expect(
      redemptionStatus(rv(RedemptionState.rejected, refund: true)).detail,
      contains('refund'),
    );
    expect(
      redemptionStatus(rv(RedemptionState.returnSubmitted)).warnDoNotRetry,
      isTrue,
    );
  });
}
