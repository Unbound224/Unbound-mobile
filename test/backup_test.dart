import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as s;
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/integrations/secure_wallet_signer.dart';

import 'secure_wallet_signer_test.dart' show MemSecrets, Approval;

void main() {
  test('backup reveals the key only after device approval, and restore brings back the same wallet', () async {
    final a = MemSecrets();
    final approval = Approval(false);
    final w = await SecureWalletSigner.create(a, approval);
    await expectLater(w.revealRecoveryKey(), throwsA(isA<SigningCancelled>()));
    approval.answer = true;
    final key = await w.revealRecoveryKey();
    expect(approval.asked.last, 'Show your recovery key');
    expect(s.KeyPair.fromSecretSeed(key).accountId, w.publicKey);

    final b = MemSecrets();
    // written down in groups of four, lower case: still restores
    final spaced = [
      for (var i = 0; i < key.length; i += 4)
        key.substring(i, i + 4 > key.length ? key.length : i + 4),
    ].join(' ').toLowerCase();
    final restored = await SecureWalletSigner.restore(b, approval, spaced);
    expect(restored.publicKey, w.publicKey);
    expect((await SecureWalletSigner.load(b, approval)).publicKey, w.publicKey);
  });

  test(
    'restore rejects malformed keys and never overwrites an existing wallet',
    () async {
      final store = MemSecrets();
      final approval = Approval(true);
      final good = s.KeyPair.random().secretSeed;
      for (final bad in [
        '',
        'SABC',
        good.replaceRange(10, 11, good[10] == 'A' ? 'B' : 'A'),
        s.KeyPair.random().accountId,
      ]) {
        await expectLater(
          SecureWalletSigner.restore(store, approval, bad),
          throwsA(isA<InvalidRecoveryKey>()),
          reason: bad,
        );
      }
      expect(store.m, isEmpty);
      await SecureWalletSigner.restore(store, approval, good);
      await expectLater(
        SecureWalletSigner.restore(
          store,
          approval,
          s.KeyPair.random().secretSeed,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
