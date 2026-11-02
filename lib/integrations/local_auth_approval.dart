import 'package:local_auth/local_auth.dart';

import 'secure_wallet_signer.dart';

/// Biometric / device-credential confirmation before signing. UNVERIFIED on real devices
/// (no device or emulator was available); it compiles and is covered only by the port's fake in tests.
class LocalAuthApproval implements UserApproval {
  LocalAuthApproval([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> confirm(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) {
        // Fail closed: without a device credential we do not sign.
        return false;
      }
      return await _auth.authenticate(localizedReason: reason);
    } on Exception {
      return false;
    }
  }
}
