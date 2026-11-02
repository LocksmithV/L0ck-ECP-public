package cz.l0ck.ecp

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.pm.PackageManager
import com.google.zxing.integration.android.IntentIntegrator
import cz.l0ck.ecp.notify.NotifyHost
import com.journeyapps.barcodescanner.CaptureActivity
import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // No screenshots, screen recording or recents thumbnails of message content
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        rememberOpen(intent)
    }

    // A tapped "new message" notification: which conversation to show after the PIN
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        rememberOpen(intent)
    }

    private fun rememberOpen(i: Intent?) {
        i?.getStringExtra(NotifyHost.EXTRA_OPEN)?.let { pendingOpen = it }
        i?.removeExtra(NotifyHost.EXTRA_OPEN)
    }

    // The engine belongs to EcpApplication and outlives this activity
    override fun getCachedEngineId(): String = EcpApplication.ENGINE

    private var permissionsChannel: MethodChannel? = null
    private var pendingPermissions: MethodChannel.Result? = null
    private var scanChannel: MethodChannel? = null
    private var pendingScan: MethodChannel.Result? = null
    private var pendingDiscoverable: MethodChannel.Result? = null

    // Runtime permissions need an activity, so this channel lives and dies with it
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        permissionsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "request") return@setMethodCallHandler result.notImplemented()
                val wanted = call.argument<List<String>>("permissions").orEmpty()
                    .filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                if (wanted.isEmpty()) return@setMethodCallHandler result.success(true)
                pendingPermissions?.success(false)
                pendingPermissions = result
                requestPermissions(wanted.toTypedArray(), 1)
            }
        }

        // Emergency lock hides the app at once
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cz.l0ck.ecp/activity")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeOpen" -> {
                        result.success(pendingOpen)
                        pendingOpen = null
                    }
                    // geo: to an installed map app (OsmAnd, Organic Maps…), https: to the browser
                    "openGeo", "openUri" -> {
                        val uri = android.net.Uri.parse(call.argument<String>("uri"))
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(true)
                        } catch (_: android.content.ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                    "minimize" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    // Bluetooth setup with a contact: visible for 2 minutes (system dialog)
                    "discoverable" -> {
                        pendingDiscoverable?.success(false)
                        pendingDiscoverable = result
                        startActivityForResult(
                            Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                                .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120),
                            REQUEST_DISCOVERABLE)
                    }
                    else -> result.notImplemented()
                }
            }

        // QR scanning needs this activity too (startActivityForResult)
        scanChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCAN).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "scan") return@setMethodCallHandler result.notImplemented()
                pendingScan?.success(null)
                pendingScan = result
                IntentIntegrator(this@MainActivity)
                    .setCaptureActivity(ScanActivity::class.java)
                    .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                    .setOrientationLocked(true)
                    .setBeepEnabled(false)
                    .setPrompt(call.argument<String>("prompt") ?: "")
                    .initiateScan()
            }
        }
    }

    @Deprecated("FlutterActivity is not a ComponentActivity; the result API is not available")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_DISCOVERABLE) {
            pendingDiscoverable?.success(resultCode != RESULT_CANCELED)
            pendingDiscoverable = null
            return
        }
        val r = IntentIntegrator.parseActivityResult(requestCode, resultCode, data)
        if (r == null) return super.onActivityResult(requestCode, resultCode, data)
        pendingScan?.success(r.contents)
        pendingScan = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        scanChannel?.setMethodCallHandler(null)
        scanChannel = null
        permissionsChannel?.setMethodCallHandler(null)
        permissionsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        pendingPermissions?.success(results.all { it == PackageManager.PERMISSION_GRANTED })
        pendingPermissions = null
    }

    companion object {
        const val PERMISSIONS = "cz.l0ck.ecp/permissions"
        const val SCAN = "cz.l0ck.ecp/scan"
        const val REQUEST_DISCOVERABLE = 7301

        /** Conversation from the last tapped notification, until Dart takes it. */
        @Volatile
        var pendingOpen: String? = null
    }
}

/**
 * Binds the PIN-derived key to this device (docs/ARCHITECTURE_V2.md §6): HMAC-SHA256 under a
 * non-exportable Keystore key, StrongBox when the phone has one. A copy of the app's storage
 * is useless without this exact device; deleting the key makes every slot unopenable.
 */
class KeystoreStrengthener : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "cz.l0ck.ecp/keystore"
        private const val ALIAS = "ecp_kek"
        private const val PROVIDER = "AndroidKeyStore"
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "strengthen" -> {
                    val input = call.argument<ByteArray>("key")
                        ?: return result.error("ARG", "missing key", null)
                    val mac = Mac.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256)
                    mac.init(getOrCreateKey())
                    result.success(mac.doFinal(input))
                }
                "deleteKey" -> {
                    keyStore().deleteEntry(ALIAS)
                    result.success(null)
                }
                "info" -> result.success(mapOf("hasKey" to keyStore().containsAlias(ALIAS)))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("KEYSTORE", e.toString(), null)
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    private fun getOrCreateKey(): SecretKey {
        val ks = keyStore()
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        // Prefer StrongBox (dedicated secure element); fall back to the TEE where absent
        if (Build.VERSION.SDK_INT >= 28) {
            try {
                return generate(strongBox = true)
            } catch (_: StrongBoxUnavailableException) {
            }
        }
        return generate(strongBox = false)
    }

    private fun generate(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            .setKeySize(256)
            .apply { if (Build.VERSION.SDK_INT >= 28) setIsStrongBoxBacked(strongBox) }
            .build()
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, PROVIDER)
        gen.init(spec)
        return gen.generateKey()
    }
}

/** ZXing's scanner, held upright like the rest of the app. */
class ScanActivity : CaptureActivity()
