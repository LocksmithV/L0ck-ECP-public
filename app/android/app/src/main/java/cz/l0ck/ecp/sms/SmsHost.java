package cz.l0ck.ecp.sms;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.telephony.SmsManager;
import android.telephony.TelephonyManager;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * PACE layer E: plain text SMS (docs/ARCHITECTURE_V2.md §3: base64url, no prefix). Sending
 * waits for the radio's verdict, so a SIM without credit or signal reports failure and the
 * router moves on. Incoming SMS arrive through [SmsReceiver]; matching them to contacts and
 * decoding happen in Dart.
 */
public final class SmsHost {

	public static final String METHODS = "cz.l0ck.ecp/sms";
	public static final String EVENTS = "cz.l0ck.ecp/sms/events";
	private static final String SENT = "cz.l0ck.ecp.SMS_SENT";

	private static SmsHost instance;

	public static synchronized SmsHost get(Context c) {
		if (instance == null) instance = new SmsHost((Application) c.getApplicationContext());
		return instance;
	}

	private final Application app;
	private final Handler main = new Handler(Looper.getMainLooper());
	private final AtomicInteger nextId = new AtomicInteger();
	private final Map<Integer, MethodChannel.Result> pending = new HashMap<>();
	private final Map<Integer, Integer> partsLeft = new HashMap<>();
	// SMS that arrived before Dart listened (process woken by the SMS itself)
	private final ArrayDeque<Map<String, Object>> backlog = new ArrayDeque<>();
	private EventChannel.EventSink sink;

	private SmsHost(Application app) {
		this.app = app;
		IntentFilter f = new IntentFilter(SENT);
		if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(sentReceiver, f, Context.RECEIVER_NOT_EXPORTED);
		else app.registerReceiver(sentReceiver, f);
	}

	public void attach(BinaryMessenger messenger) {
		new MethodChannel(messenger, METHODS).setMethodCallHandler(this::onCall);
		new EventChannel(messenger, EVENTS).setStreamHandler(new EventChannel.StreamHandler() {
			@Override
			public void onListen(Object arguments, EventChannel.EventSink events) {
				sink = events;
				while (!backlog.isEmpty()) sink.success(backlog.poll());
			}

			@Override
			public void onCancel(Object arguments) {
				sink = null;
			}
		});
	}

	private boolean granted(String p) {
		return app.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED;
	}

	private void onCall(MethodCall call, MethodChannel.Result result) {
		switch (call.method) {
			case "status": {
				TelephonyManager tm = app.getSystemService(TelephonyManager.class);
				Map<String, Object> m = new HashMap<>();
				m.put("send", granted(Manifest.permission.SEND_SMS));
				m.put("receive", granted(Manifest.permission.RECEIVE_SMS));
				m.put("sim", tm != null && tm.getSimState() == TelephonyManager.SIM_STATE_READY);
				result.success(m);
				break;
			}
			case "send":
				send(call.argument("to"), call.argument("text"), result);
				break;
			default:
				result.notImplemented();
		}
	}

	@SuppressWarnings("deprecation")
	private void send(String to, String text, MethodChannel.Result result) {
		if (!granted(Manifest.permission.SEND_SMS)) {
			result.success(false);
			return;
		}
		try {
			SmsManager sms = Build.VERSION.SDK_INT >= 31
					? app.getSystemService(SmsManager.class) : SmsManager.getDefault();
			ArrayList<String> parts = sms.divideMessage(text);
			int id = nextId.incrementAndGet();
			ArrayList<PendingIntent> sent = new ArrayList<>();
			for (int i = 0; i < parts.size(); i++) {
				Intent intent = new Intent(SENT).setPackage(app.getPackageName()).putExtra("id", id);
				sent.add(PendingIntent.getBroadcast(app, id * 16 + i, intent,
						PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_ONE_SHOT));
			}
			pending.put(id, result);
			partsLeft.put(id, parts.size());
			if (parts.size() == 1) sms.sendTextMessage(to, null, text, sent.get(0), null);
			else sms.sendMultipartTextMessage(to, null, parts, sent, null);
			// No verdict within a minute (no network at all): report failure, move on
			main.postDelayed(() -> finish(id, false), 60_000);
		} catch (Exception e) {
			result.success(false);
		}
	}

	private void finish(int id, boolean ok) {
		MethodChannel.Result r = pending.remove(id);
		partsLeft.remove(id);
		if (r != null) r.success(ok);
	}

	private final BroadcastReceiver sentReceiver = new BroadcastReceiver() {
		@Override
		public void onReceive(Context c, Intent i) {
			int id = i.getIntExtra("id", -1);
			if (getResultCode() != Activity.RESULT_OK) {
				finish(id, false);
				return;
			}
			Integer left = partsLeft.get(id);
			if (left == null) return;
			if (left <= 1) finish(id, true);
			else partsLeft.put(id, left - 1);
		}
	};

	/** From [SmsReceiver], on the main thread. */
	void deliver(String from, String body) {
		Map<String, Object> m = new HashMap<>();
		m.put("type", "sms");
		m.put("from", from);
		m.put("body", body);
		if (sink != null) sink.success(m);
		else if (backlog.size() < 50) backlog.add(m);
	}
}
