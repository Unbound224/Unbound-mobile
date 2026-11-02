import 'dart:math';

/// Port: secure signing on the device. The secret NEVER leaves the implementation.
/// Production implementation (Keystore/Keychain + Stellar signing) does not exist yet.
abstract class WalletSigner {
  String get publicKey;

  /// Returns the signed envelope XDR for the given unsigned XDR. May throw [SigningCancelled].
  Future<String> sign(String unsignedXdr, String networkPassphrase);
}

class SigningCancelled implements Exception {}

/// Port: small durable store for idempotency keys and in-flight ids, so a crash/restart
/// resumes the SAME business operation instead of creating a second one.
/// The only implementation here is [InMemoryPendingStore] (does not survive restarts).
abstract class PendingStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class InMemoryPendingStore implements PendingStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

String newIdempotencyKey([Random? rng]) {
  final r = rng ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return 'idem-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// Returns the persisted key for [slot], creating and persisting one first if needed.
Future<String> keyFor(
  PendingStore store,
  String slot, {
  String Function()? generator,
}) async {
  final existing = await store.read('key:$slot');
  if (existing != null) return existing;
  final k = (generator ?? newIdempotencyKey)();
  await store.write('key:$slot', k);
  return k;
}
