// Renders README screenshots of the REAL Flutter screens, driven by the same test adapters as the widget tests
// (fake core API, in-memory keystore, synthetic Testnet fixture data). Not part of CI.
//
//   flutter test tool/screenshots/screenshots_test.dart --update-goldens
//
// Writes docs/screenshots/mobile-*.png (the committed copies are downscaled to 2/3 and palette-compressed). Fonts come from the Flutter SDK cache (Roboto + Material Icons) so text
// renders instead of the test font's boxes. These are headless renders, not device captures.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/app/harness.dart';

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('FLUTTER_ROOT is not set (run via flutter test)');
  }
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String name) async =>
      ByteData.sublistView(File('$dir/$name').readAsBytesSync());
  final roboto = FontLoader('Roboto')
    ..addFont(f('Roboto-Regular.ttf'))
    ..addFont(f('Roboto-Medium.ttf'))
    ..addFont(f('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(f('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  await tester.pumpAndSettle();
}

Future<void> _shot(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('../../docs/screenshots/mobile-$name.png'),
);

void main() {
  setUpAll(_loadFonts);

  testWidgets('first run', (tester) async {
    final r = Rig(withWallet: false);
    await r.pump(tester, signedIn: false);
    await _phone(tester);
    await _shot('welcome');
  });

  testWidgets('inventory', (tester) async {
    final r = Rig();
    await r.pump(tester);
    await _phone(tester);
    await _shot('inventory');
  });

  testWidgets('quote review', (tester) async {
    final r = Rig();
    r.api.quoteOverride = fxQuote;
    await r.pump(tester);
    await _phone(tester);
    await tester.tap(find.text('Exchange SHOP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '80');
    await tester.tap(find.byKey(const Key('target')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('USDC').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    expect(find.text('Review exchange'), findsOneWidget);
    await _shot('quote-review');
  });
}
