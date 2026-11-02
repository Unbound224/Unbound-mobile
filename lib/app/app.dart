import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design_system/theme.dart';
import 'router.dart';

class UnboundApp extends ConsumerStatefulWidget {
  const UnboundApp({super.key});
  @override
  ConsumerState<UnboundApp> createState() => _UnboundAppState();
}

class _UnboundAppState extends ConsumerState<UnboundApp> {
  final GoRouter _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Unbound (Testnet)',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: _router,
  );
}
