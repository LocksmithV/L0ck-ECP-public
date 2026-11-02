package cz.l0ck.ecp.location;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Application;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * One current position for a report, straight from Android's LocationManager — GPS first,
 * then the network provider, then a fresh last-known fix. No Google Play services, no
 * tracking: the receiver is only asked when the user sends a report.
 */
@SuppressLint("MissingPermission") // checked in current()
public final class LocationHost {

	public static final String METHODS = "cz.l0ck.ecp/location";
	private static final long FRESH_MS = 5 * 60_000;

	private final Application app;
	private final Handler main = new Handler(Looper.getMainLooper());

	public LocationHost(Application app) {
		this.app = app;
	}

	public void attach(BinaryMessenger messenger) {
		new MethodChannel(messenger, METHODS).setMethodCallHandler((call, result) -> {
			if (!"current".equals(call.method)) {
				result.notImplemented();
				return;
			}
			Integer t = call.argument("timeoutMs");
			current(t == null ? 30_000 : t, result);
		});
	}

	private void current(int timeoutMs, MethodChannel.Result result) {
		if (app.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
				!= PackageManager.PERMISSION_GRANTED
				&& app.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
				!= PackageManager.PERMISSION_GRANTED) {
			result.error("NO_PERMISSION", "location permission", null);
			return;
		}
		LocationManager lm = app.getSystemService(LocationManager.class);
		if (lm == null || (Build.VERSION.SDK_INT >= 28 && !lm.isLocationEnabled())) {
			result.error("OFF", "location is switched off", null);
			return;
		}
		AtomicBoolean done = new AtomicBoolean();
		Runnable fallback = () -> {
			if (done.getAndSet(true)) return;
			Location last = freshest(lm);
			if (last != null) result.success(toMap(last));
			else result.error("TIMEOUT", "no fix", null);
		};
		main.postDelayed(fallback, timeoutMs);
		for (String p : new String[]{LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER}) {
			if (!lm.isProviderEnabled(p)) continue;
			if (Build.VERSION.SDK_INT >= 30) {
				lm.getCurrentLocation(p, new CancellationSignal(), app.getMainExecutor(), l -> {
					if (l != null && !done.getAndSet(true)) result.success(toMap(l));
				});
			} else {
				requestSingle(lm, p, done, result);
			}
		}
	}

	@SuppressWarnings("deprecation")
	private void requestSingle(LocationManager lm, String p, AtomicBoolean done, MethodChannel.Result result) {
		lm.requestSingleUpdate(p, new LocationListener() {
			@Override
			public void onLocationChanged(Location l) {
				if (!done.getAndSet(true)) result.success(toMap(l));
			}
		}, Looper.getMainLooper());
	}

	private Location freshest(LocationManager lm) {
		Location best = null;
		for (String p : lm.getProviders(true)) {
			Location l = lm.getLastKnownLocation(p);
			if (l == null || System.currentTimeMillis() - l.getTime() > FRESH_MS) continue;
			if (best == null || l.getTime() > best.getTime()) best = l;
		}
		return best;
	}

	private static Map<String, Object> toMap(Location l) {
		Map<String, Object> m = new HashMap<>();
		m.put("lat", l.getLatitude());
		m.put("lon", l.getLongitude());
		if (l.hasAltitude()) m.put("alt", l.getAltitude());
		if (l.hasAccuracy()) m.put("acc", (double) l.getAccuracy());
		if (l.hasBearing()) m.put("course", (double) l.getBearing());
		if (l.hasSpeed()) m.put("speed", (double) l.getSpeed());
		m.put("time", l.getTime());
		m.put("provider", l.getProvider());
		return m;
	}
}
