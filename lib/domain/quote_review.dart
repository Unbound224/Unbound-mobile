import 'amount.dart';
import 'models.dart';

enum ReviewIssue {
  expired,
  wrongNetwork,
  floorBelowSlippage,
  floorAboveExpected,
  slippageTooHigh,
  zeroAmount,
  sameAsset,
}

const int maxSlippageBps = 1000;

/// What the user is shown before approving, plus any reason the quote must not be signed.
class QuoteReview {
  QuoteReview._(this.quote, this.issues, this.remaining);

  final Quote quote;
  final List<ReviewIssue> issues;
  final Duration remaining;

  bool get canProceed => issues.isEmpty;
  bool get needsNewQuote => issues.contains(ReviewIssue.expired);

  /// Worst-case cost to the user relative to the expected output, in base units.
  Amount get maxShortfall => quote.expectedDestination - quote.minDestination;

  /// Plain, non-promissory lines for the confirm screen.
  List<String> get disclosure => [
    'You sell ${quote.sourceAmount.toDisplay()} ${quote.sourceAsset.code} (issuer ${quote.sourceAsset.issuer}).',
    'You receive about ${quote.expectedDestination.toDisplay()} ${quote.targetAsset.code} (issuer ${quote.targetAsset.issuer}).',
    'You are guaranteed at least ${quote.minDestination.toDisplay()} ${quote.targetAsset.code}, or the exchange does not happen.',
    'Network fee: up to ${quote.estimatedFeeStroops} stroops.',
    'Slippage cap: ${(quote.slippageBps / 100).toStringAsFixed(2)}%.',
    ...quote.warnings,
  ];

  static QuoteReview evaluate(
    Quote q,
    DateTime now, {
    String expectedPassphrase = testnetPassphrase,
  }) {
    final issues = <ReviewIssue>[];
    final remaining = q.expiresAt.difference(now);
    if (remaining <= Duration.zero) {
      issues.add(ReviewIssue.expired);
    }
    if (q.networkPassphrase != expectedPassphrase) {
      issues.add(ReviewIssue.wrongNetwork);
    }
    if (q.slippageBps < 0 || q.slippageBps > maxSlippageBps) {
      issues.add(ReviewIssue.slippageTooHigh);
    }
    // Re-derive the floor: a server must not claim a looser floor than the slippage it displays.
    if (q.slippageBps >= 0 &&
        q.slippageBps <= 10000 &&
        q.minDestination <
            q.expectedDestination.applySlippageFloor(q.slippageBps)) {
      issues.add(ReviewIssue.floorBelowSlippage);
    }
    if (q.minDestination > q.expectedDestination) {
      issues.add(ReviewIssue.floorAboveExpected);
    }
    if (q.sourceAmount.isZero || q.minDestination.isZero) {
      issues.add(ReviewIssue.zeroAmount);
    }
    if (q.sourceAsset == q.targetAsset) issues.add(ReviewIssue.sameAsset);
    return QuoteReview._(
      q,
      issues,
      remaining.isNegative ? Duration.zero : remaining,
    );
  }
}
