import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../features/backup/backup_screen.dart';
import '../features/exchange/exchange_screen.dart';
import '../features/exchange/review_screen.dart';
import '../features/exchange/status_screen.dart';
import '../features/onboarding/gate_screen.dart';
import '../features/redemption/redeem_screen.dart';
import '../features/settings/settings_screen.dart';

/// `extra` carries in-memory objects between steps; deep links to those routes fall back to home.
GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const GateScreen()),
    GoRoute(
      path: '/exchange',
      builder: (_, s) => s.extra is HoldingView
          ? ExchangeScreen(holding: s.extra! as HoldingView)
          : const GateScreen(),
    ),
    GoRoute(
      path: '/review',
      builder: (_, s) => s.extra is Quote
          ? ReviewScreen(quote: s.extra! as Quote)
          : const GateScreen(),
    ),
    GoRoute(
      path: '/status/:id',
      builder: (_, s) => StatusScreen(intentId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/redeem',
      builder: (_, s) => s.extra is HoldingView
          ? RedeemScreen(holding: s.extra! as HoldingView)
          : const GateScreen(),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
    GoRoute(path: '/restore', builder: (_, _) => const RestoreWalletScreen()),
  ],
);
