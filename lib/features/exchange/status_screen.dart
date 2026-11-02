import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/status_text.dart';
import '../../flows/exchange_flow.dart';

/// Step 3: honest status. Re-tracks the SAME intent; never offers a retry while the outcome is unknown.
class StatusScreen extends ConsumerStatefulWidget {
  const StatusScreen({super.key, required this.intentId});
  final String intentId;
  @override
  ConsumerState<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends ConsumerState<StatusScreen> {
  ExchangeResult? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(exchangeFlowProvider).track(widget.intentId);
      if (mounted) {
        setState(() => _result = r);
      }
    } catch (_) {
      // keep the last known state; the stale banner below explains
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = _result?.intent;
    final text = intent == null ? null : exchangeStatus(intent);
    final inFlight =
        _result != null && _result!.kind != ExchangeOutcomeKind.terminal;
    return Scaffold(
      appBar: AppBar(title: const Text('Exchange status')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (text == null && _loading)
              const Center(child: CircularProgressIndicator()),
            if (text == null && !_loading)
              const Text(
                'Status unavailable. Your exchange is not lost; try again.',
                key: Key('status-unavailable'),
              ),
            if (text != null) ...[
              Text(
                text.headline,
                key: const Key('status-headline'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(text.detail, key: const Key('status-detail')),
              if (text.warnDoNotRetry)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Do not start this exchange again while it is in progress.',
                    key: Key('do-not-retry'),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
            if (_result?.stale ?? false)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Showing the last known state; you appear to be offline.',
                  key: Key('stale'),
                ),
              ),
            if (intent?.txHash != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText('Transaction: ${intent!.txHash}'),
              ),
            const SizedBox(height: 16),
            if (inFlight || text == null)
              OutlinedButton(
                onPressed: _loading ? null : _refresh,
                child: Text(_loading ? 'Checking...' : 'Check again'),
              ),
            if (text?.showRetry ?? false)
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Start over with a new quote'),
              ),
            if (_result?.kind == ExchangeOutcomeKind.terminal &&
                !(text?.showRetry ?? false))
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to my credits'),
              ),
          ],
        ),
      ),
    );
  }
}
