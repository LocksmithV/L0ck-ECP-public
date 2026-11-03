package cz.l0ck.ecp

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import com.google.zxing.integration.android.IntentIntegrator
import cz.l0ck.ecp.notify.NotifyHost
import com.journeyapps.barcodescanner.CaptureActivity
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
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
    private var pendingFiles: MethodChannel.Result? = null
    private var photoFile: File? = null
    private var toSave: ByteArray? = null

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

        // Fingerprint instead of the PIN for the running profile (settings); strong biometrics
        // only, Android 11+
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC)
            .setMethodCallHandler { call, result ->
                if (Build.VERSION.SDK_INT < 30) return@setMethodCallHandler result.success(false)
                val strong = BiometricManager.Authenticators.BIOMETRIC_STRONG
                when (call.method) {
                    "available" -> result.success(
                        getSystemService(BiometricManager::class.java)
                            .canAuthenticate(strong) == BiometricManager.BIOMETRIC_SUCCESS)
                    "authenticate" -> {
                        var answered = false
                        fun reply(ok: Boolean) {
                            if (answered) return
                            answered = true
                            result.success(ok)
                        }
                        BiometricPrompt.Builder(this)
                            .setTitle(call.argument<String>("title") ?: "")
                            .setNegativeButton(call.argument<String>("cancel") ?: "", mainExecutor) { _, _ ->
                                reply(false)
                            }
                            .setAllowedAuthenticators(strong)
                            .setConfirmationRequired(false)
                            .build()
                            .authenticate(CancellationSignal(), mainExecutor,
                                object : BiometricPrompt.AuthenticationCallback() {
                                    override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult?) =
                                        reply(true)

                                    // Cancelled, too many tries, sensor gone: back to the PIN
                                    override fun onAuthenticationError(code: Int, message: CharSequence?) =
                                        reply(false)
                                })
                    }
                    else -> result.notImplemented()
                }
            }

        // Chat attachments: a photo with the camera app, a file from the system picker, saving a
        // received one where the user chooses. Storage Access Framework: no storage permission.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES).setMethodCallHandler { call, result ->
            pendingFiles?.success(null)
            pendingFiles = result
            try {
                when (call.method) {
                    "photo" -> {
                        val dir = File(cacheDir, "photos").apply { mkdirs() }
                        val f = File.createTempFile("photo", ".jpg", dir)
                        photoFile = f
                        val uri = FileProvider.getUriForFile(this, "$packageName.photos", f)
                        startActivityForResult(Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                            .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                            .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION), REQUEST_PHOTO)
                    }
                    "pick" -> startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"), REQUEST_PICK)
                    "save" -> {
                        toSave = call.argument<ByteArray>("data")
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(call.argument<String>("mime") ?: "application/octet-stream")
                            .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "soubor"), REQUEST_SAVE)
                    }
                    else -> {
                        pendingFiles = null
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                pendingFiles = null
                result.error("FILES", e.toString(), null)
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
        if (requestCode == REQUEST_PHOTO || requestCode == REQUEST_PICK || requestCode == REQUEST_SAVE) {
            val result = pendingFiles ?: return
            pendingFiles = null
            val ok = resultCode == RESULT_OK
            Thread {
                val answer: Any? = try {
                    when (requestCode) {
                        REQUEST_PHOTO -> photoFile?.let { f ->
                            photoFile = null
                            val jpeg = if (ok && f.length() > 0) shrinkPhoto(f) else null
                            f.delete()
                            jpeg
                        }
                        REQUEST_PICK -> data?.data?.takeIf { ok }?.let { readPicked(it) }
                        else -> {
                            val bytes = toSave
                            toSave = null
                            val uri = data?.data
                            if (ok && uri != null && bytes != null) {
                                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                                true
                            } else false
                        }
                    }
                } catch (e: Exception) {
                    null
                }
                runOnUiThread { result.success(answer) }
            }.start()
            return
        }
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

    /** The photo upright, at most 1600 px, re-encoded as JPEG under [MAX_ATTACHMENT] bytes —
     *  which also drops every EXIF field, the GPS position and the camera model among them. */
    private fun shrinkPhoto(f: File): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
        var bmp = BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalStateException("no image")
        val m = Matrix()
        when (ExifInterface(f.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
        }
        val scale = minOf(1f, 1600f / maxOf(bmp.width, bmp.height))
        m.postScale(scale, scale)
        bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        var quality = 75
        while (true) {
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, quality, out)
            if (out.size() <= MAX_ATTACHMENT || quality <= 30) return out.toByteArray()
            quality -= 15
        }
    }

    /** {name, mime, data}, or {name, size} without data when it is over [MAX_ATTACHMENT]. */
    private fun readPicked(uri: Uri): Map<String, Any?> {
        var name = "soubor"
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) ?: name }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !c.isNull(it) }?.let { size = c.getLong(it) }
            }
        }
        val mime = contentResolver.getType(uri) ?: "application/octet-stream"
        if (size > MAX_ATTACHMENT) return mapOf("name" to name, "size" to size)
        val bytes = contentResolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(16 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                if (out.size() > MAX_ATTACHMENT) return mapOf("name" to name, "size" to out.size().toLong())
            }
            out.toByteArray()
        } ?: throw IllegalStateException("cannot read")
        return mapOf("name" to name, "mime" to mime, "data" to bytes)
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
        const val BIOMETRIC = "cz.l0ck.ecp/biometric"
        const val REQUEST_DISCOVERABLE = 7301
        const val REQUEST_PHOTO = 7302
        const val REQUEST_PICK = 7303
        const val REQUEST_SAVE = 7304
        const val FILES = "cz.l0ck.ecp/files"

        /** Attachment.maxBytes (ecp_core). */
        const val MAX_ATTACHMENT = 512 * 1024

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
