import 'amount.dart';

const String testnetPassphrase = 'Test SDF Network ; September 2015';

/// Thrown when a server payload violates the contract. Clients fail closed.
class ContractException implements Exception {
  ContractException(this.message);
  final String message;
  @override
  String toString() => 'ContractException: $message';
}

T _need<T>(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is! T) throw ContractException('field "$k" missing or wrong type');
  return v;
}

class AssetRef {
  const AssetRef(this.code, this.issuer);

  /// `issuer == null` means native XLM.
  final String code;
  final String? issuer;

  factory AssetRef.fromJson(Map<String, Object?> j) {
    final issuer = j['issuer'];
    if (issuer != null && issuer is! String) {
      throw ContractException('bad issuer');
    }
    return AssetRef(_need<String>(j, 'code'), issuer as String?);
  }

  Map<String, Object?> toJson() => {'code': code, 'issuer': issuer};

  String get key => issuer == null ? 'native' : '$code:$issuer';

  @override
  bool operator ==(Object other) => other is AssetRef && other.key == key;
  @override
  int get hashCode => key.hashCode;
  @override
  String toString() => key;
}

/// Indicative, expiring quote exactly as issued by the core API (stellar schema 1.0).
class Quote {
  Quote({
    required this.quoteId,
    required this.networkPassphrase,
    required this.sourceAsset,
    required this.targetAsset,
    required this.sourceAmount,
    required this.expectedDestination,
    required this.minDestination,
    required this.slippageBps,
    required this.path,
    required this.estimatedFeeStroops,
    required this.expiresAt,
    required this.issuedAt,
    required this.warnings,
  });

  factory Quote.fromJson(Map<String, Object?> j) {
    if (_need<String>(j, 'schemaVersion') != '1.0') {
      throw ContractException('unsupported quote schemaVersion');
    }
    if (_need<String>(j, 'network') != 'TESTNET') {
      throw ContractException('quote is not for TESTNET');
    }
    try {
      return Quote(
        quoteId: _need<String>(j, 'quoteId'),
        networkPassphrase: _need<String>(j, 'networkPassphrase'),
        sourceAsset: AssetRef.fromJson(
          _need<Map<String, Object?>>(j, 'sourceAsset'),
        ),
        targetAsset: AssetRef.fromJson(
          _need<Map<String, Object?>>(j, 'targetAsset'),
        ),
        sourceAmount: Amount.parse(_need<String>(j, 'sourceAmount')),
        expectedDestination: Amount.parse(
          _need<String>(j, 'expectedDestinationAmount'),
        ),
        minDestination: Amount.parse(_need<String>(j, 'minDestinationAmount')),
        slippageBps: _need<int>(j, 'slippageBps'),
        path: [
          for (final p in _need<List<Object?>>(j, 'path'))
            AssetRef.fromJson(p! as Map<String, Object?>),
        ],
        estimatedFeeStroops: _need<int>(j, 'estimatedFeeStroops'),
        issuedAt: DateTime.parse(_need<String>(j, 'issuedAt')),
        expiresAt: DateTime.parse(_need<String>(j, 'expiresAt')),
        warnings: [
          for (final w in _need<List<Object?>>(j, 'warnings')) w! as String,
        ],
      );
    } on FormatException catch (e) {
      throw ContractException('malformed quote: ${e.message}');
    } on TypeError {
      throw ContractException('malformed quote');
    }
  }

  final String quoteId;
  final String networkPassphrase;
  final AssetRef sourceAsset;
  final AssetRef targetAsset;
  final Amount sourceAmount;
  final Amount expectedDestination;
  final Amount minDestination;
  final int slippageBps;
  final List<AssetRef> path;
  final int estimatedFeeStroops;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final List<String> warnings;
}

enum IntentState {
  draft,
  verified,
  awaitingSignature,
  submitted,
  reconciling,
  confirmed,
  failed,
  cancelled;

  static IntentState parse(String s) {
    switch (s) {
      case 'DRAFT':
        return draft;
      case 'VERIFIED':
        return verified;
      case 'AWAITING_SIGNATURE':
        return awaitingSignature;
      case 'SUBMITTED':
        return submitted;
      case 'RECONCILING':
        return reconciling;
      case 'CONFIRMED':
        return confirmed;
      case 'FAILED':
        return failed;
      case 'CANCELLED':
        return cancelled;
    }
    // Unknown state from a newer server: refuse to guess.
    throw ContractException('unknown intent state "$s"');
  }

  bool get isTerminal =>
      this == confirmed || this == failed || this == cancelled;
}

class IntentView {
  IntentView({
    required this.id,
    required this.state,
    required this.quoteId,
    required this.txHash,
    required this.unsignedXdr,
    required this.failureReason,
    required this.amountOutActual,
    required this.ledger,
  });

  factory IntentView.fromJson(Map<String, Object?> j) {
    final out = j['amountOutActual'];
    return IntentView(
      id: _need<String>(j, 'id'),
      state: IntentState.parse(_need<String>(j, 'state')),
      quoteId: _need<String>(j, 'quoteId'),
      txHash: j['txHash'] as String?,
      unsignedXdr: j['unsignedXdr'] as String?,
      failureReason: j['failureReason'] as String?,
      amountOutActual: out == null ? null : Amount.parse(out as String),
      ledger: j['ledger'] as int?,
    );
  }

  final String id;
  final IntentState state;
  final String quoteId;
  final String? txHash;
  final String? unsignedXdr;
  final String? failureReason;
  final Amount? amountOutActual;
  final int? ledger;
}

