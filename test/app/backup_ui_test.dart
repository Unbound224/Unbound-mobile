import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as s;

import 'harness.dart';

void main() {
  testWidgets(
    'settings -> backup: warnings first, approval, then the key in groups; hide again',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      await tester.tap(find.byTooltip('Settings and security'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-backup')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Anyone who sees it controls the wallet'),
        findsOneWidget,
      );
      final reveal = find.byKey(const Key('backup-reveal'));
      expect(tester.widget<FilledButton>(reveal).onPressed, isNull);
      r.approval.answer = false;
      await tester.tap(find.byKey(const Key('backup-understood')));
      await tester.pumpAndSettle();
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-error')), findsOneWidget);
      expect(find.byKey(const Key('backup-key')), findsNothing);
      r.approval.answer = true;
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      final seed = fixtureUserSeed();
      expect(find.text(seed.substring(0, 4)), findsOneWidget);
      expect(find.text(seed.substring(52)), findsOneWidget);
      await tester.tap(find.byKey(const Key('backup-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-key')), findsNothing);
    },
  );

  testWidgets(
    'first launch: restore from a recovery key instead of creating a wallet',
    (tester) async {
      final r = Rig(withWallet: false);
      await r.pump(tester, signedIn: false);
      await tester.tap(find.byKey(const Key('open-restore')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('restore-key')),
        'SNOTAREALKEY',
      );
      await tester.tap(find.byKey(const Key('restore-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restore-error')), findsOneWidget);
      expect(r.secrets.m, isEmpty);
      final seed = fixtureUserSeed();
      await tester.enterText(find.byKey(const Key('restore-key')), seed);
      await tester.tap(find.byKey(const Key('restore-submit')));
      await tester.pumpAndSettle();
      expect(r.secrets.m.values.single, seed);
      expect(
        find.text('Wallet: ${s.KeyPair.fromSecretSeed(seed).accountId}'),
        findsOneWidget,
      );
    },
  );
}
