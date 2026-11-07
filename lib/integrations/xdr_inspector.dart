import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as s;

import '../domain/amount.dart';
import '../domain/approval_guard.dart';
import '../domain/models.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

AssetRef _asset(s.Asset a) {
  if (a is s.AssetTypeNative) {
    return const AssetRef('XLM', null);
  }
  if (a is s.AssetTypeCreditAlphaNum) {
    return AssetRef(a.code, a.issuerId);
  }
  throw const FormatException('unsupported asset type');
}

String _contract(String id) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(id)
    ? s.StrKey.encodeContractIdHex(id)
    : id;

Object? _arg(s.XdrSCVal v) {
  switch (v.discriminant) {
    case s.XdrSCValType.SCV_ADDRESS:
      final a = s.Address.fromXdrSCVal(v);
      return a.accountId ??
          (a.contractId == null ? null : _contract(a.contractId!));
    case s.XdrSCValType.SCV_I128:
      return v.toBigInt();
    case s.XdrSCValType.SCV_U64:
      return v.u64?.uint64;
    case s.XdrSCValType.SCV_BYTES:
      return _hex(v.bytes?.sCBytes ?? const <int>[]);
    default:
      return null; // unknown argument kinds are reported as null and fail any comparison
  }
}

/// Decodes an unsigned transaction envelope LOCALLY (no network) so [ApprovalGuard] can compare what
/// the user would sign with the quote. Supports exactly the two shapes Unbound produces: a
/// single-operation `pathPaymentStrictSend` (exchange), `payment` (native redemption return) or a
/// Soroban contract invocation (the redemption escrow, decoded into [ContractCall]). Anything
/// else - fee bumps, extra operations, per-operation source accounts - is refused by throwing.
/// The transaction hash is computed for Testnet; a mismatch with the advertised hash is caught by the guard.
class StellarXdrInspector implements TransactionInspector {
  const StellarXdrInspector();

  @override
  TxSummary inspect(String unsignedXdr) {
    final s.AbstractTransaction t = s.AbstractTransaction.fromEnvelopeXdrString(
      unsignedXdr,
    );
    if (t is! s.Transaction) {
      throw const FormatException('fee-bump envelopes are not accepted');
    }
    if (t.operations.length != 1) {
      throw FormatException(
        'expected exactly one operation, got ${t.operations.length}',
      );
    }
    final op = t.operations.single;
    if (op.sourceAccount != null) {
      throw const FormatException(
        'operation-level source accounts are not accepted',
      );
    }
    final hash = _hex(t.hash(s.Network.TESTNET));
    final source = t.sourceAccount.accountId;
    if (op is s.PathPaymentStrictSendOperation) {
      return TxSummary(
        networkPassphrase: testnetPassphrase,
        sourceAccount: source,
        operationType: 'pathPaymentStrictSend',
        sendAsset: _asset(op.sendAsset),
        sendAmount: Amount.parse(op.sendAmount),
        destAsset: _asset(op.destAsset),
        destMin: Amount.parse(op.destMin),
        destination: op.destination.accountId,
        path: [for (final a in op.path) _asset(a)],
        hash: hash,
        operationCount: 1,
      );
    }
    if (op is s.PaymentOperation) {
      final a = _asset(op.asset);
      return TxSummary(
        networkPassphrase: testnetPassphrase,
        sourceAccount: source,
        operationType: 'payment',
        sendAsset: a,
        sendAmount: Amount.parse(op.amount),
        destAsset: a,
        destMin: Amount.parse(op.amount),
        destination: op.destination.accountId,
        path: const [],
        hash: hash,
        operationCount: 1,
      );
    }
    if (op is s.InvokeHostFunctionOperation) {
      final f = op.function;
      if (f is! s.InvokeContractHostFunction) {
        throw const FormatException('only contract invocations are accepted');
      }
      return TxSummary(
        networkPassphrase: testnetPassphrase,
        sourceAccount: source,
        operationType: 'invokeContract',
        sendAsset: const AssetRef('XLM', null),
        sendAmount: Amount.zero,
        destAsset: const AssetRef('XLM', null),
        destMin: Amount.zero,
        destination: _contract(f.contractID),
        path: const [],
        hash: hash,
        operationCount: 1,
        contractCall: ContractCall(_contract(f.contractID), f.functionName, [
          for (final a in f.arguments ?? const <s.XdrSCVal>[]) _arg(a),
        ]),
      );
    }
    throw FormatException('unsupported operation ${op.runtimeType}');
  }
}