enum RedemptionState {
  awaitingReturn,
  returnSubmitted,
  returnConfirmed,
  fulfilled,
  rejected,
  failed,
  cancelled;

  static RedemptionState parse(String s) {
    switch (s) {
      case 'AWAITING_RETURN':
        return awaitingReturn;
      case 'RETURN_SUBMITTED':
        return returnSubmitted;
      case 'RETURN_CONFIRMED':
        return returnConfirmed;
      case 'FULFILLED':
        return fulfilled;
      case 'REJECTED':
        return rejected;
      case 'FAILED':
        return failed;
      case 'CANCELLED':
        return cancelled;
    }
    throw ContractException('unknown redemption state "$s"');
  }

  bool get isTerminal =>
      this == fulfilled ||
      this == rejected ||
      this == failed ||
      this == cancelled;
}

class RedemptionView {
  RedemptionView({
    required this.id,
    required this.state,
    required this.asset,
    required this.amount,
    required this.returnTxHash,
    required this.unsignedXdr,
    required this.refundDue,
  });

  factory RedemptionView.fromJson(Map<String, Object?> j) => RedemptionView(
    id: _need<String>(j, 'id'),
    state: RedemptionState.parse(_need<String>(j, 'state')),
    asset: AssetRef.fromJson(_need<Map<String, Object?>>(j, 'asset')),
    amount: Amount.parse(_need<String>(j, 'amount')),
    returnTxHash: j['returnTxHash'] as String?,
    unsignedXdr: j['unsignedXdr'] as String?,
    refundDue: _need<bool>(j, 'refundDue'),
  );

  final String id;
  final RedemptionState state;
  final AssetRef asset;
  final Amount amount;
  final String? returnTxHash;
  final String? unsignedXdr;
  final bool refundDue;
}

/// An eligible (verified, active) credit program as listed by `GET /v1/assets`.
class EligibleAsset {
  EligibleAsset({
    required this.asset,
    required this.unitOfAccount,
    required this.expiresAt,
    required this.jurisdiction,
    required this.refundPolicy,
    required this.contact,
  });

  factory EligibleAsset.fromJson(Map<String, Object?> j) {
    final policy = _need<Map<String, Object?>>(j, 'policy');
    if (_need<String>(j, 'status') != 'ACTIVE') {
      throw ContractException('non-active asset in eligible list');
    }
    return EligibleAsset(
      asset: AssetRef(
        _need<String>(j, 'assetCode'),
        _need<String>(j, 'issuer'),
      ),
      unitOfAccount: _need<String>(policy, 'unitOfAccount'),
      expiresAt: DateTime.parse(_need<String>(policy, 'expiresAt')),
      jurisdiction: _need<String>(policy, 'jurisdiction'),
      refundPolicy: _need<String>(policy, 'refundPolicy'),
      contact: _need<String>(policy, 'contact'),
    );
  }

  final AssetRef asset;
  final String unitOfAccount;
  final DateTime expiresAt;
  final String jurisdiction;
  final String refundPolicy;
  final String contact;
}

enum HoldingStatus {
  redeemable,
  supportedAsset,
  unverified,
  suspended,
  expired,
  frozen;

  static HoldingStatus parse(String s) {
    switch (s) {
      case 'REDEEMABLE':
        return redeemable;
      case 'SUPPORTED_ASSET':
        return supportedAsset;
      case 'UNVERIFIED':
        return unverified;
      case 'SUSPENDED':
        return suspended;
      case 'EXPIRED':
        return expired;
      case 'FROZEN':
        return frozen;
    }
    throw ContractException('unknown holding status "$s"');
  }
}

class HoldingView {
  HoldingView({
    required this.wallet,
    required this.asset,
    required this.balance,
    required this.status,
    this.unitOfAccount,
    this.expiresAt,
    this.contact,
  });

  factory HoldingView.fromJson(Map<String, Object?> j) {
    final p = j['program'];
    final prog = p is Map<String, Object?> ? p : null;
    return HoldingView(
      wallet: _need<String>(j, 'wallet'),
      asset: AssetRef.fromJson(_need<Map<String, Object?>>(j, 'asset')),
      balance: Amount.parse(_need<String>(j, 'balance')),
      status: HoldingStatus.parse(_need<String>(j, 'status')),
      unitOfAccount: prog?['unitOfAccount'] as String?,
      expiresAt: prog == null
          ? null
          : DateTime.parse(_need<String>(prog, 'expiresAt')),
      contact: prog?['contact'] as String?,
    );
  }

  final String wallet;
  final AssetRef asset;
  final Amount balance;
  final HoldingStatus status;
  final String? unitOfAccount;
  final DateTime? expiresAt;
  final String? contact;

  /// Only verified, active, unexpired, authorized credit may be exchanged or redeemed.
  bool get usable => status == HoldingStatus.redeemable;
}

class PortfolioView {
  PortfolioView({required this.holdings, required this.notice});

  factory PortfolioView.fromJson(Map<String, Object?> j) => PortfolioView(
    holdings: [
      for (final h in _need<List<Object?>>(j, 'holdings'))
        HoldingView.fromJson(h! as Map<String, Object?>),
    ],
    notice: _need<String>(j, 'notice'),
  );

  final List<HoldingView> holdings;
  final String notice;
}

class WalletChallenge {
  WalletChallenge(this.challengeId, this.message);
  final String challengeId;
  final String message;
}
