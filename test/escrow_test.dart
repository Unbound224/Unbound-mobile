import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/domain/status_text.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/flows/redemption_flow.dart';
import 'package:unbound_mobile/integrations/core_api.dart';
import 'package:unbound_mobile/integrations/xdr_inspector.dart';

import 'support/fakes.dart';

/// Escrowed redemptions (unbound-stellar ADR 0002). The XDR comes from unbound-stellar's REAL
/// SorobanRedemptionEscrow builders over its fixture RPC (test/fixtures/transactions.v1.json).
final fx = jsonDecode(
  File('test/fixtures/transactions.v1.json').readAsStringSync(),
) as Map<String, Object?>;
final open = fx['escrowOpen']! as Map<String, Object?>;
final expire = fx['escrowExpire']! as Map<String, Object?>;
final accounts = fx['accounts']! as Map<String, Object?>;
final user = accounts['user']! as String;
final issuer = accounts['issuer']! as String;
final contract = open['contractId']! as String;
final deadline = DateTime.fromMillisecondsSinceEpoch(
  (open['deadline']! as int) * 1000,
  isUtc: true,
);

Map<String, Object?> escrowJson({
  String state = 'HELD',
  bool refundAvailable = false,
  String? pendingAction,
  String? pendingXdr,
}) => {
  'contractId': contract,
  'deadline': deadline.toIso8601String(),
  'state': state,
  'refundAvailable': refundAvailable,
  'pendingAction': pendingAction,
  'pendingXdr': pendingXdr,
  'pendingTxHash': null,
  'closeTxHash': null,
  'lastFailure': null,
};

RedemptionView view(
  String state, {
  String? xdr,
  Map<String, Object?>? escrow,
  String id = 'red_fixture0001',
}) => RedemptionView.fromJson({
  'id': id,
  'state': state,
  'asset': {'code': 'SHOP', 'issuer': issuer},
  'amount': '30.0000000',
  'holder': user,
  'returnTxHash': open['hash'],
  'unsignedXdr': xdr,
  'refundDue': false,
  'rejectionReason': null,
  'mode': 'ESCROW',
  'escrow': escrow ?? escrowJson(state: 'AWAITING_OPEN'),
  'createdAt': 'x',
  'updatedAt': 'x',
});

({FakeCoreApi api, FakeSigner signer, RedemptionFlow flow}) rig() {
  final api = FakeCoreApi();
  final signer = FakeSigner(publicKey: user);
  return (
    api: api,
    signer: signer,
    flow: RedemptionFlow(
      api: api,
      signer: signer,
      inspector: const StellarXdrInspector(),
      store: InMemoryPendingStore(),
      delay: (_) async {},
      maxPolls: 2,
    ),
  );
}

