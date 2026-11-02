import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/amount.dart';
import '../../domain/models.dart';
import '../../domain/status_text.dart';
import '../../flows/ports.dart';
import '../../flows/redemption_flow.dart';
import '../../integrations/core_api.dart';

/// Redeem verified credit with the merchant that issued it. Two steps are shown honestly:
/// the ledger return, then the merchant's fulfilment.
class RedeemScreen extends ConsumerStatefulWidget {
  const RedeemScreen({super.key, required this.holding});
  final HoldingView holding;
  @override
  ConsumerState<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends ConsumerState<RedeemScreen> {
  final _amount = TextEditingController();
  bool _busy = false;
  String? _error;
  RedemptionResult? _result;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final Amount a;
    try {
      a = Amount.parse(_amount.text.trim());
    } on FormatException {
      setState(() => _error = 'Enter an amount with up to 7 decimals.');
      return;
    }
    if (a.isZero || a > widget.holding.balance) {
      setState(
        () => _error =
            'Enter an amount between 0 and ${widget.holding.balance.toDisplay()}.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(redemptionFlowProvider)
          .redeem(asset: widget.holding.asset, amount: a);
      setState(() {
        switch (r.kind) {
          case RedemptionOutcomeKind.refused:
            _error = 'For your safety this was not signed: the transaction did not match the redemption. Nothing was sent.';
          case RedemptionOutcomeKind.cancelled:
            _error = 'Signing was cancelled. Nothing was sent.';
          case RedemptionOutcomeKind.terminal:
          case RedemptionOutcomeKind.inFlight:
            _result = r;
        }
      });
    } on SigningCancelled {
      setState(() => _error = 'Signing was cancelled. Nothing was sent.');
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'REDEMPTION_UNAVAILABLE' => 'The issuer does not offer redemption for this amount or credit right now. Nothing was sent.',
          'NETWORK' => 'Cannot reach the Unbound service. Nothing was sent.',
          _ => 'Redemption could not start (${e.code}).',
        },
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.holding;
    final r = _result?.redemption;
    final text = r == null ? null : redemptionStatus(r);
    return Scaffold(
      appBar: AppBar(title: Text('Redeem ${h.asset.code}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'You return credit to the issuer on the ledger, then the merchant confirms fulfilment under its own published terms. '
              'Unbound does not pay out cash.',
            ),
            if (h.contact != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Issuer contact: ${h.contact}'),
              ),
            const SizedBox(height: 12),
            if (_result == null) ...[
              TextField(
                key: const Key('redeem-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount of ${h.asset.code} to redeem',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('redeem-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _start,
                child: Text(
                  _busy
                      ? 'Working...'
                      : 'Approve return and request redemption',
                ),
              ),
            ] else if (text != null) ...[
              Text(
                text.headline,
                key: const Key('redeem-headline'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(text.detail, key: const Key('redeem-detail')),
              if (r!.refundDue)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Refund owed to you by the issuer.',
                    key: Key('refund-due'),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              if (_result!.stale)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the last known state; you appear to be offline.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
