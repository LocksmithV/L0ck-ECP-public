package cz.l0ck.ecp.bramble;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

import cz.l0ck.ecp.R;

/**
 * Keeps the process — and with it Bramble, the Flutter engine and the PACE router — alive
 * while the app is locked or in the background. The notification is deliberately bland;
 * without the notification permission Android hides it but the service still runs.
 */
public class EcpService extends Service {

	private static final String CHANNEL = "ecp_background";
	private static final int ID = 1;

	@Override
	public int onStartCommand(Intent intent, int flags, int startId) {
		NotificationManager nm = getSystemService(NotificationManager.class);
		Notification.Builder b;
		if (Build.VERSION.SDK_INT >= 26) {
			nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Služba",
					NotificationManager.IMPORTANCE_MIN));
			b = new Notification.Builder(this, CHANNEL);
		} else {
			b = new Notification.Builder(this);
		}
		Intent open = getPackageManager().getLaunchIntentForPackage(getPackageName());
		PendingIntent pi = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE);
		Notification n = b.setSmallIcon(R.mipmap.ic_launcher_monochrome)
				.setContentTitle("Aktivní")
				.setContentIntent(pi)
				.setOngoing(true)
				.setVisibility(Notification.VISIBILITY_SECRET)
				.build();
		if (Build.VERSION.SDK_INT >= 34) {
			startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING);
		} else {
			startForeground(ID, n);
		}
		return START_NOT_STICKY;
	}

	@Override
	public IBinder onBind(Intent intent) {
		return null;
	}
}
