import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/amount.dart';
import '../../domain/models.dart';
import '../../integrations/core_api.dart';

/// Step 1: choose amount and target, then ask for an indicative quote.
class ExchangeScreen extends ConsumerStatefulWidget {
  const ExchangeScreen({super.key, required this.holding});
  final HoldingView holding;
  @override
  ConsumerState<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends ConsumerState<ExchangeScreen> {
  final _amount = TextEditingController();
  AssetRef? _target;
  int _slippage = 100;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String? _validate() {
    final Amount a;
    try {
      a = Amount.parse(_amount.text.trim());
    } on FormatException {
      return 'Enter an amount with up to 7 decimals.';
    }
    if (a.isZero) {
      return 'Amount must be greater than zero.';
    }
    if (a > widget.holding.balance) {
      return 'You only hold ${widget.holding.balance.toDisplay()} ${widget.holding.asset.code}.';
    }
    if (_target == null) {
      return 'Choose what you want to receive.';
    }
    return null;
  }

  Future<void> _quote() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final wallet = ref.read(walletProvider).value!;
      final q = await ref
          .read(coreApiProvider)
          .requestQuote(
            source: widget.holding.asset,
            target: _target!,
            sourceAmount: Amount.parse(_amount.text.trim()).toString(),
            slippageBps: _slippage,
            destinationAccount: wallet.publicKey,
          );
      if (mounted) {
        await context.push('/review', extra: q);
      }
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'NO_ROUTE' => 'There is no liquidity for this exchange right now. Nothing was spent. Try a smaller amount or later.',
          'NETWORK' =>
            'Cannot reach the Unbound service. Check your connection.',
          'SENSITIVE_ACTIONS_PAUSED' =>
            'Exchanges are paused while a ledger discrepancy is investigated.',
          'ASSET_NOT_ELIGIBLE' =>
            'This credit is not currently eligible for exchange.',
          _ => 'The quote could not be created (${e.code}).',
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
    final targets = ref.watch(targetsProvider);
    final h = widget.holding;
    return Scaffold(
      appBar: AppBar(title: Text('Exchange ${h.asset.code}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Balance: ${h.balance.toDisplay()} ${h.asset.code}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount of ${h.asset.code} to sell',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            targets.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text(
                'Supported assets could not be loaded.',
                key: Key('targets-error'),
              ),
              data: (list) => DropdownButtonFormField<AssetRef>(
                key: const Key('target'),
                initialValue: _target,
                decoration: const InputDecoration(
                  labelText: 'Receive',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in list)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        '${t.code} (issuer ${t.issuer})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _target = v),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const Key('slippage'),
              initialValue: _slippage,
              decoration: const InputDecoration(
                labelText: 'Maximum slippage',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 50, child: Text('0.5%')),
                DropdownMenuItem(value: 100, child: Text('1%')),
                DropdownMenuItem(value: 200, child: Text('2%')),
              ],
              onChanged: (v) => setState(() => _slippage = v ?? 100),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const Key('exchange-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _quote,
              child: Text(_busy ? 'Getting quote...' : 'Get quote'),
            ),
            const SizedBox(height: 8),
            const Text(
              'A quote is indicative, expires quickly and is not a guarantee. You will review every detail before signing.',
            ),
          ],
        ),
      ),
    );
  }
}