void main() {
  group('decoding the real escrow invocations', () {
    const inspector = StellarXdrInspector();
    test('open_return: contract, function and every argument', () {
      final s = inspector.inspect(open['xdr']! as String);
      expect(s.hash, open['hash']);
      expect(s.operationType, 'invokeContract');
      expect(s.sourceAccount, user);
      final c = s.contractCall!;
      expect(c.contractId, contract);
      expect(c.function, 'open_return');
      expect(c.args[0], user);
      expect(c.args[1], issuer);
      expect(c.args[2], startsWith('C'));
      expect(c.args[3], Amount.parse('30').units);
      expect(c.args[4], open['redemptionKeyHex']);
      expect(c.args[5], BigInt.from(open['deadline']! as int));
      expect(redemptionKeyHex('red_fixture0001'), open['redemptionKeyHex']);
    });
    test('expire_refund carries only the redemption key', () {
      final c = inspector.inspect(expire['xdr']! as String).contractCall!;
      expect(c.function, 'expire_refund');
      expect(c.args, [expire['redemptionKeyHex']]);
    });
  });

  group('models', () {
    test('escrow details parse; older cores without mode are native', () {
      final v = view('RETURN_CONFIRMED', escrow: escrowJson());
      expect(v.isEscrow, isTrue);
      expect(v.escrow!.state, EscrowState.held);
      expect(v.escrow!.deadline, deadline);
      final legacy = RedemptionView.fromJson({
        'id': 'r',
        'state': 'EXPIRED',
        'asset': {'code': 'SHOP', 'issuer': issuer},
        'amount': '1',
        'refundDue': false,
      });
      expect(legacy.isEscrow, isFalse);
      expect(legacy.state.isTerminal, isTrue);
    });
    test('fails closed on inconsistent or unknown escrow data', () {
      final base = {
        'id': 'r',
        'state': 'RETURN_CONFIRMED',
        'asset': {'code': 'SHOP', 'issuer': issuer},
        'amount': '1',
        'refundDue': false,
      };
      expect(
        () => RedemptionView.fromJson({...base, 'mode': 'ESCROW'}),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => RedemptionView.fromJson({
          ...base,
          'mode': 'ESCROW',
          'escrow': {...escrowJson(), 'state': 'MOON'},
        }),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => RedemptionView.fromJson({
          ...base,
          'mode': 'ESCROW',
          'escrow': {...escrowJson(), 'contractId': 'GNOTACONTRACT'},
        }),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => RedemptionView.fromJson({...base, 'mode': 'SIDEWAYS'}),
        throwsA(isA<ContractException>()),
      );
    });
  });

  group('redeem in escrow mode', () {
    test(
      'the real open_return XDR is verified locally, signed and tracked',
      () async {
        final r = rig();
        r.api.createRedemptionResult = view(
          'AWAITING_RETURN',
          xdr: open['xdr']! as String,
        );
        r.api.returnResult = view('RETURN_SUBMITTED');
        r.api.redemptionScript = [
          view('RETURN_CONFIRMED', escrow: escrowJson()),
        ];
        final res = await r.flow.redeem(
          asset: AssetRef('SHOP', issuer),
          amount: Amount.parse('30'),
        );
        expect(r.signer.signCalls, 1);
        expect(res.kind, RedemptionOutcomeKind.inFlight);
        expect(res.redemption!.escrow!.state, EscrowState.held);
      },
    );

    for (final (name, mutate, problem) in [
      (
        'another redemption id',
        (Map<String, Object?> j) => j['id'] = 'red_other00001',
        'wrong redemption',
      ),
      (
        'a different contract',
        (Map<String, Object?> j) => j['escrow'] = {
          ...escrowJson(state: 'AWAITING_OPEN'),
          'contractId':
              'CA6LKTSR5SVSQ2RV5LRXEZIIGV7MLJSJ5LVP3ROH27HDKPE4VXUEGANI',
        },
        'wrong contract',
      ),
      (
        'a different deadline',
        (Map<String, Object?> j) => j['escrow'] = {
          ...escrowJson(state: 'AWAITING_OPEN'),
          'deadline': deadline.add(const Duration(days: 1)).toIso8601String(),
        },
        'deadline differs from what core reported',
      ),
    ]) {
      test('refuses to sign when core reports $name', () async {
        final r = rig();
        final j = {
          'id': 'red_fixture0001',
          'state': 'AWAITING_RETURN',
          'asset': {'code': 'SHOP', 'issuer': issuer},
          'amount': '30.0000000',
          'unsignedXdr': open['xdr'],
          'refundDue': false,
          'mode': 'ESCROW',
          'escrow': escrowJson(state: 'AWAITING_OPEN'),
        };
        mutate(j);
        r.api.createRedemptionResult = RedemptionView.fromJson(j);
        final res = await r.flow.redeem(
          asset: AssetRef('SHOP', issuer),
          amount: Amount.parse('30'),
        );
        expect(res.kind, RedemptionOutcomeKind.refused);
        expect(res.problems, contains(problem));
        expect(r.signer.signCalls, 0);
      });
    }

    test('refuses a different amount and a different signer', () async {
      final r = rig();
      r.api.createRedemptionResult = view(
        'AWAITING_RETURN',
        xdr: open['xdr']! as String,
      );
      final res = await r.flow.redeem(
        asset: AssetRef('SHOP', issuer),
        amount: Amount.parse('31'),
      );
      expect(res.problems, contains('wrong amount'));
      expect(r.signer.signCalls, 0);
    });
  });

  group('timeout refund', () {
    test('verifies the real expire_refund XDR, signs and submits it', () async {
      final r = rig();
      r.api.claimRefundResult = view(
        'RETURN_CONFIRMED',
        escrow: escrowJson(
          pendingAction: 'EXPIRE',
          pendingXdr: expire['xdr']! as String,
        ),
      );
      r.api.escrowSubmitResult = view(
        'EXPIRED',
        escrow: escrowJson(state: 'EXPIRED_REFUNDED'),
      );
      r.api.redemptionScript = [
        view('EXPIRED', escrow: escrowJson(state: 'EXPIRED_REFUNDED')),
      ];
      final held = view('RETURN_CONFIRMED', escrow: escrowJson());
      final res = await r.flow.claimRefund(held);
      expect(res.kind, RedemptionOutcomeKind.terminal);
      expect(res.redemption!.state, RedemptionState.expired);
      expect(r.api.escrowSubmissions.single, 'SIGNED:${expire['xdr']}');
    });

    test('refuses to sign an open_return presented as the refund', () async {
      final r = rig();
      r.api.claimRefundResult = view(
        'RETURN_CONFIRMED',
        escrow: escrowJson(
          pendingAction: 'EXPIRE',
          pendingXdr: open['xdr']! as String,
        ),
      );
      final res = await r.flow.claimRefund(
        view('RETURN_CONFIRMED', escrow: escrowJson()),
      );
      expect(res.kind, RedemptionOutcomeKind.refused);
      expect(res.problems, contains('not expire_refund'));
      expect(r.signer.signCalls, 0);
    });

    test('native redemptions have no escrow refund', () async {
      final r = rig();
      final res = await r.flow.claimRefund(
        redemptionView(RedemptionState.rejected),
      );
      expect(res.kind, RedemptionOutcomeKind.refused);
    });

    test('server refusal surfaces as an ApiException', () async {
      final r = rig();
      r.api.claimRefundResult = ApiException('INVALID_STATE', 'x', status: 409);
      expect(
        () =>
            r.flow.claimRefund(view('RETURN_CONFIRMED', escrow: escrowJson())),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('status text', () {
    final before = deadline.subtract(const Duration(days: 1));
    test('held, refund available, refunded, rejected-with-escrow', () {
      expect(
        redemptionStatus(
          view('RETURN_CONFIRMED', escrow: escrowJson()),
          now: before,
        ).headline,
        'Held in escrow',
      );
      expect(
        redemptionStatus(
          view('RETURN_CONFIRMED', escrow: escrowJson()),
          now: deadline,
        ).headline,
        'Refund available',
      );
      expect(
        redemptionStatus(
          view(
            'RETURN_CONFIRMED',
            escrow: escrowJson(pendingAction: 'EXPIRE', pendingXdr: 'x'),
          ),
        ).warnDoNotRetry,
        isTrue,
      );
      expect(
        redemptionStatus(
          view('EXPIRED', escrow: escrowJson(state: 'EXPIRED_REFUNDED')),
        ).headline,
        'Refunded',
      );
      expect(
        redemptionStatus(
          view('REJECTED', escrow: escrowJson(state: 'REFUNDED')),
        ).detail,
        contains('refunded your credit'),
      );
    });
  });
}
