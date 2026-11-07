import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as s;

import '../domain/models.dart';
import '../flows/ports.dart';

/// Minimal secret storage port. Production: [SecureStorageKeyValueStore] (Android Keystore / iOS Keychain).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageKeyValueStore implements SecretStore {
  SecureStorageKeyValueStore([FlutterSecureStorage? s])
    : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Port: ask the person to approve a signing request (biometrics / device PIN in production).
/// No production implementation is wired yet; see README.
abstract class UserApproval {
  Future<bool> confirm(String reason);
}

class WalletNotCreated implements Exception {
  @override
  String toString() => 'WalletNotCreated';
}

class InvalidRecoveryKey implements Exception {
  @override
  String toString() => 'InvalidRecoveryKey';
}

/// On-device Testnet wallet. The secret seed is written only to [SecretStore] and is never logged
/// or sent anywhere. The single exception is [revealRecoveryKey], which shows it to the person
/// (after device approval) so they can write it down; nothing else returns it.
class SecureWalletSigner implements WalletSigner {
  SecureWalletSigner._(this._store, this._approval, this._kp);

  static const _seedKey = 'unbound.wallet.seed.v1';
  final SecretStore _store;
  final UserApproval _approval;
  final s.KeyPair _kp;

  /// Loads the stored wallet or throws [WalletNotCreated].
  static Future<SecureWalletSigner> load(
    SecretStore store,
    UserApproval approval,
  ) async {
    final seed = await store.read(_seedKey);
    if (seed == null) {
      throw WalletNotCreated();
    }
    return SecureWalletSigner._(
      store,
      approval,
      s.KeyPair.fromSecretSeed(seed),
    );
  }

  /// Creates a fresh random wallet. Refuses to overwrite an existing one.
  static Future<SecureWalletSigner> create(
    SecretStore store,
    UserApproval approval,
  ) async {
    if (await store.read(_seedKey) != null) {
      throw StateError('a wallet already exists on this device');
    }
    final kp = s.KeyPair.random();
    await store.write(_seedKey, kp.secretSeed);
    return SecureWalletSigner._(store, approval, kp);
  }

  /// Restores a wallet from a written-down recovery key (Stellar secret seed, `S...`).
  /// Refuses to overwrite an existing wallet and rejects malformed keys before storing anything.
  static Future<SecureWalletSigner> restore(
    SecretStore store,
    UserApproval approval,
    String recoveryKey,
  ) async {
    if (await store.read(_seedKey) != null) {
      throw StateError('a wallet already exists on this device');
    }
    final seed = recoveryKey.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final s.KeyPair kp;
    try {
      if (!s.StrKey.isValidStellarSecretSeed(seed)) throw InvalidRecoveryKey();
      kp = s.KeyPair.fromSecretSeed(seed);
    } on Object {
      throw InvalidRecoveryKey();
    }
    await store.write(_seedKey, kp.secretSeed);
    return SecureWalletSigner._(store, approval, kp);
  }

  /// Backup: returns the recovery key for display ONLY after the person approves on the device.
  /// The caller must never log, copy or transmit it.
  Future<String> revealRecoveryKey() async {
    if (!await _approval.confirm('Show your recovery key')) {
      throw SigningCancelled();
    }
    final seed = await _store.read(_seedKey);
    if (seed == null) throw WalletNotCreated();
    return seed;
  }

  static Future<bool> exists(SecretStore store) async =>
      await store.read(_seedKey) != null;

  /// Signs a challenge string (wallet login with unbound-core). Needs approval like a transaction.
  Future<String> signLoginChallenge(String message) async {
    if (!await _approval.confirm('Sign in to Unbound')) {
      throw SigningCancelled();
    }
    return _b64(_kp.sign(Uint8List.fromList(message.codeUnits)));
  }

  @override
  String get publicKey => _kp.accountId;

  @override
  Future<String> sign(String unsignedXdr, String networkPassphrase) async {
    if (networkPassphrase != testnetPassphrase) {
      throw ArgumentError('only Testnet is supported');
    }
    final t = s.AbstractTransaction.fromEnvelopeXdrString(unsignedXdr);
    if (t is! s.Transaction || t.sourceAccount.accountId != publicKey) {
      throw ArgumentError(
        'refusing to sign a transaction this wallet does not own',
      );
    }
    if (!await _approval.confirm('Approve this transaction')) {
      throw SigningCancelled();
    }
    t.sign(_kp, s.Network.TESTNET);
    return t.toEnvelopeXdrBase64();
  }

  /// Removes the wallet from this device. Irreversible without a backup of the seed.
  Future<void> wipe() => _store.delete(_seedKey);

  static String _b64(List<int> bytes) => base64Encode(bytes);
}
