import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import 'harness.dart';

RedemptionView awaiting() => RedemptionView(
  id: 'red_1',
  state: RedemptionState.awaitingReturn,
  asset: AssetRef('SHOP', fxIssuer),
  amount: Amount.parse('30'),
  returnTxHash: fxReturn['hash']! as String,
  unsignedXdr: fxReturn['xdr']! as String,
  refundDue: false,
);

RedemptionView state(RedemptionState s, {bool refund = false}) =>
    RedemptionView(
      id: 'red_1',
      state: s,
      asset: AssetRef('SHOP', fxIssuer),
      amount: Amount.parse('30'),
      returnTxHash: fxReturn['hash']! as String,
      unsignedXdr: null,
      refundDue: refund,
    );

Future<void> openRedeem(
  WidgetTester tester,
  Rig r, {
  String amount = '30',
}) async {
  await r.pump(tester);
  await tester.tap(find.text('Redeem SHOP with the merchant'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('redeem-amount')), amount);
  await tester.tap(find.textContaining('Approve return'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'redemption with the REAL return XDR: signed, ledger-confirmed, but not "Redeemed" until the merchant confirms',
    (tester) async {
      final r = Rig();
      r.api.createRedemptionResult = awaiting();
      r.api.returnResult = state(RedemptionState.returnSubmitted);
      r.api.redemptionScript = [state(RedemptionState.returnConfirmed)];
      await openRedeem(tester, r);
      expect(r.api.returnCalls, 1);
      expect(find.byKey(const Key('redeem-headline')), findsOneWidget);
      expect(find.text('Waiting for the merchant'), findsOneWidget);
      expect(find.text('Redeemed'), findsNothing);
      expect(
        find.textContaining('Unbound does not pay out cash'),
        findsOneWidget,
      );
    },
  );

  testWidgets('merchant fulfilment shows Redeemed', (tester) async {
    final r = Rig();
    r.api.createRedemptionResult = awaiting();
    r.api.returnResult = state(RedemptionState.returnSubmitted);
    r.api.redemptionScript = [state(RedemptionState.fulfilled)];
    await openRedeem(tester, r);
    expect(find.text('Redeemed'), findsOneWidget);
  });

  testWidgets(
    'a merchant rejection after the return surfaces the refund obligation',
    (tester) async {
      final r = Rig();
      r.api.createRedemptionResult = awaiting();
      r.api.returnResult = state(RedemptionState.returnSubmitted);
      r.api.redemptionScript = [state(RedemptionState.rejected, refund: true)];
      await openRedeem(tester, r);
      expect(find.byKey(const Key('refund-due')), findsOneWidget);
      expect(find.textContaining('owed a refund'), findsOneWidget);
    },
  );

  testWidgets('unsupported credit: refusal explained, nothing signed', (
    tester,
  ) async {
    final r = Rig();
    r.api.createRedemptionResult = ApiException(
      'REDEMPTION_UNAVAILABLE',
      'x',
      status: 422,
    );
    await openRedeem(tester, r);
    expect(find.byKey(const Key('redeem-error')), findsOneWidget);
    expect(find.textContaining('does not offer redemption'), findsOneWidget);
    expect(r.api.returnCalls, 0);
  });

  testWidgets('validates the amount against the balance', (tester) async {
    final r = Rig();
    await openRedeem(tester, r, amount: '101');
    expect(find.textContaining('between 0 and 100.00'), findsOneWidget);
    expect(r.api.redemptionKeys, isEmpty);
  });

  testWidgets(
    'a return to anything but the issuer is refused (tampered server payload)',
    (tester) async {
      final r = Rig();
      // the fixture burn pays the issuer; claim a different asset issuer so the destination no longer matches
      r.api.createRedemptionResult = RedemptionView(
        id: 'red_1',
        state: RedemptionState.awaitingReturn,
        asset: AssetRef('SHOP', fxTarget),
        amount: Amount.parse('30'),
        returnTxHash: fxReturn['hash']! as String,
        unsignedXdr: fxReturn['xdr']! as String,
        refundDue: false,
      );
      await openRedeem(tester, r);
      expect(r.api.returnCalls, 0);
      expect(
        find.textContaining('did not match the redemption'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'settings: shows network, address and verified issuers; the seed is never displayed',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      await tester.tap(find.byTooltip('Settings and security'));
      await tester.pumpAndSettle();
      expect(find.text('Stellar Testnet only'), findsOneWidget);
      expect(find.textContaining(fxUser), findsWidgets);
      expect(find.textContaining(fxIssuer), findsWidgets);
      expect(find.textContaining(r.secrets.m.values.single), findsNothing);
    },
  );

  testWidgets(
    'settings: removing the wallet needs confirmation, then returns to onboarding',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      await tester.tap(find.byTooltip('Settings and security'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove wallet from this device'));
      await tester.tap(find.text('Remove wallet from this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep wallet'));
      await tester.pumpAndSettle();
      expect(r.secrets.m, isNotEmpty);
      await tester.tap(find.text('Remove wallet from this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete it'));
      await tester.pumpAndSettle();
      expect(r.secrets.m, isEmpty);
      expect(find.text('Create Testnet wallet'), findsOneWidget);
    },
  );
}
