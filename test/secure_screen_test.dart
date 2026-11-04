import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unbound_mobile/features/backup/backup_screen.dart';
import 'package:unbound_mobile/integrations/secure_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  void mock(Future<Object?>? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(SecureScreen.channelName),
          (c) async {
            calls.add(c);
            return handler(c);
          },
        );
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(SecureScreen.channelName),
          null,
        );
  });

  test('enable and disable call the platform with the secure flag and report its answer', () async {
    mock((c) async => (c.arguments as Map)['secure']);
    final s = SecureScreen();
    expect(await s.enable(), isTrue);
    expect(await s.disable(), isFalse);
    expect(calls.map((c) => c.method), ['setSecure', 'setSecure']);
    expect(calls.map((c) => (c.arguments as Map)['secure']), [true, false]);
  });

  test('without a platform implementation (iOS, tests) it reports false instead of throwing', () async {
    final s = SecureScreen(
      channel: const MethodChannel('dev.unbound/not_registered'),
    );
    expect(await s.enable(), isFalse);
  });

  test('a platform error is swallowed and reported as unprotected', () async {
    mock((c) async => throw PlatformException(code: 'boom'));
    expect(await SecureScreen().enable(), isFalse);
  });

  testWidgets(
    'the recovery-key screen turns protection on when shown and off when it goes away',
    (t) async {
      mock((c) async => (c.arguments as Map)['secure']);
      await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: BackupScreen())),
      );
      await t.pump();
      expect(calls.map((c) => (c.arguments as Map)['secure']), [true]);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(calls.map((c) => (c.arguments as Map)['secure']), [true, false]);
    },
  );
}
