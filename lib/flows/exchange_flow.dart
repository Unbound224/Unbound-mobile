import '../domain/approval_guard.dart';
import '../domain/models.dart';
import '../domain/quote_review.dart';
import '../integrations/core_api.dart';
import 'ports.dart';

enum ExchangeOutcomeKind {
  /// Intent reached a terminal state.
  terminal,

  /// Submitted but no verdict yet; keep tracking, never re-submit with new parameters.
  inFlight,

  /// The user must request a new quote and approve again.
  needsNewQuote,

  /// Local refusal (guard/review) - nothing was signed or sent.
  refused,

  /// User cancelled signing.
  cancelled,
}

class ExchangeResult {
  const ExchangeResult(
    this.kind, {
    this.intent,
    this.refusal,
    this.stale = false,
    this.note,
  });
  final ExchangeOutcomeKind kind;
  final IntentView? intent;
  final ApprovalRefused? refusal;

  /// Data shown is the last known one because the network was unreachable.
  final bool stale;
  final String? note;
}

typedef Delay = Future<void> Function(Duration d);

/// Orchestrates quote -> approve -> create intent -> sign -> submit -> track.
/// Rules: same key => same intent; unknown submit outcome => keep tracking, never retry
/// differently; stale quote => new approval; poor network => retain last known state.
class ExchangeFlow {
  ExchangeFlow({
    required this.api,
    required this.signer,
    required this.guard,
    required this.store,
    required this.clock,
    this.delay = _realDelay,
    this.pollSchedule = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    this.maxPolls = 30,
  });

  final CoreApi api;
  final WalletSigner signer;
  final ApprovalGuard guard;
  final PendingStore store;
  final DateTime Function() clock;
  final Delay delay;
  final List<Duration> pollSchedule;
  final int maxPolls;

  bool _busy = false;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  Future<Quote> requestQuote({
    required AssetRef source,
    required AssetRef target,
    required String sourceAmount,
    int slippageBps = 100,
  }) => api.requestQuote(
    source: source,
    target: target,
    sourceAmount: sourceAmount,
    slippageBps: slippageBps,
    destinationAccount: signer.publicKey,
  );

  /// Approve a reviewed quote. Re-entrant taps while a run is active return [ExchangeOutcomeKind.inFlight]
  /// from the stored intent instead of starting another.
  ///
  /// With [trackAfterSubmit] false (used by the UI) it returns as soon as the transaction has been
  /// submitted so the status screen can track the SAME intent; no second submission is ever made.
  Future<ExchangeResult> approve(
    Quote quote, {
    bool trackAfterSubmit = true,
  }) async {
    if (_busy) {
      return const ExchangeResult(
        ExchangeOutcomeKind.inFlight,
        note: 'already in progress',
      );
    }
    _busy = true;
    try {
      final review = QuoteReview.evaluate(quote, clock());
      if (review.needsNewQuote) {
        return const ExchangeResult(ExchangeOutcomeKind.needsNewQuote);
      }
      if (!review.canProceed) {
        return ExchangeResult(
          ExchangeOutcomeKind.refused,
          note: review.issues.map((i) => i.name).join(','),
        );
      }

      // 1. Create (or re-fetch) the intent under a PERSISTED key. A crash here is safe to retry.
      final createKey = await keyFor(store, 'create:${quote.quoteId}');
      IntentView intent;
      try {
        intent = await api.createIntent(
          quoteId: quote.quoteId,
          idempotencyKey: createKey,
        );
      } on ApiException catch (e) {
        if (e.code == 'QUOTE_EXPIRED') {
          return const ExchangeResult(ExchangeOutcomeKind.needsNewQuote);
        }
        rethrow;
      }
      await store.write('intent:${quote.quoteId}', intent.id);

      // 2. Local verification, then the user signs on-device.
      if (intent.state == IntentState.awaitingSignature) {
        final ApprovedTransaction approved;
        try {
          approved = guard.check(
            quote: quote,
            intent: intent,
            ownAccounts: {signer.publicKey},
            signingAccount: signer.publicKey,
            now: clock(),
          );
        } on ApprovalRefused catch (r) {
          return ExchangeResult(
            ExchangeOutcomeKind.refused,
            intent: intent,
            refusal: r,
          );
        }
        final String signed;
        try {
          signed = await signer.sign(
            approved.unsignedXdr,
            approved.networkPassphrase,
          );
        } on SigningCancelled {
          return ExchangeResult(ExchangeOutcomeKind.cancelled, intent: intent);
        }

        // 3. Submit under a persisted key; an unknown outcome is tracked, never re-signed.
        final submitKey = await keyFor(store, 'submit:${intent.id}');
        try {
          intent = await api.submitIntent(
            id: intent.id,
            signedXdr: signed,
            idempotencyKey: submitKey,
          );
        } on ApiException catch (e) {
          if (!e.outcomeUnknown) {
            if (e.code == 'QUOTE_EXPIRED') {
              return const ExchangeResult(ExchangeOutcomeKind.needsNewQuote);
            }
            rethrow;
          }
          // Unknown: fall through to tracking with the last known intent.
        }
      }
      if (!trackAfterSubmit) {
        return ExchangeResult(
          intent.state.isTerminal
              ? ExchangeOutcomeKind.terminal
              : ExchangeOutcomeKind.inFlight,
          intent: intent,
        );
      }
      return await track(intent.id, last: intent);
    } finally {
      _busy = false;
    }
  }

  /// Resume after an app restart using the persisted intent id for a quote.
  Future<ExchangeResult?> resume(String quoteId) async {
    final id = await store.read('intent:$quoteId');
    if (id == null) {
      return null;
    }
    return track(id);
  }

  /// One quick read for immediate display. Network trouble yields `intent: null, stale: true`
  /// (or the [last] known intent), never an invented state.
  Future<ExchangeResult> snapshot(String intentId, {IntentView? last}) async {
    try {
      final v = await api.getIntent(intentId);
      return ExchangeResult(
        v.state.isTerminal
            ? ExchangeOutcomeKind.terminal
            : ExchangeOutcomeKind.inFlight,
        intent: v,
      );
    } on ApiException catch (e) {
      if (!e.outcomeUnknown) {
        rethrow;
      }
      return ExchangeResult(
        ExchangeOutcomeKind.inFlight,
        intent: last,
        stale: true,
      );
    }
  }

  /// Poll with backoff until terminal or [maxPolls]. Network loss keeps the last known state (stale).
  Future<ExchangeResult> track(String intentId, {IntentView? last}) async {
    var current = last;
    var stale = false;
    for (var i = 0; i < maxPolls; i++) {
      try {
        current = await api.getIntent(intentId);
        stale = false;
      } on ApiException catch (e) {
        if (!e.outcomeUnknown) {
          rethrow;
        }
        stale = true;
      }
      if (current != null && current.state.isTerminal) {
        return ExchangeResult(ExchangeOutcomeKind.terminal, intent: current);
      }
      if (current != null &&
          current.state == IntentState.awaitingSignature &&
          last == null &&
          i == 0) {
        // Resumed into a pending signature: caller decides (quote may be stale).
        return ExchangeResult(
          ExchangeOutcomeKind.inFlight,
          intent: current,
          note: 'awaiting signature',
        );
      }
      await delay(
        pollSchedule[i < pollSchedule.length ? i : pollSchedule.length - 1],
      );
    }
    return ExchangeResult(
      ExchangeOutcomeKind.inFlight,
      intent: current,
      stale: stale,
      note: 'still waiting for the ledger',
    );
  }
}
