import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/approval_guard.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/flows/exchange_flow.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/integrations/core_api.dart';

import 'models_test.dart' show quoteJson;
import 'support/fakes.dart';

final t0 = DateTime.utc(2026, 11, 2, 12);

class Rig {
  Rig({PendingStore? store, this.now})
    : store = store ?? InMemoryPendingStore() {
    flow = _build();
  }
  final FakeCoreApi api = FakeCoreApi();
  final FakeSigner signer = FakeSigner();
  final FakeInspector inspector = FakeInspector();
  final PendingStore store;
  DateTime? now;
  final List<Duration> delays = [];
  late ExchangeFlow flow;

  ExchangeFlow _build() => ExchangeFlow(
    api: api,
    signer: signer,
    guard: ApprovalGuard(inspector),
    store: store,
    clock: () => now ?? t0,
    delay: (d) async => delays.add(d),
    maxPolls: 6,
  );

  Quote get quote => Quote.fromJson(quoteJson());
}

void main() {
  trackFlagTests();
  snapshotTests();
  test('happy path: one create, one sign, one submit, then ledger-confirmed result', () async {
    final r = Rig();
    final res = await r.flow.approve(r.quote);
    expect(res.kind, ExchangeOutcomeKind.terminal);
    expect(res.intent!.state, IntentState.confirmed);
    expect(res.intent!.amountOutActual, Amount.parse('72'));
    expect(
      [r.api.createKeys.length, r.signer.signCalls, r.api.submitCalls],
      [1, 1, 1],
    );
    expect(r.api.submitKeys.single, isNot(r.api.createKeys.single));
  });

  test('an expired quote asks for a new quote and touches nothing', () async {
    final r = Rig(now: t0.add(const Duration(minutes: 2)));
    final res = await r.flow.approve(r.quote);
    expect(res.kind, ExchangeOutcomeKind.needsNewQuote);
    expect([r.api.createKeys.length, r.signer.signCalls], [0, 0]);
  });

  test('server-side QUOTE_EXPIRED also asks for a new quote', () async {
    final r = Rig();
    r.api.createError = ApiException('QUOTE_EXPIRED', 'expired', status: 410);
    expect(
      (await r.flow.approve(r.quote)).kind,
      ExchangeOutcomeKind.needsNewQuote,
    );
    expect(r.signer.signCalls, 0);
  });

  test(
    'guard refusal (foreign destination) means nothing is signed or submitted',
    () async {
      final r = Rig();
      r.inspector.destination = 'GATTACKER';
      final res = await r.flow.approve(r.quote);
      expect(res.kind, ExchangeOutcomeKind.refused);
      expect(res.refusal!.reasons, contains(RefusalReason.foreignDestination));
      expect([r.signer.signCalls, r.api.submitCalls], [0, 0]);
    },
  );

  test('user cancelling the signer submits nothing', () async {
    final r = Rig();
    r.signer.cancel = true;
    expect((await r.flow.approve(r.quote)).kind, ExchangeOutcomeKind.cancelled);
    expect(r.api.submitCalls, 0);
  });

  test('submit timeout: keeps tracking the SAME intent, no re-sign, no second submit', () async {
    final r = Rig();
    r.api.submitResult = ApiException('NETWORK', 'timeout');
    r.api.getScript = [
      intentView(IntentState.submitted),
      intentView(IntentState.reconciling),
      intentView(IntentState.confirmed, out: Amount.parse('72')),
    ];
    final res = await r.flow.approve(r.quote);
    expect(res.kind, ExchangeOutcomeKind.terminal);
    expect(r.api.submitCalls, 1);
    expect(r.signer.signCalls, 1);
    expect(r.delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  test(
    'a definitive server rejection on submit is surfaced, not swallowed',
    () async {
      final r = Rig();
      r.api.submitResult = ApiException(
        'ASSET_NOT_ELIGIBLE',
        'issuer revoked',
        status: 422,
      );
      await expectLater(
        r.flow.approve(r.quote),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'ASSET_NOT_ELIGIBLE',
          ),
        ),
      );
    },
  );

  test(
    'network loss while polling keeps the last known state flagged stale',
    () async {
      final r = Rig();
      r.api.getScript = [
        intentView(IntentState.submitted),
        ApiException('NETWORK', 'offline'),
      ];
      final res = await r.flow.approve(r.quote);
      expect(res.kind, ExchangeOutcomeKind.inFlight);
      expect(res.stale, isTrue);
      expect(res.intent!.state, IntentState.submitted);
      expect(r.api.getCalls, 6);
    },
  );

  test('a ledger FAILED verdict is terminal and carries the reason', () async {
    final r = Rig();
    r.api.getScript = [
      intentView(IntentState.failed, reason: 'MIN_OUTPUT_VIOLATION'),
    ];
    final res = await r.flow.approve(r.quote);
    expect(res.kind, ExchangeOutcomeKind.terminal);
    expect(res.intent!.failureReason, 'MIN_OUTPUT_VIOLATION');
  });

  test('double tap: the second approve does not start a second run', () async {
    final r = Rig();
    final results = await Future.wait([
      r.flow.approve(r.quote),
      r.flow.approve(r.quote),
    ]);
    expect(
      results.map((x) => x.kind),
      containsAll([ExchangeOutcomeKind.terminal, ExchangeOutcomeKind.inFlight]),
    );
    expect(r.api.createKeys.length, 1);
    expect(r.api.submitCalls, 1);
  });

  test('crash after the server created the intent: restart reuses the persisted key => same intent', () async {
    final store = InMemoryPendingStore();
    final r1 = Rig(store: store);
    r1.api.failFirstCreateAfterServerCreated = true;
    await expectLater(r1.flow.approve(r1.quote), throwsA(isA<ApiException>()));
    // "restart": new flow + same durable store + same server
    final r2 = Rig(store: store);
    r2.api.createdByKey.addAll(r1.api.createdByKey);
    final res = await r2.flow.approve(r2.quote);
    expect(res.kind, ExchangeOutcomeKind.terminal);
    expect(r2.api.createKeys.single, r1.api.createKeys.single);
    expect(r2.api.createdByKey.length, 1);
  });

  test(
    'resume tracks a persisted intent after restart and returns null when none',
    () async {
      final r = Rig();
      expect(await r.flow.resume('q_1'), isNull);
      await r.store.write('intent:q_1', 'int_1');
      r.api.getScript = [
        intentView(IntentState.reconciling),
        intentView(IntentState.confirmed),
      ];
      final res = await r.flow.resume('q_1');
      expect(res!.kind, ExchangeOutcomeKind.terminal);
    },
  );
}

void trackFlagTests() {
  test(
    'trackAfterSubmit:false returns right after submit without polling',
    () async {
      final r = Rig();
      final res = await r.flow.approve(r.quote, trackAfterSubmit: false);
      expect(res.kind, ExchangeOutcomeKind.inFlight);
      expect(res.intent!.state, IntentState.submitted);
      expect(r.api.getCalls, 0);
      expect(r.api.submitCalls, 1);
    },
  );
}

void snapshotTests() {
  test(
    'snapshot reads once; offline keeps the last known intent flagged stale',
    () async {
      final r = Rig();
      r.api.getScript = [intentView(IntentState.reconciling)];
      final a = await r.flow.snapshot('int_1');
      expect(
        [a.kind, a.intent!.state, a.stale],
        [ExchangeOutcomeKind.inFlight, IntentState.reconciling, false],
      );
      r.api.getScript = [ApiException('NETWORK', 'offline')];
      r.api.getCalls = 0;
      final b = await r.flow.snapshot('int_1', last: a.intent);
      expect([b.intent!.state, b.stale], [IntentState.reconciling, true]);
      r.api.getScript = [ApiException('NOT_FOUND', 'x', status: 404)];
      r.api.getCalls = 0;
      await expectLater(r.flow.snapshot('nope'), throwsA(isA<ApiException>()));
    },
  );
}
