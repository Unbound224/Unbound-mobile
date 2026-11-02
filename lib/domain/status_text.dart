import 'models.dart';

/// User-facing status. Never says "settled/complete" before the ledger confirmed it.
class StatusText {
  const StatusText(
    this.headline,
    this.detail, {
    this.showRetry = false,
    this.warnDoNotRetry = false,
  });
  final String headline;
  final String detail;

  /// Offer "start over with a new quote" (only when nothing can still land).
  final bool showRetry;

  /// Tell the user not to repeat the exchange while the outcome is unknown.
  final bool warnDoNotRetry;
}

StatusText exchangeStatus(IntentView v) {
  switch (v.state) {
    case IntentState.draft:
    case IntentState.verified:
      return const StatusText(
        'Preparing',
        'Checking the issuer and building your transaction.',
      );
    case IntentState.awaitingSignature:
      return const StatusText(
        'Waiting for your approval',
        'Review the exact amounts, then approve on this device.',
      );
    case IntentState.submitted:
      return const StatusText(
        'Submitted',
        'Sent to the Stellar network. Not final yet.',
        warnDoNotRetry: true,
      );
    case IntentState.reconciling:
      return const StatusText(
        'Confirming',
        'We have not seen the final result yet. This can take a while. Please do not repeat the exchange; we will update this screen.',
        warnDoNotRetry: true,
      );
    case IntentState.confirmed:
      final out = v.amountOutActual;
      return StatusText(
        'Exchange complete',
        out == null
            ? 'Confirmed on the Stellar ledger.'
            : 'Confirmed on the ledger. You received ${out.toDisplay()}.',
      );
    case IntentState.failed:
      return StatusText(
        'Exchange did not happen',
        'The exchange failed${v.failureReason == null ? '' : ' (${v.failureReason})'}. Your credit was not exchanged. A small network fee may still apply.',
        showRetry: true,
      );
    case IntentState.cancelled:
      return const StatusText(
        'Cancelled',
        'Nothing was sent.',
        showRetry: true,
      );
  }
}

StatusText redemptionStatus(RedemptionView v) {
  switch (v.state) {
    case RedemptionState.awaitingReturn:
      return const StatusText(
        'Approve the return',
        'Send your credit back to the issuer on the ledger so the merchant can honor it.',
      );
    case RedemptionState.returnSubmitted:
      return const StatusText(
        'Waiting for the ledger',
        'Your return is not confirmed yet. Do not repeat it.',
        warnDoNotRetry: true,
      );
    case RedemptionState.returnConfirmed:
      return const StatusText(
        'Waiting for the merchant',
        'Your credit was returned. The merchant still has to confirm fulfilment.',
      );
    case RedemptionState.fulfilled:
      return const StatusText('Redeemed', 'The merchant confirmed fulfilment.');
    case RedemptionState.rejected:
      return StatusText(
        'Merchant rejected the redemption',
        v.refundDue
            ? 'You are owed a refund under the issuer\'s policy. Contact the issuer.'
            : 'The merchant rejected the request.',
      );
    case RedemptionState.failed:
      return const StatusText(
        'Return failed',
        'Your credit was not returned.',
        showRetry: true,
      );
    case RedemptionState.cancelled:
      return const StatusText(
        'Cancelled',
        'Nothing was sent.',
        showRetry: true,
      );
  }
}
