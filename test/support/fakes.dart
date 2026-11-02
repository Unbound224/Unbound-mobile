// TEST ADAPTERS ONLY. None of these talk to Stellar or unbound-core.
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/approval_guard.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import '../models_test.dart' show quoteJson;

final hash64 = 'a' * 64;

class FakeSigner implements WalletSigner {
  FakeSigner({this.publicKey = 'GME'});
  @override
  final String publicKey;
  int signCalls = 0;
  bool cancel = false;
  @override
  Future<String> sign(String unsignedXdr, String networkPassphrase) async {
    if (cancel) {
      throw SigningCancelled();
    }
    signCalls++;
    return 'SIGNED:$unsignedXdr';
  }
}

/// Canned decoder: reports exactly what the default quote asks for unless overridden.
class FakeInspector implements TransactionInspector {
  String destination = 'GME';
  @override
  TxSummary inspect(String unsignedXdr) => TxSummary(
    networkPassphrase: testnetPassphrase,
    sourceAccount: 'GME',
    operationType: 'pathPaymentStrictSend',
    sendAsset: const AssetRef('SHOP', 'GSHOP'),
    sendAmount: Amount.parse('80'),
    destAsset: const AssetRef('USDC', 'GUSDC'),
    destMin: Amount.parse('71.28'),
    destination: destination,
    path: const [],
    hash: hash64,
    operationCount: 1,
  );
}

IntentView intentView(
  IntentState s, {
  String? xdr,
  Amount? out,
  String? reason,
}) => IntentView(
  id: 'int_1',
  state: s,
  quoteId: 'q_1',
  txHash: hash64,
  unsignedXdr: s == IntentState.awaitingSignature ? (xdr ?? 'XDR') : null,
  failureReason: reason,
  amountOutActual: out,
  ledger: null,
);

/// Scriptable CoreApi. createIntent is idempotent per key like the real server.
class FakeCoreApi implements CoreApi {
  final Map<String, IntentView> createdByKey = {};
  final List<String> createKeys = [];
  final List<String> submitKeys = [];
  int submitCalls = 0;
  int getCalls = 0;

  /// Scripts consumed one per getIntent call; the last repeats.
  List<Object> getScript = [
    intentView(IntentState.confirmed, out: Amount.parse('72')),
  ];
  Object? submitResult;
  Object? createError;
  bool failFirstCreateAfterServerCreated = false;

  @override
  Future<IntentView> createIntent({
    required String quoteId,
    required String idempotencyKey,
  }) async {
    createKeys.add(idempotencyKey);
    final existing = createdByKey[idempotencyKey];
    final v = existing ?? intentView(IntentState.awaitingSignature);
    createdByKey[idempotencyKey] = v;
    if (createError != null) {
      throw createError!;
    }
    if (failFirstCreateAfterServerCreated) {
      failFirstCreateAfterServerCreated = false;
      throw ApiException('NETWORK', 'timeout');
    }
    return v;
  }

  @override
  Future<IntentView> submitIntent({
    required String id,
    required String signedXdr,
    required String idempotencyKey,
  }) async {
    submitCalls++;
    submitKeys.add(idempotencyKey);
    final r = submitResult ?? intentView(IntentState.submitted);
    if (r is Exception) {
      throw r;
    }
    return r as IntentView;
  }

  @override
  Future<IntentView> getIntent(String id) async {
    final i = getCalls < getScript.length ? getCalls : getScript.length - 1;
    getCalls++;
    final r = getScript[i];
    if (r is Exception) {
      throw r;
    }
    return r as IntentView;
  }

  @override
  Future<Quote> requestQuote({
    required AssetRef source,
    required AssetRef target,
    required String sourceAmount,
    required int slippageBps,
    required String destinationAccount,
  }) async => Quote.fromJson(quoteJson());

  @override
  Future<List<EligibleAsset>> listAssets() async => [];
  @override
  Future<RedemptionView> createRedemption({
    required AssetRef asset,
    required String amount,
    required String holder,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<RedemptionView> getRedemption(String id) => throw UnimplementedError();
  @override
  Future<RedemptionView> submitRedemptionReturn({
    required String id,
    required String signedXdr,
  }) => throw UnimplementedError();
}
