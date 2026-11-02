import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import 'harness.dart';

void main() {
  testWidgets(
    'first run: Testnet notice, create wallet, then sign in reaches the inventory',
    (tester) async {
      final r = Rig(withWallet: false);
      await r.pump(tester, signedIn: false);
      expect(find.textContaining('Testnet demo'), findsOneWidget);
      expect(find.textContaining('never sent anywhere'), findsOneWidget);
      await tester.tap(find.text('Create Testnet wallet'));
      await tester.pumpAndSettle();
      expect(r.secrets.m, isNotEmpty);
      expect(find.byKey(const Key('wallet-key')), findsOneWidget);
      expect(
        find.textContaining(r.secrets.m.values.single),
        findsNothing,
      ); // the seed is never rendered
      await tester.tap(find.text('Sign in with my wallet'));
      await tester.pumpAndSettle();
      expect(r.api.loginSignatures, hasLength(1));
      expect(find.text('My credits'), findsOneWidget);
    },
  );

  testWidgets('sign-in failure while offline is explained and retryable', (
    tester,
  ) async {
    final r = Rig();
    r.api.verifyError = ApiException('NETWORK', 'offline');
    await r.pump(tester, signedIn: false);
    await tester.tap(find.text('Sign in with my wallet'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cannot reach the Unbound service'),
      findsOneWidget,
    );
    r.api.verifyError = null;
    await tester.tap(find.text('Sign in with my wallet'));
    await tester.pumpAndSettle();
    expect(find.text('My credits'), findsOneWidget);
  });

  testWidgets(
    'cancelling the biometric prompt leaves the user signed out with a clear message',
    (tester) async {
      final r = Rig();
      r.approval.answer = false;
      await r.pump(tester, signedIn: false);
      await tester.tap(find.text('Sign in with my wallet'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signin-error')), findsOneWidget);
      expect(find.textContaining('cancelled'), findsOneWidget);
      expect(r.api.loginSignatures, isEmpty);
    },
  );

  testWidgets(
    'inventory: verified credit can be exchanged/redeemed; unverified credit gets no actions and no value',
    (tester) async {
      final r = Rig();
      r.api.portfolioResult = PortfolioView(
        holdings: [
          holding('SHOP', fxIssuer, '20', HoldingStatus.redeemable),
          holding('RND', 'GRANDOM', '1000', HoldingStatus.unverified),
          holding('OLD', 'GOLD', '5', HoldingStatus.expired),
          holding('FRZ', 'GFRZ', '3', HoldingStatus.frozen),
        ],
        notice: 'Only REDEEMABLE credit can be exchanged or redeemed.',
      );
      await r.pump(tester);
      expect(find.text('Exchange SHOP'), findsOneWidget);
      expect(find.text('Redeem SHOP with the merchant'), findsOneWidget);
      expect(find.text('Exchange RND'), findsNothing);
      expect(find.textContaining('has no usable value here'), findsOneWidget);
      expect(find.textContaining('terms have expired'), findsOneWidget);
      expect(find.textContaining('frozen your balance'), findsOneWidget);
      expect(
        find.byType(FilledButton),
        findsOneWidget,
      ); // only SHOP gets a primary action
    },
  );

  testWidgets('inventory: empty state', (tester) async {
    final r = Rig();
    r.api.portfolioResult = PortfolioView(holdings: [], notice: 'n');
    await r.pump(tester);
    expect(find.byKey(const Key('inventory-empty')), findsOneWidget);
  });

  testWidgets('inventory: offline message with retry', (tester) async {
    final r = Rig();
    r.api.portfolioError = ApiException('NETWORK', 'offline');
    await r.pump(tester);
    expect(find.textContaining('appear to be offline'), findsOneWidget);
    r.api.portfolioError = null;
    r.api.portfolioResult = PortfolioView(
      holdings: [holding('SHOP', fxIssuer, '1', HoldingStatus.redeemable)],
      notice: 'n',
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Exchange SHOP'), findsOneWidget);
  });
}
