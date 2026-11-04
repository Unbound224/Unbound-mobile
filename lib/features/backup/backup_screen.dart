import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../flows/ports.dart';
import '../../integrations/secure_screen.dart';

/// Wallet backup: shows the recovery key once the person has read the warnings and approved on
/// the device. It is never copied to the clipboard, logged or sent. While this screen is open,
/// screenshots, screen recording and the recent-apps thumbnail are blocked on Android
/// (FLAG_SECURE through [SecureScreen]); iOS has no such switch, so nothing is claimed there.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key, this.secureScreen});
  final SecureScreen? secureScreen;
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late final SecureScreen _secure = widget.secureScreen ?? SecureScreen();
  bool _understood = false;

  @override
  void initState() {
    super.initState();
    unawaited(_secure.enable());
  }

  String? _key;
  String? _error;
  bool _busy = false;

  Future<void> _reveal() async {
    final w = ref.read(walletProvider).value;
    if (w == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final k = await w.revealRecoveryKey();
      setState(() => _key = k);
    } on SigningCancelled {
      setState(() => _error = 'Not approved. The recovery key stays hidden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_secure.disable());
    _key = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _key == null
        ? const <String>[]
        : [
            for (var i = 0; i < _key!.length; i += 4)
              _key!.substring(i, i + 4 > _key!.length ? _key!.length : i + 4),
          ];
    return Scaffold(
      appBar: AppBar(title: const Text('Back up your wallet')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Your recovery key is the only way to get this wallet back if you lose or reset this phone. '
              'Unbound cannot recover it for you: it never leaves this device.',
            ),
            const SizedBox(height: 12),
            const _Bullet('Write it on paper and keep it somewhere private.'),
            const _Bullet(
              'Anyone who sees it controls the wallet. Unbound will never ask for it.',
            ),
            const _Bullet(
              'Do not screenshot it, paste it into apps, or store it in the cloud.',
            ),
            const _Bullet(
              'Testnet only: this wallet holds synthetic assets, but treat the habit seriously.',
            ),
            const SizedBox(height: 12),
            if (_key == null) ...[
              CheckboxListTile(
                key: const Key('backup-understood'),
                value: _understood,
                onChanged: (v) => setState(() => _understood = v ?? false),
                title: const Text(
                  'I understand that anyone with this key controls my wallet.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('backup-reveal'),
                onPressed: _understood && !_busy ? _reveal : null,
                child: Text(
                  _busy ? 'Waiting for approval...' : 'Show recovery key',
                ),
              ),
            ] else ...[
              Semantics(
                label:
                    'Recovery key, ${groups.length} groups of four characters',
                child: Card(
                  key: const Key('backup-key'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        for (final g in groups)
                          Text(
                            g,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Spaces are only for readability. To restore, choose "Restore from recovery key" on a new install.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('backup-done'),
                onPressed: () {
                  setState(() => _key = null);
                  Navigator.of(context).maybePop();
                },
                child: const Text('I wrote it down; hide it'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const Key('backup-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// Restore an existing wallet on this device from its recovery key.
class RestoreWalletScreen extends ConsumerStatefulWidget {
  const RestoreWalletScreen({super.key});
  @override
  ConsumerState<RestoreWalletScreen> createState() => _RestoreState();
}

class _RestoreState extends ConsumerState<RestoreWalletScreen> {
  final _c = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.clear();
    _c.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(walletProvider.notifier).restore(_c.text);
      _c.clear();
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      setState(
        () => _error = 'That is not a valid recovery key. Check each character (it starts with S and has 56 characters).',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Restore wallet')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Type the recovery key you wrote down. It is checked on this device and stored only in its secure keystore.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('restore-key'),
            controller: _c,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z2-7 ]')),
            ],
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Recovery key',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                key: const Key('restore-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('restore-submit'),
            onPressed: _busy ? null : _restore,
            child: Text(_busy ? 'Checking...' : 'Restore wallet'),
          ),
        ],
      ),
    ),
  );
}
