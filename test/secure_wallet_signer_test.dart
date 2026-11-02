import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as s;
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/integrations/secure_wallet_signer.dart';

/// TEST ADAPTERS (not the platform keystore / biometrics).
class MemSecrets implements SecretStore {
  final Map<String, String> m = {};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

class Approval implements UserApproval {
  Approval(this.answer);
  bool answer;
  final List<String> asked = [];
  @override
  Future<bool> confirm(String reason) async {
    asked.add(reason);
    return answer;
  }
}

void main() {
  final fx = jsonDecode(
    File('test/fixtures/transactions.v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final settlement = fx['settlement']! as Map<String, Object?>;

  /// The producer derived this synthetic key from a public label; deriving it here lets us prove
  /// that Dart signing equals TypeScript signing byte for byte.
  s.KeyPair fixtureUser() => s.KeyPair.fromSecretSeedList(
    s.Util.hash(Uint8List.fromList(utf8.encode('unbound-fixture:user'))),
  );

  test(
    'creates a wallet, never exposes the seed, and reloads the same key',
    () async {
      final store = MemSecrets();
      final w = await SecureWalletSigner.create(store, Approval(true));
      expect(w.publicKey, startsWith('G'));
      expect(w.toString(), isNot(contains(store.m.values.single)));
      final again = await SecureWalletSigner.load(store, Approval(true));
      expect(again.publicKey, w.publicKey);
      expect(await SecureWalletSigner.exists(store), isTrue);
    },
  );

  test(
    'refuses to overwrite an existing wallet; load without one fails',
    () async {
      final store = MemSecrets();
      await expectLater(
        SecureWalletSigner.load(store, Approval(true)),
        throwsA(isA<WalletNotCreated>()),
      );
      await SecureWalletSigner.create(store, Approval(true));
      await expectLater(
        SecureWalletSigner.create(store, Approval(true)),
        throwsStateError,
      );
    },
  );

  test('signing the real fixture reproduces the TypeScript-signed envelope byte for byte', () async {
    final store = MemSecrets()
      ..m['unbound.wallet.seed.v1'] = fixtureUser().secretSeed;
    final w = await SecureWalletSigner.load(store, Approval(true));
    expect(w.publicKey, (fx['accounts']! as Map<String, Object?>)['user']);
    final signed = await w.sign(
      settlement['xdr']! as String,
      testnetPassphrase,
    );
    expect(signed, settlement['signedXdr']);
  });

  test('asks the person first; a "no" signs nothing', () async {
    final store = MemSecrets()
      ..m['unbound.wallet.seed.v1'] = fixtureUser().secretSeed;
    final approval = Approval(false);
    final w = await SecureWalletSigner.load(store, approval);
    await expectLater(
      w.sign(settlement['xdr']! as String, testnetPassphrase),
      throwsA(isA<SigningCancelled>()),
    );
    expect(approval.asked, hasLength(1));
  });

  test('refuses other networks and transactions from other accounts', () async {
    final store = MemSecrets();
    final w = await SecureWalletSigner.create(
      store,
      Approval(true),
    ); // a different key than the fixture's source
    await expectLater(
      w.sign(settlement['xdr']! as String, testnetPassphrase),
      throwsArgumentError,
    );
    final store2 = MemSecrets()
      ..m['unbound.wallet.seed.v1'] = fixtureUser().secretSeed;
    final w2 = await SecureWalletSigner.load(store2, Approval(true));
    await expectLater(
      w2.sign(
        settlement['xdr']! as String,
        'Public Global Stellar Network ; September 2015',
      ),
      throwsArgumentError,
    );
  });

  test('login challenge signatures verify against the public key', () async {
    final w = await SecureWalletSigner.create(MemSecrets(), Approval(true));
    const msg = 'unbound-auth:v1:TESTNET:abc:GKEY';
    final sig = await w.signLoginChallenge(msg);
    expect(
      s.KeyPair.fromAccountId(w.publicKey)
          .verify(Uint8List.fromList(msg.codeUnits), base64Decode(sig)),
      isTrue,
    );
  });

  test('wipe removes the seed', () async {
    final store = MemSecrets();
    final w = await SecureWalletSigner.create(store, Approval(true));
    await w.wipe();
    expect(store.m, isEmpty);
  });
}
