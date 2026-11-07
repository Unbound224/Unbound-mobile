import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../escrow_test.dart' show view, escrowJson, open, expire, deadline;
import 'harness.dart';
import 'redeem_settings_ui_test.dart' show openRedeem;

void main() {
  testWidgets(
    'escrowed redemption: REAL open_return signed on device, held card, then the timeout refund',
    (tester) async {
      final r = Rig();
      r.api.createRedemptionResult = view(
        'AWAITING_RETURN',
        xdr: open['xdr']! as String,
      );
      r.api.returnResult = view('RETURN_SUBMITTED');
      r.api.redemptionScript = [view('RETURN_CONFIRMED', escrow: escrowJson())];
      await openRedeem(tester, r);
      expect(r.api.returnCalls, 1);
      expect(find.text('Held in escrow'), findsOneWidget);
      expect(
        find.text('Escrow: Locked in the redemption escrow'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('claim-refund')), findsNothing);

      // the merchant never answers; after the deadline the holder can take the credit back
      r.now = deadline.add(const Duration(minutes: 1));
      await tester.tap(find.byKey(const Key('redeem-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('Refund available'), findsOneWidget);
      r.api.claimRefundResult = view(
        'RETURN_CONFIRMED',
        escrow: escrowJson(
          pendingAction: 'EXPIRE',
          pendingXdr: expire['xdr']! as String,
        ),
      );
      r.api.escrowSubmitResult = view(
        'EXPIRED',
        escrow: escrowJson(state: 'EXPIRED_REFUNDED'),
      );
      r.api.redemptionScript = [
        view('EXPIRED', escrow: escrowJson(state: 'EXPIRED_REFUNDED')),
      ];
      await tester.tap(find.byKey(const Key('claim-refund')));
      await tester.pumpAndSettle();
      expect(r.api.escrowSubmissions, hasLength(1));
      expect(find.text('Refunded'), findsOneWidget);
      expect(
        find.text('Escrow: Refunded to your wallet after the deadline'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a refund transaction that does not match is never signed', (
    tester,
  ) async {
    final r = Rig();
    r.api.createRedemptionResult = view(
      'AWAITING_RETURN',
      xdr: open['xdr']! as String,
    );
    r.api.returnResult = view('RETURN_SUBMITTED');
    r.api.redemptionScript = [
      view('RETURN_CONFIRMED', escrow: escrowJson(refundAvailable: true)),
    ];
    await openRedeem(tester, r);
    r.api.claimRefundResult = view(
      'RETURN_CONFIRMED',
      escrow: escrowJson(
        pendingAction: 'EXPIRE',
        pendingXdr: open['xdr']! as String,
      ),
    );
    await tester.tap(find.byKey(const Key('claim-refund')));
    await tester.pumpAndSettle();
    expect(r.api.escrowSubmissions, isEmpty);
    expect(find.textContaining('the refund was not signed'), findsOneWidget);
  });
}
