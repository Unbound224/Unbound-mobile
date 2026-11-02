import 'package:test/test.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/domain/quote_review.dart';

import 'models_test.dart' show quoteJson;

final t0 = DateTime.utc(2026, 11, 2, 12, 0, 0);

QuoteReview review([Map<String, Object?> over = const {}, DateTime? now]) =>
    QuoteReview.evaluate(Quote.fromJson(quoteJson(over)), now ?? t0);

void main() {
  test('a fresh, consistent quote can proceed and discloses issuers, floor, fee and slippage', () {
    final r = review();
    expect(r.canProceed, isTrue);
    expect(r.remaining, const Duration(minutes: 1));
    final text = r.disclosure.join('\n');
    expect(text, contains('GSHOP'));
    expect(text, contains('GUSDC'));
    expect(text, contains('at least 71.28 USDC'));
    expect(text, contains('1.00%'));
    expect(text, contains('100 stroops'));
    expect(r.maxShortfall.toString(), '0.7200000');
  });

  test('an expired quote needs a new quote (no grace)', () {
    final r = review({}, t0.add(const Duration(minutes: 1)));
    expect(r.issues, [ReviewIssue.expired]);
    expect(r.needsNewQuote, isTrue);
    expect(r.remaining, Duration.zero);
  });

  test('refuses a floor looser than the displayed slippage', () {
    expect(
      review({'minDestinationAmount': '60.0000000'}).issues,
      contains(ReviewIssue.floorBelowSlippage),
    );
  });

  test(
    'refuses nonsense floors, high slippage, wrong network and zero amounts',
    () {
      expect(
        review({'minDestinationAmount': '73.0000000'}).issues,
        contains(ReviewIssue.floorAboveExpected),
      );
      expect(
        review({'slippageBps': 2000, 'minDestinationAmount': '57.6000000'})
            .issues,
        contains(ReviewIssue.slippageTooHigh),
      );
      expect(
        review({
          'networkPassphrase': 'Public Global Stellar Network ; September 2015',
        }).issues,
        contains(ReviewIssue.wrongNetwork),
      );
      expect(
        review({'sourceAmount': '0.0000000'}).issues,
        contains(ReviewIssue.zeroAmount),
      );
      expect(
        review({
          'targetAsset': {'code': 'SHOP', 'issuer': 'GSHOP'},
        }).issues,
        contains(ReviewIssue.sameAsset),
      );
    },
  );
}
