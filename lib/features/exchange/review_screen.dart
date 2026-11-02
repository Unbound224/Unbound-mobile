import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/quote_review.dart';
import '../../flows/exchange_flow.dart';
import '../../integrations/core_api.dart';

/// Step 2: exact disclosure + approve. The primary action is disabled once the quote expires or looks wrong.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.quote});
  final Quote quote;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  Timer? _tick;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _approve() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await ref.read(exchangeFlowProvider).approve(widget.quote);
      if (!mounted) {
        return;
      }
      switch (r.kind) {
        case ExchangeOutcomeKind.terminal:
        case ExchangeOutcomeKind.inFlight:
          final id = r.intent?.id;
          if (id != null) {
            context.go('/status/$id');
          } else {
            setState(() => _message = 'An exchange is already in progress.');
          }
        case ExchangeOutcomeKind.needsNewQuote:
          setState(
            () => _message = 'This quote expired. Nothing was sent. Go back and get a new quote.',
          );
        case ExchangeOutcomeKind.refused:
          setState(
            () => _message = 'For your safety this was not signed: the transaction did not match the quote. Nothing was sent.',
          );
        case ExchangeOutcomeKind.cancelled:
          setState(() => _message = 'Signing was cancelled. Nothing was sent.');
      }
    } on ApiException catch (e) {
      setState(
        () => _message = e.code == 'NETWORK'
            ? 'Cannot reach the Unbound service. Nothing was signed.'
            : 'The exchange was refused (${e.code}). Nothing was sent.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = QuoteReview.evaluate(
      widget.quote,
      ref.read(clockProvider)(),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Review exchange')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final line in review.disclosure)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
            const Divider(),
            if (review.needsNewQuote)
              const Text(
                'This quote has expired.',
                key: Key('expired'),
                style: TextStyle(fontWeight: FontWeight.bold),
              )
            else
              Text(
                'Quote expires in ${review.remaining.inSeconds}s',
                key: const Key('countdown'),
              ),
            if (!review.canProceed && !review.needsNewQuote)
              Text(
                'This quote cannot be used (${review.issues.map((i) => i.name).join(', ')}). Get a new quote.',
                key: const Key('quote-problem'),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _message!,
                  key: const Key('review-message'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            if (review.needsNewQuote || !review.canProceed)
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Get a new quote'),
              )
            else
              FilledButton(
                onPressed: _busy ? null : _approve,
                child: Text(_busy ? 'Working...' : 'Approve and sign'),
              ),
            const SizedBox(height: 8),
            const Text(
              'You sign on this device. Your secret key never leaves it. The exchange is only complete when the Stellar ledger confirms it.',
            ),
          ],
        ),
      ),
    );
  }
}
