import '../domain/amount.dart';
import '../domain/approval_guard.dart';
import '../domain/models.dart';
import '../integrations/core_api.dart';
import 'exchange_flow.dart' show Delay;
import 'ports.dart';

enum RedemptionOutcomeKind { terminal, inFlight, refused, cancelled }

class RedemptionResult {
  const RedemptionResult(
    this.kind, {
    this.redemption,
    this.problems = const [],
    this.stale = false,
  });
  final RedemptionOutcomeKind kind;
  final RedemptionView? redemption;
  final List<String> problems;
  final bool stale;
}

/// Redeem supported credit: the holder returns it to the issuer on the ledger, then the merchant
/// confirms fulfilment off-chain. `RETURN_CONFIRMED` is NOT "redeemed"; only `FULFILLED` is.
class RedemptionFlow {
  RedemptionFlow({
    required this.api,
    required this.signer,
    required this.inspector,
    required this.store,
    this.delay = _realDelay,
    this.pollSchedule = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
    this.maxPolls = 30,
  });

  final CoreApi api;
  final WalletSigner signer;
  final TransactionInspector inspector;
  final PendingStore store;
  final Delay delay;
  final List<Duration> pollSchedule;
  final int maxPolls;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  /// [asset] must come from the verified issuer directory (see CreditInventory.canRedeem).
  Future<RedemptionResult> redeem({
    required AssetRef asset,
    required Amount amount,
  }) async {
    final key = await keyFor(store, 'redeem:${asset.key}:$amount');
    var r = await api.createRedemption(
      asset: asset,
      amount: amount.toString(),
      holder: signer.publicKey,
      idempotencyKey: key,
    );
    await store.write('redemption:${asset.key}:$amount', r.id);

    if (r.state == RedemptionState.awaitingReturn) {
      final xdr = r.unsignedXdr;
      if (xdr == null) {
        return RedemptionResult(
          RedemptionOutcomeKind.refused,
          redemption: r,
          problems: const ['missing payload'],
        );
      }
      final problems = _verify(r, xdr, amount);
      if (problems.isNotEmpty) {
        return RedemptionResult(
          RedemptionOutcomeKind.refused,
          redemption: r,
          problems: problems,
        );
      }
      final String signed;
      try {
        signed = await signer.sign(xdr, testnetPassphrase);
      } on SigningCancelled {
        return RedemptionResult(RedemptionOutcomeKind.cancelled, redemption: r);
      }
      try {
        r = await api.submitRedemptionReturn(id: r.id, signedXdr: signed);
      } on ApiException catch (e) {
        if (!e.outcomeUnknown) {
          rethrow;
        }
      }
    }
    return track(r.id, last: r);
  }

  List<String> _verify(RedemptionView r, String xdr, Amount amount) {
    final TxSummary s;
    try {
      s = inspector.inspect(xdr);
    } on Object {
      return const ['could not decode transaction'];
    }
    final p = <String>[];
    if (s.networkPassphrase != testnetPassphrase) {
      p.add('wrong network');
    }
    if (s.operationCount != 1 || s.operationType != 'payment') {
      p.add('not a single payment');
    }
    if (s.sendAsset != r.asset) {
      p.add('wrong asset');
    }
    if (s.sendAmount != amount) {
      p.add('wrong amount');
    }
    // The return must go back to the issuer of the credit and nowhere else.
    if (s.destination != r.asset.issuer) {
      p.add('destination is not the issuer');
    }
    if (s.sourceAccount != signer.publicKey) {
      p.add('wrong source');
    }
    return p;
  }

  Future<RedemptionResult> track(String id, {RedemptionView? last}) async {
    var cur = last;
    var stale = false;
    for (var i = 0; i < maxPolls; i++) {
      try {
        cur = await api.getRedemption(id);
        stale = false;
      } on ApiException catch (e) {
        if (!e.outcomeUnknown) {
          rethrow;
        }
        stale = true;
      }
      if (cur != null && cur.state.isTerminal) {
        return RedemptionResult(
          RedemptionOutcomeKind.terminal,
          redemption: cur,
        );
      }
      await delay(
        pollSchedule[i < pollSchedule.length ? i : pollSchedule.length - 1],
      );
    }
    return RedemptionResult(
      RedemptionOutcomeKind.inFlight,
      redemption: cur,
      stale: stale,
    );
  }
}
