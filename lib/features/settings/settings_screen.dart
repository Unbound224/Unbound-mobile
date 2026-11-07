import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';

/// Security and trusted-issuer settings: what this device holds, which network, who the issuers are.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider).value;
    final pf = ref.watch(portfolioProvider).value;
    final issuers = <String, HoldingView>{
      for (final h in pf?.holdings ?? <HoldingView>[])
        if (h.usable) h.asset.issuer ?? '': h,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Security and issuers')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ListTile(
              title: Text('Network'),
              subtitle: Text('Stellar Testnet only'),
            ),
            ListTile(
              title: const Text('Wallet address'),
              subtitle: SelectableText(wallet?.publicKey ?? 'none'),
            ),
            ListTile(
              key: const Key('open-backup'),
              title: const Text('Back up recovery key'),
              subtitle: const Text(
                'Stored in this device\'s secure keystore and never sent. Write it down so you can restore this wallet on a new phone.',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: wallet != null,
              onTap: () => context.push('/backup'),
            ),
            const Divider(),
            Text(
              'Verified issuers you hold',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (issuers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('None.', key: Key('no-issuers')),
              ),
            for (final h in issuers.values)
              ListTile(
                title: Text(h.asset.code),
                subtitle: Text(
                  '${h.asset.issuer}\n${h.unitOfAccount ?? ''}\nContact: ${h.contact ?? 'n/a'}',
                ),
                isThreeLine: true,
              ),
            const Divider(),
            OutlinedButton(
              onPressed: () =>
                  ref.read(sessionTokenProvider.notifier).set(null),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: wallet == null
                  ? null
                  : () => _confirmWipe(context, ref),
              child: const Text('Remove wallet from this device'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove wallet?'),
        content: const Text(
          'The secret key will be deleted from this device and cannot be recovered. Credits held by this wallet become inaccessible.',
        ),
        actions: [
          TextButton(
            onPressed: () => c.pop(false),
            child: const Text('Keep wallet'),
          ),
          TextButton(
            onPressed: () => c.pop(true),
            child: const Text('Delete it'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(walletProvider.notifier).wipe();
      if (context.mounted) {
        context.go('/');
      }
    }
  }
}
