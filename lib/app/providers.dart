import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/approval_guard.dart';
import '../domain/models.dart';
import '../flows/exchange_flow.dart';
import '../flows/ports.dart';
import '../flows/redemption_flow.dart';
import '../integrations/core_api.dart';
import '../integrations/local_auth_approval.dart';
import '../integrations/secure_wallet_signer.dart';
import '../integrations/xdr_inspector.dart';

class AppConfig {
  const AppConfig({required this.apiBase});
  final Uri apiBase;

  /// Override at build time: --dart-define=API_URL=http://host:3001 (10.0.2.2 reaches the host from the Android emulator).
  factory AppConfig.fromEnvironment() => AppConfig(
    apiBase: Uri.parse(
      const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://10.0.2.2:3001',
      ),
    ),
  );
}

final configProvider = Provider<AppConfig>((_) => AppConfig.fromEnvironment());
final secretStoreProvider = Provider<SecretStore>(
  (_) => SecureStorageKeyValueStore(),
);
final userApprovalProvider = Provider<UserApproval>((_) => LocalAuthApproval());
final pendingStoreProvider = Provider<PendingStore>(
  (_) => InMemoryPendingStore(),
);
final clockProvider = Provider<DateTime Function()>(
  (_) =>
      () => DateTime.now().toUtc(),
);
final transactionInspectorProvider = Provider<TransactionInspector>(
  (_) => const StellarXdrInspector(),
);

/// Session bearer token. Memory only: never persisted, so a restart requires signing in again.
class SessionToken extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? token) => state = token;
}

final sessionTokenProvider = NotifierProvider<SessionToken, String?>(
  SessionToken.new,
);

final coreApiProvider = Provider<CoreApi>(
  (ref) => HttpCoreApi(
    baseUri: ref.watch(configProvider).apiBase,
    tokenProvider: () => ref.read(sessionTokenProvider),
  ),
);

/// The on-device wallet, or null when none exists yet.
class WalletController extends AsyncNotifier<SecureWalletSigner?> {
  @override
  Future<SecureWalletSigner?> build() async {
    final store = ref.watch(secretStoreProvider);
    if (!await SecureWalletSigner.exists(store)) {
      return null;
    }
    return SecureWalletSigner.load(store, ref.watch(userApprovalProvider));
  }

  Future<void> create() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => SecureWalletSigner.create(
        ref.read(secretStoreProvider),
        ref.read(userApprovalProvider),
      ),
    );
  }

  /// Recovery: put a written-down key back on this device. Throws [InvalidRecoveryKey].
  Future<void> restore(String recoveryKey) async {
    final w = await SecureWalletSigner.restore(
      ref.read(secretStoreProvider),
      ref.read(userApprovalProvider),
      recoveryKey,
    );
    state = AsyncData(w);
  }

  Future<void> wipe() async {
    final w = state.value;
    if (w != null) {
      await w.wipe();
    }
    ref.read(sessionTokenProvider.notifier).set(null);
    state = const AsyncData(null);
  }

  /// Proves wallet control to unbound-core and stores the session token in memory.
  Future<void> signIn() async {
    final w = state.value;
    if (w == null) {
      throw WalletNotCreated();
    }
    final api = ref.read(coreApiProvider);
    final ch = await api.walletChallenge(w.publicKey);
    final sig = await w.signLoginChallenge(ch.message);
    ref
        .read(sessionTokenProvider.notifier)
        .set(
          await api.walletVerify(
            challengeId: ch.challengeId,
            signatureBase64: sig,
          ),
        );
  }
}

final walletProvider =
    AsyncNotifierProvider<WalletController, SecureWalletSigner?>(
      WalletController.new,
    );

final portfolioProvider = FutureProvider.autoDispose<PortfolioView>(
  (ref) => ref.watch(coreApiProvider).portfolio(),
);
final targetsProvider = FutureProvider.autoDispose<List<AssetRef>>(
  (ref) => ref.watch(coreApiProvider).listTargets(),
);

/// Polling cadence for flows; tests override it with an instant delay and a small poll budget.
class FlowTiming {
  const FlowTiming({this.delay, this.maxPolls = 30});
  final Delay? delay;
  final int maxPolls;
}

final flowTimingProvider = Provider<FlowTiming>((_) => const FlowTiming());

final exchangeFlowProvider = Provider<ExchangeFlow>((ref) {
  final signer = ref.watch(walletProvider).value;
  if (signer == null) {
    throw WalletNotCreated();
  }
  return ExchangeFlow(
    api: ref.watch(coreApiProvider),
    signer: signer,
    guard: ApprovalGuard(ref.watch(transactionInspectorProvider)),
    store: ref.watch(pendingStoreProvider),
    clock: ref.watch(clockProvider),
    delay: ref.watch(flowTimingProvider).delay ?? _realDelay,
    maxPolls: ref.watch(flowTimingProvider).maxPolls,
  );
});

final redemptionFlowProvider = Provider<RedemptionFlow>((ref) {
  final signer = ref.watch(walletProvider).value;
  if (signer == null) {
    throw WalletNotCreated();
  }
  return RedemptionFlow(
    api: ref.watch(coreApiProvider),
    signer: signer,
    inspector: ref.watch(transactionInspectorProvider),
    store: ref.watch(pendingStoreProvider),
    delay: ref.watch(flowTimingProvider).delay ?? _realDelay,
    maxPolls: ref.watch(flowTimingProvider).maxPolls,
  );
});

Future<void> _realDelay(Duration d) => Future<void>.delayed(d);
