import 'dart:convert';

import 'package:crypto/crypto.dart';

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
    final e = r.escrow;
    if (e != null) {
      // Escrow mode (ADR 0002): one open_return call on the escrow contract that core named,
      // moving exactly this amount from this wallet, for this credit's issuer and this redemption.
      final c = s.contractCall;
      if (s.operationCount != 1 || c == null) {
        return [...p, 'not a single escrow call'];
      }
      if (c.contractId != e.contractId) p.add('wrong contract');
      if (c.function != 'open_return' || c.args.length != 6) {
        return [...p, 'not open_return'];
      }
      if (c.args[0] != signer.publicKey ||
          s.sourceAccount != signer.publicKey) {
        p.add('wrong source');
      }
      if (c.args[1] != r.asset.issuer) p.add('escrow is not for this issuer');
      if (c.args[3] != amount.units) p.add('wrong amount');
      if (c.args[4] != redemptionKeyHex(r.id)) p.add('wrong redemption');
      if (c.args[5] != BigInt.from(e.deadline.millisecondsSinceEpoch ~/ 1000)) {
        p.add('deadline differs from what core reported');
      }
      return p;
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

  /// Escrow mode, after the deadline: take the credit back. Core builds `expire_refund` with this
  /// wallet as source; it is decoded and checked locally before signing.
  Future<RedemptionResult> claimRefund(RedemptionView current) async {
    final e = current.escrow;
    if (e == null) {
      return RedemptionResult(
        RedemptionOutcomeKind.refused,
        redemption: current,
        problems: const ['not an escrowed redemption'],
      );
    }
    var r = await api.claimRefund(current.id);
    final xdr = r.escrow?.pendingXdr;
    if (r.escrow?.pendingAction != EscrowAction.expire || xdr == null) {
      return r.state.isTerminal
          ? RedemptionResult(RedemptionOutcomeKind.terminal, redemption: r)
          : RedemptionResult(
              RedemptionOutcomeKind.refused,
              redemption: r,
              problems: const ['missing payload'],
            );
    }
    final problems = <String>[];
    try {
      final s = inspector.inspect(xdr);
      final c = s.contractCall;
      if (s.networkPassphrase != testnetPassphrase) {
        problems.add('wrong network');
      }
      if (c == null || c.contractId != e.contractId) {
        problems.add('wrong contract');
      }
      if (c?.function != 'expire_refund' || c?.args.length != 1) {
        problems.add('not expire_refund');
      } else if (c!.args[0] != redemptionKeyHex(r.id)) {
        problems.add('wrong redemption');
      }
      if (s.sourceAccount != signer.publicKey) problems.add('wrong source');
    } on Object {
      problems.add('could not decode transaction');
    }
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
      r = await api.submitEscrowAction(id: r.id, signedXdr: signed);
    } on ApiException catch (e) {
      if (!e.outcomeUnknown) rethrow;
    }
    return track(r.id, last: r);
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

/// The escrow keys a return by sha256(core redemption id); see unbound-stellar `redemptionKey`.
String redemptionKeyHex(String redemptionId) =>
    sha256.convert(utf8.encode(redemptionId)).toString();
