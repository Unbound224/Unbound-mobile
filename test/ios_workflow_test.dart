import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The README promises an unsigned iOS build in CI; this keeps that promise honest.
void main() {
  test('CI builds iOS without code signing and skips forks by default', () {
    final w = File('.github/workflows/ci.yml').readAsStringSync();
    expect(w, contains('runs-on: macos-latest'));
    expect(w, contains('flutter build ios --release --no-codesign'));
    expect(
      w,
      contains(
        "if: github.repository == 'Unbound224/Unbound-mobile' || vars.IOS_BUILD == 'true'",
      ),
    );
    // No signing material: no certificates, profiles or signing secrets.
    for (final banned in [
      'secrets.',
      '.p12',
      '.mobileprovision',
      'CODE_SIGN_IDENTITY',
    ]) {
      expect(w, isNot(contains(banned)), reason: 'found "$banned" in ci.yml');
    }
  });

  test(
    'the iOS minimum version the README documents matches the Xcode project',
    () {
      final project = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
          .allMatches(project)
          .map((m) => m.group(1))
          .toSet();
      expect(targets, {'15.0'});
      expect(
        File('README.md').readAsStringSync(),
        contains('iOS 15.0 or later'),
      );
    },
  );
}
