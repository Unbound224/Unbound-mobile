import 'amount.dart';
import 'models.dart';

/// What an unsigned transaction would actually do, as decoded by a [TransactionInspector].
class TxSummary {
  const TxSummary({
    required this.networkPassphrase,
    required this.sourceAccount,
    required this.operationType,
    required this.sendAsset,
    required this.sendAmount,
    required this.destAsset,
    required this.destMin,
    required this.destination,
    required this.path,
    required this.hash,
    required this.operationCount,
    this.contractCall,
  });

  final String networkPassphrase;
  final String sourceAccount;
  final String operationType;
  final AssetRef sendAsset;
  final Amount sendAmount;
  final AssetRef destAsset;
  final Amount destMin;
  final String destination;
  final List<AssetRef> path;
  final String hash;
  final int operationCount;

  /// Set for a Soroban `invokeHostFunction` (the redemption escrow); null for classic payments.
  final ContractCall? contractCall;
}

/// A decoded contract invocation. Args: account/contract strkeys as String, integers as BigInt,
/// bytes as lowercase hex.
class ContractCall {
  const ContractCall(this.contractId, this.function, this.args);
  final String contractId;
  final String function;
  final List<Object?> args;
}

/// Port: decode XDR locally so the user signs what the quote said, not what the server claims.
/// NO production implementation exists yet (needs a Dart Stellar XDR decoder); see README.
abstract class TransactionInspector {
  TxSummary inspect(String unsignedXdr);
}

enum RefusalReason {
  wrongState,
  quoteMismatch,
  missingPayload,
  expired,
  wrongNetwork,
  notSingleOperation,
  wrongOperation,
  assetMismatch,
  amountMismatch,
  floorMismatch,
  routeMismatch,
  foreignDestination,
  wrongSource,
  hashMismatch,
  inspectionFailed,
}

class ApprovalRefused implements Exception {
  ApprovalRefused(this.reasons);
  final List<RefusalReason> reasons;
  @override
  String toString() => 'ApprovalRefused($reasons)';
}

class ApprovedTransaction {
  const ApprovedTransaction(
    this.unsignedXdr,
    this.networkPassphrase,
    this.expectedHash,
  );
  final String unsignedXdr;
  final String networkPassphrase;
  final String expectedHash;
}

/// Last line of defence before the secure signer is invoked. Pure and deterministic.
class ApprovalGuard {
  const ApprovalGuard(this.inspector);
  final TransactionInspector inspector;

  /// [ownAccounts]: public keys of wallets bound to this device/user. A swap must pay one of them.
  ApprovedTransaction check({
    required Quote quote,
    required IntentView intent,
    required Set<String> ownAccounts,
    required String signingAccount,
    required DateTime now,
  }) {
    final bad = <RefusalReason>[];
    if (intent.state != IntentState.awaitingSignature) {
      bad.add(RefusalReason.wrongState);
    }
    if (intent.quoteId != quote.quoteId) bad.add(RefusalReason.quoteMismatch);
    final xdr = intent.unsignedXdr;
    final hash = intent.txHash;
    if (xdr == null || xdr.isEmpty || hash == null || hash.isEmpty) {
      bad.add(RefusalReason.missingPayload);
    }
    if (!now.isBefore(quote.expiresAt)) bad.add(RefusalReason.expired);
    if (xdr == null || hash == null || xdr.isEmpty || hash.isEmpty) {
      throw ApprovalRefused(bad);
    }

    final TxSummary s;
    try {
      s = inspector.inspect(xdr);
    } on Object {
      throw ApprovalRefused([...bad, RefusalReason.inspectionFailed]);
    }
    if (s.networkPassphrase != testnetPassphrase ||
        s.networkPassphrase != quote.networkPassphrase) {
      bad.add(RefusalReason.wrongNetwork);
    }
    if (s.operationCount != 1) bad.add(RefusalReason.notSingleOperation);
    if (s.operationType != 'pathPaymentStrictSend') {
      bad.add(RefusalReason.wrongOperation);
    }
    if (s.sendAsset != quote.sourceAsset || s.destAsset != quote.targetAsset) {
      bad.add(RefusalReason.assetMismatch);
    }
    if (s.sendAmount != quote.sourceAmount) {
      bad.add(RefusalReason.amountMismatch);
    }
    if (s.destMin != quote.minDestination) bad.add(RefusalReason.floorMismatch);
    if (s.path.length != quote.path.length || !_samePath(s.path, quote.path)) {
      bad.add(RefusalReason.routeMismatch);
    }
    if (!ownAccounts.contains(s.destination)) {
      bad.add(RefusalReason.foreignDestination);
    }
    if (s.sourceAccount != signingAccount) bad.add(RefusalReason.wrongSource);
    if (s.hash != hash) bad.add(RefusalReason.hashMismatch);
    if (bad.isNotEmpty) throw ApprovalRefused(bad);
    return ApprovedTransaction(xdr, s.networkPassphrase, hash);
  }

  static bool _samePath(List<AssetRef> a, List<AssetRef> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
