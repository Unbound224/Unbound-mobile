import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import '../support/fakes.dart';
import 'harness.dart';

Rig rig() {
  final r = Rig();
  r.api.quoteOverride = fxQuote;
  r.api.awaitingOverride = IntentView(
    id: 'int_1',
    state: IntentState.awaitingSignature,
    quoteId: fxQuote.quoteId,
    txHash: fxSettlement['hash']! as String,
    unsignedXdr: fxSettlement['xdr']! as String,
    failureReason: null,
    amountOutActual: null,
    ledger: null,
  );
  return r;
}

Future<void> toReview(WidgetTester tester) async {
  await tester.tap(find.text('Exchange SHOP'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('amount')), '80');
  await tester.tap(find.byKey(const Key('target')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('USDC').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Get quote'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'full exchange with REAL fixture XDR: review discloses issuers/floor, user signs, ledger-confirmed result',
    (tester) async {
      final r = rig();
      r.api.getScript = [
        intentView(IntentState.confirmed, out: Amount.parse('72')),
      ];
      await r.pump(tester);
      await toReview(tester);
      expect(find.text('Review exchange'), findsOneWidget);
      expect(find.textContaining('at least 71.28 USDC'), findsOneWidget);
      expect(find.textContaining(fxIssuer), findsWidgets);
      expect(find.textContaining(fxTarget), findsWidgets);
      expect(find.textContaining('Network fee'), findsOneWidget);
      await tester.tap(find.text('Approve and sign'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('status-headline')), findsOneWidget);
      expect(find.text('Exchange complete'), findsOneWidget);
      expect(find.textContaining('You received 72.00'), findsOneWidget);
      expect(r.api.submitCalls, 1);
    },
  );

  testWidgets('input validation: bad amount, over balance, missing target', (
    tester,
  ) async {
    final r = rig();
    await r.pump(tester);
    await tester.tap(find.text('Exchange SHOP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '1e3');
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    expect(find.textContaining('up to 7 decimals'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '101');
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You only hold 100.00 SHOP'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '10');
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Choose what you want to receive'),
      findsOneWidget,
    );
    expect(find.text('Review exchange'), findsNothing);
  });

  testWidgets('no liquidity: clear message, nothing spent, no review screen', (
    tester,
  ) async {
    final r = rig();
    r.api.quoteError = ApiException('NO_ROUTE', 'no route', status: 422);
    await r.pump(tester);
    await toReview(tester);
    expect(find.textContaining('no liquidity'), findsOneWidget);
    expect(find.text('Review exchange'), findsNothing);
  });

  testWidgets(
    'an expired quote cannot be approved; the user is sent for a new one',
    (tester) async {
      final r = rig();
      r.now = fxQuote.expiresAt;
      await r.pump(tester);
      await toReview(tester);
      expect(find.byKey(const Key('expired')), findsOneWidget);
      expect(find.text('Approve and sign'), findsNothing);
      expect(find.text('Get a new quote'), findsOneWidget);
      expect(r.api.createKeys, isEmpty);
    },
  );

  testWidgets(
    'a server transaction that does not match the quote is NOT signed',
    (tester) async {
      final r = rig();
      r.api.awaitingOverride = IntentView(
        id: 'int_1',
        state: IntentState.awaitingSignature,
        quoteId: fxQuote.quoteId,
        txHash: 'f' * 64, // advertised hash lies
        unsignedXdr: fxSettlement['xdr']! as String,
        failureReason: null,
        amountOutActual: null,
        ledger: null,
      );
      await r.pump(tester);
      await toReview(tester);
      await tester.tap(find.text('Approve and sign'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-message')), findsOneWidget);
      expect(find.textContaining('did not match the quote'), findsOneWidget);
      expect(r.api.submitCalls, 0);
    },
  );

  testWidgets('declining the biometric prompt sends nothing', (tester) async {
    final r = rig();
    r.approval.answer = false;
    await r.pump(tester);
    await toReview(tester);
    await tester.tap(find.text('Approve and sign'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Signing was cancelled'), findsOneWidget);
    expect(r.api.submitCalls, 0);
  });

  testWidgets(
    'unknown outcome shows Confirming, warns not to retry and offers no restart',
    (tester) async {
      final r = rig();
      r.api.submitResult = ApiException('NETWORK', 'timeout');
      r.api.getScript = [intentView(IntentState.reconciling)];
      await r.pump(tester);
      await toReview(tester);
      await tester.tap(find.text('Approve and sign'));
      await tester.pumpAndSettle();
      expect(find.text('Confirming'), findsOneWidget);
      expect(find.byKey(const Key('do-not-retry')), findsOneWidget);
      expect(find.text('Start over with a new quote'), findsNothing);
      expect(find.textContaining('Check'), findsOneWidget);
      expect(find.text('Exchange complete'), findsNothing);
      expect(r.api.submitCalls, 1);
    },
  );

  testWidgets(
    'a failed exchange says nothing was exchanged and offers a fresh start',
    (tester) async {
      final r = rig();
      r.api.getScript = [
        intentView(IntentState.failed, reason: 'MIN_OUTPUT_VIOLATION'),
      ];
      await r.pump(tester);
      await toReview(tester);
      await tester.tap(find.text('Approve and sign'));
      await tester.pumpAndSettle();
      expect(find.text('Exchange did not happen'), findsOneWidget);
      expect(find.textContaining('MIN_OUTPUT_VIOLATION'), findsOneWidget);
      expect(find.text('Start over with a new quote'), findsOneWidget);
    },
  );
}
