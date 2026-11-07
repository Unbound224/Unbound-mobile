import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android launcher identity: app name "Unbound" and the brand icon generated from
/// brand/icon.svg (via assets/branding/app_icon.png and flutter_launcher_icons) at every density.
(int, int) pngSize(String path) {
  final b = File(path).readAsBytesSync();
  expect(b.sublist(1, 4), 'PNG'.codeUnits, reason: path);
  final d = ByteData.sublistView(b, 16, 24);
  return (d.getUint32(0), d.getUint32(4));
}

void main() {
  const res = 'android/app/src/main/res';
  test('launcher icon exists at every density with the right size', () {
    for (final (dpi, px) in [
      ('mdpi', 48),
      ('hdpi', 72),
      ('xhdpi', 96),
      ('xxhdpi', 144),
      ('xxxhdpi', 192),
    ]) {
      expect(pngSize('$res/mipmap-$dpi/launcher_icon.png'), (
        px,
        px,
      ), reason: dpi);
    }
    expect(pngSize('assets/branding/app_icon.png'), (1024, 1024));
    final adaptive = File('$res/mipmap-anydpi-v26/launcher_icon.xml')
        .readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@color/ic_launcher_background'));
  });

  test('manifest uses the brand name and icon', () {
    final m = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(m, contains('android:label="Unbound"'));
    expect(m, contains('android:icon="@mipmap/launcher_icon"'));
    final colors = Directory('$res/values')
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join();
    // adaptive icon background is the brand ink #10092E
    expect(colors.toUpperCase(), contains('#10092E'));
  });
}
