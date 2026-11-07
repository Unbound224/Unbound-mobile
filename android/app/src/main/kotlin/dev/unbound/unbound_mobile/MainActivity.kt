package dev.unbound.unbound_mobile

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (biometric / device-credential approval before signing) requires a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    // Screenshot / screen-recording / recent-apps-thumbnail blocking for the recovery-key screen (Android FLAG_SECURE).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.unbound/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") == true
                        runOnUiThread {
                            if (secure) {
                                window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(secure)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
