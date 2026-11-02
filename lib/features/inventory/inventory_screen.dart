import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../integrations/core_api.dart';

String statusLabel(HoldingStatus s) => switch (s) {
  HoldingStatus.redeemable => 'Verified issuer',
  HoldingStatus.supportedAsset => 'Supported asset (not store credit)',
  HoldingStatus.unverified => 'No verified issuer',
  HoldingStatus.suspended => 'Issuer suspended',
  HoldingStatus.expired => 'Redemption terms expired',
  HoldingStatus.frozen => 'Frozen by the issuer',
};

String statusExplanation(HoldingStatus s) => switch (s) {
  HoldingStatus.redeemable => '',
  HoldingStatus.supportedAsset =>
    'You can hold this, but it is not redeemable merchant credit.',
  HoldingStatus.unverified => 'No issuer has agreed to honor this, so it has no usable value here. It cannot be exchanged or redeemed.',
  HoldingStatus.suspended =>
    'The issuer is suspended. Exchange and redemption are unavailable.',
  HoldingStatus.expired => 'The issuer\'s redemption terms have expired. Exchange and redemption are unavailable.',
  HoldingStatus.frozen =>
    'The issuer has frozen your balance of this asset. Contact the issuer.',
};

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pf = ref.watch(portfolioProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My credits'),
        actions: [
          IconButton(
            tooltip: 'Settings and security',
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(portfolioProvider.future),
          child: pf.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  e is ApiException && e.code == 'NETWORK'
                      ? 'You appear to be offline. Balances cannot be shown right now.'
                      : 'Balances could not be loaded.',
                  key: const Key('inventory-error'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(portfolioProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
            data: (p) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Testnet demo. Values below are ledger balances, not money.',
                ),
                const SizedBox(height: 8),
                if (p.holdings.isEmpty)
                  const Text(
                    'You hold no credits yet.',
                    key: Key('inventory-empty'),
                  ),
                for (final h in p.holdings) _HoldingCard(h),
                const SizedBox(height: 8),
                Text(p.notice, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard(this.h);
  final HoldingView h;

  @override
  Widget build(BuildContext context) {
    final code = h.asset.code;
    return Card(
      key: Key('holding-$code-${h.asset.issuer}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${h.balance.toDisplay()} $code',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Issuer ${h.asset.issuer}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Chip(label: Text(statusLabel(h.status))),
            if (h.usable) ...[
              if (h.unitOfAccount != null) Text(h.unitOfAccount!),
              if (h.expiresAt != null)
                Text(
                  'Terms valid until ${h.expiresAt!.toIso8601String().substring(0, 10)}',
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => context.push('/exchange', extra: h),
                child: Text('Exchange $code'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push('/redeem', extra: h),
                child: Text('Redeem $code with the merchant'),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(statusExplanation(h.status)),
              ),
          ],
        ),
      ),
    );
  }
}
