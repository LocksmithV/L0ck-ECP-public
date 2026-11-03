package cz.l0ck.ecp.net;

import android.app.Application;
import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Handler;
import android.os.Looper;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;

/**
 * Whether the phone has a network with internet at all (mobile data, Wi-Fi). The PACE router
 * skips SimpleX and Tor at once when it has none, instead of waiting for their ACK timeouts.
 *
 * Deliberately the INTERNET capability, not VALIDATED: validation probes Google's servers, and
 * where those are blocked a working internet would look like none and switch SimpleX off.
 */
public final class NetHost {

	public static final String EVENTS = "cz.l0ck.ecp/net";

	private final ConnectivityManager cm;
	private final Handler main = new Handler(Looper.getMainLooper());
	private EventChannel.EventSink sink;
	private ConnectivityManager.NetworkCallback callback;

	public NetHost(Application app) {
		cm = (ConnectivityManager) app.getSystemService(Context.CONNECTIVITY_SERVICE);
	}

	public void attach(BinaryMessenger messenger) {
		new EventChannel(messenger, EVENTS).setStreamHandler(new EventChannel.StreamHandler() {
			@Override
			public void onListen(Object arguments, EventChannel.EventSink events) {
				sink = events;
				sink.success(online(cm.getNetworkCapabilities(cm.getActiveNetwork())));
				callback = new ConnectivityManager.NetworkCallback() {
					@Override
					public void onCapabilitiesChanged(Network n, NetworkCapabilities c) {
						post(online(c));
					}

					@Override
					public void onLost(Network n) {
						// The default network is gone. Asking for the active one here can still
						// return the lost one (with INTERNET), and nothing would correct it; a
						// network that takes over reports itself through onCapabilitiesChanged.
						post(false);
					}
				};
				cm.registerDefaultNetworkCallback(callback);
			}

			@Override
			public void onCancel(Object arguments) {
				if (callback != null) cm.unregisterNetworkCallback(callback);
				callback = null;
				sink = null;
			}
		});
	}

	private static boolean online(NetworkCapabilities c) {
		return c != null && c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
	}

	private void post(boolean online) {
		main.post(() -> {
			if (sink != null) sink.success(online);
		});
	}
}
