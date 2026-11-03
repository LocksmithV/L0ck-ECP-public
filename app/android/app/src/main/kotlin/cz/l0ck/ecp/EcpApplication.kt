package cz.l0ck.ecp

import android.app.Application
import cz.l0ck.ecp.bramble.BrambleHost
import cz.l0ck.ecp.location.LocationHost
import cz.l0ck.ecp.net.NetHost
import cz.l0ck.ecp.notify.NotifyHost
import cz.l0ck.ecp.radio.RadioHost
import cz.l0ck.ecp.sms.SmsHost
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.briarproject.bramble.BrambleAppComponent
import org.briarproject.bramble.BrambleApplication

/**
 * Owns the Flutter engine instead of the activity, so the Dart side (unlocked profile, PACE
 * router) keeps running while the screen is locked or the activity is gone; EcpService keeps
 * the process alive.
 */
class EcpApplication : Application(), BrambleApplication {

    companion object {
        const val ENGINE = "main"
    }

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, KeystoreStrengthener.CHANNEL).setMethodCallHandler(KeystoreStrengthener())
        BrambleHost.get(this).attach(messenger)
        RadioHost.get(this).attach(messenger)
        SmsHost.get(this).attach(messenger)
        NotifyHost(this).attach(messenger)
        LocationHost(this).attach(messenger)
        NetHost(this).attach(messenger)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE, engine)
    }

    override fun getBrambleAppComponent(): BrambleAppComponent = BrambleHost.get(this).appComponent()
}
