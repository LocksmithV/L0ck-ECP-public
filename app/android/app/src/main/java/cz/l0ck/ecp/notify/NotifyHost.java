package cz.l0ck.ecp.notify;

import android.Manifest;
import android.app.Application;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.Build;

import cz.l0ck.ecp.R;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * "New message" notifications. Deliberately empty of content: no sender, no text, the same on
 * the lock screen — a glance at the phone must not tell anyone who writes or what.
 */
public final class NotifyHost {

	public static final String METHODS = "cz.l0ck.ecp/notify";
	private static final String CHANNEL = "ecp_messages";
	private static final int ID = 2;
	private static final String CALLS = "ecp_calls";
	private static final int CALL_ID = 3;
	public static final String EXTRA_OPEN = "cz.l0ck.ecp.OPEN";

	private final Application app;

	public NotifyHost(Application app) {
		this.app = app;
	}

	public void attach(BinaryMessenger messenger) {
		new MethodChannel(messenger, METHODS).setMethodCallHandler((call, result) -> {
			switch (call.method) {
				case "message":
					show(call.<Integer>argument("count"), call.argument("open"));
					result.success(null);
					break;
				case "clear":
					app.getSystemService(NotificationManager.class).cancel(ID);
					result.success(null);
					break;
				case "call":
					ring(call.argument("text"), call.argument("open"));
					result.success(null);
					break;
				case "callEnd":
					app.getSystemService(NotificationManager.class).cancel(CALL_ID);
					result.success(null);
					break;
				default:
					result.notImplemented();
			}
		});
	}

	/** An incoming call: rings (repeating) until answered, declined or given up. No caller
	 *  on screen either; the call screen after the PIN shows who it is. */
	private void ring(String text, String open) {
		if (Build.VERSION.SDK_INT >= 33
				&& app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
				!= PackageManager.PERMISSION_GRANTED) return;
		NotificationManager nm = app.getSystemService(NotificationManager.class);
		NotificationChannel ch = new NotificationChannel(CALLS, "Hovory", NotificationManager.IMPORTANCE_HIGH);
		ch.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), new AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
				.setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
				.build());
		ch.enableVibration(true);
		nm.createNotificationChannel(ch);
		Intent intent = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
		if (intent != null && open != null) intent.putExtra(EXTRA_OPEN, open);
		PendingIntent pi = PendingIntent.getActivity(app, 1, intent,
				PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
		Notification n = new Notification.Builder(app, CALLS)
				.setSmallIcon(R.mipmap.ic_launcher_monochrome)
				.setContentTitle(text)
				.setContentIntent(pi)
				.setCategory(Notification.CATEGORY_CALL)
				.setVisibility(Notification.VISIBILITY_PUBLIC)
				.setOngoing(true)
				.build();
		n.flags |= Notification.FLAG_INSISTENT; // the ringtone repeats until cancelled
		nm.notify(CALL_ID, n);
	}

	/** [open] = conversation to show after unlock ("c:<contact id>" / "t:<team id>"); it
	 *  travels in the intent only, never on screen. */
	private void show(int count, String open) {
		if (Build.VERSION.SDK_INT >= 33
				&& app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
				!= PackageManager.PERMISSION_GRANTED) return;
		NotificationManager nm = app.getSystemService(NotificationManager.class);
		nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Zprávy",
				NotificationManager.IMPORTANCE_DEFAULT));
		String text = count > 1 ? "Nové zprávy (" + count + ")" : "Nová zpráva";
		Intent intent = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
		if (intent != null && open != null) intent.putExtra(EXTRA_OPEN, open);
		PendingIntent pi = PendingIntent.getActivity(app, 0, intent,
				PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
		Notification pub = new Notification.Builder(app, CHANNEL)
				.setSmallIcon(R.mipmap.ic_launcher_monochrome)
				.setContentTitle(text)
				.build();
		Notification n = new Notification.Builder(app, CHANNEL)
				.setSmallIcon(R.mipmap.ic_launcher_monochrome)
				.setContentTitle(text)
				.setContentIntent(pi)
				.setAutoCancel(true)
				.setNumber(count)
				.setVisibility(Notification.VISIBILITY_PRIVATE)
				.setPublicVersion(pub)
				.build();
		nm.notify(ID, n);
	}
}
