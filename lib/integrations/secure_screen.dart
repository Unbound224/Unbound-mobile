import 'package:flutter/services.dart';

/// Blocks screenshots, screen recording and the recent-apps thumbnail while sensitive content is on screen.
///
/// Android only: it sets `FLAG_SECURE` on the activity window through a small platform channel
/// (`MainActivity.kt`). iOS has no equivalent switch for screenshots, so there [enable] reports `false` and the
/// caller must not claim protection. Failures never throw: the screen still works, just unprotected.
class SecureScreen {
  SecureScreen({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'dev.unbound/secure_screen';
  final MethodChannel _channel;

  /// True when the platform confirmed the window is now protected.
  Future<bool> enable() => _set(true);

  /// Always call this when the sensitive screen goes away.
  Future<bool> disable() => _set(false);

  Future<bool> _set(bool secure) async {
    try {
      return await _channel.invokeMethod<bool>('setSecure', {
            'secure': secure,
          }) ??
          false;
    } on MissingPluginException {
      return false; // iOS, desktop, tests
    } on PlatformException {
      return false;
    }
  }
}
