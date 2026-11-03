import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../integrations/core_api.dart';
import '../../integrations/secure_wallet_signer.dart';
import '../../flows/ports.dart';
import '../inventory/inventory_screen.dart';

/// Home gate: wallet -> sign-in -> inventory. Testnet only, stated up front.
class GateScreen extends ConsumerWidget {
  const GateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final token = ref.watch(sessionTokenProvider);
    return wallet.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _Scaffold(
        child: Text(
          'Could not open the wallet on this device.',
          key: const Key('wallet-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      data: (w) {
        if (w == null) {
          return const _CreateWallet();
        }
        if (token == null) {
          return const _SignIn();
        }
        return const InventoryScreen();
      },
    );
  }
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unbound')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [child]),
      ),
    ),
  );
}

const _testnetNotice =
    'Testnet demo. Synthetic assets only: no real money, no cash-out, and no store listing. A credit only has value here if a verified issuer has agreed to honor it.';

class _CreateWallet extends ConsumerWidget {
  const _CreateWallet();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Scaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to Unbound',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(_testnetNotice),
        const SizedBox(height: 12),
        const Text(
          'Create a Testnet wallet on this device. Its secret key stays in the device keystore and is never sent anywhere. '
          'Back it up afterwards from Security and issuers; Unbound cannot recover it for you.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => ref.read(walletProvider.notifier).create(),
          child: const Text('Create Testnet wallet'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('open-restore'),
          onPressed: () => context.push('/restore'),
          child: const Text('Restore from recovery key'),
        ),
      ],
    ),
  );
}

class _SignIn extends ConsumerStatefulWidget {
  const _SignIn();
  @override
  ConsumerState<_SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<_SignIn> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(walletProvider.notifier).signIn();
    } on SigningCancelled {
      _error = 'Sign-in was cancelled.';
    } on ApiException catch (e) {
      _error = e.code == 'NETWORK'
          ? 'Cannot reach the Unbound service. Check your connection and try again.'
          : 'Sign-in failed (${e.code}).';
    } on WalletNotCreated {
      _error = 'No wallet on this device.';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(walletProvider).value;
    return _Scaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text(_testnetNotice),
          const SizedBox(height: 12),
          Text('Wallet: ${w?.publicKey ?? ''}', key: const Key('wallet-key')),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                key: const Key('signin-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy ? 'Signing in...' : 'Sign in with my wallet'),
          ),
        ],
      ),
    );
  }
}
