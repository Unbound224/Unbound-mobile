import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'integrations/file_pending_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  runApp(
    ProviderScope(
      // No automatic retry: failed financial reads surface to the user, who decides.
      retry: (_, _) => null,
      overrides: [
        pendingStoreProvider.overrideWithValue(
          FilePendingStore(File('${dir.path}/pending.json')),
        ),
      ],
      child: const UnboundApp(),
    ),
  );
}
