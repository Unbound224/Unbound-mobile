import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The site links to releases/latest/download/unbound-android.apk; this keeps the workflow honest.
void main() {
  test('release workflow publishes a latest, non-prerelease unbound-android.apk', () {
    final w = File('.github/workflows/release.yml').readAsStringSync();
    expect(w, contains("tags: ['v*']"));
    expect(w, contains('prerelease: false'));
    expect(w, contains('make_latest: true'));
    expect(
      w,
      contains(
        'mv build/app/outputs/flutter-apk/app-release.apk unbound-android.apk',
      ),
    );
    expect(w, contains('unbound-android.apk.sha256'));
    expect(w, isNot(contains('prerelease: true')));
  });
}
