package cz.l0ck.ecp.bramble;

import android.app.Application;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.briarproject.bramble.BrambleAndroidEagerSingletons;
import org.briarproject.bramble.BrambleAppComponent;
import org.briarproject.bramble.BrambleCoreEagerSingletons;

import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import static org.briarproject.bramble.util.IoUtils.deleteFileOrDir;

/**
 * The process's single Bramble node and its Flutter channels. Bramble's lifecycle cannot be
 * restarted in-process, so a process runs at most one profile: after a duress switch the
 * stopped node stays down and the decoy goes without Bramble until the next process start.
 */
public final class BrambleHost implements BrambleNode.Listener {

	public static final String METHODS = "cz.l0ck.ecp/bramble";
	public static final String EVENTS = "cz.l0ck.ecp/bramble/events";

	/** Profile directory names are hex hashes (see SecurityService); nothing else is accepted. */
	private static final Pattern PROFILE = Pattern.compile("[0-9a-f]{16,64}");

	private static BrambleHost instance;

	public static synchronized BrambleHost get(Application app) {
		if (instance == null) instance = new BrambleHost(app);
		return instance;
	}

	private final Application app;
	private final ExecutorService worker = Executors.newSingleThreadExecutor();
	private final Handler main = new Handler(Looper.getMainLooper());
	private volatile EcpBrambleComponent component;
	private BrambleNode node; // worker thread only
	private String profile, link;
	private boolean stopped; // worker thread only; a stopped node cannot start again
	private EventChannel.EventSink sink; // main thread only
	private volatile String current = ""; // last method name, for the failure log

	private BrambleHost(Application app) {
		this.app = app;
	}

	/** For Bramble's AlarmReceiver, which may fire before any profile is running. */
	public BrambleAppComponent appComponent() {
		EcpBrambleComponent c = component;
		return c != null ? c : () -> intent -> {};
	}

	public void attach(BinaryMessenger messenger) {
		new MethodChannel(messenger, METHODS).setMethodCallHandler(this::onCall);
		new EventChannel(messenger, EVENTS).setStreamHandler(new EventChannel.StreamHandler() {
			@Override
			public void onListen(Object arguments, EventChannel.EventSink events) {
				sink = events;
			}

			@Override
			public void onCancel(Object arguments) {
				sink = null;
			}
		});
	}

	private void onCall(MethodCall call, MethodChannel.Result result) {
		current = call.method;
		switch (call.method) {
			case "start":
				run(result, () -> start(call.argument("profile"), call.argument("nickname"),
						call.argument("password")));
				break;
			case "link":
				run(result, () -> running().handshakeLink());
				break;
			case "contacts":
				run(result, () -> running().contacts());
				break;
			case "pending":
				run(result, () -> running().pendingContacts());
				break;
			case "transports":
				run(result, () -> running().activeTransports());
				break;
			case "addContact":
				run(result, () -> running().addContact(call.argument("link"), call.argument("alias")));
				break;
			case "removeContact":
				run(result, () -> {
					running().removeContact(call.<Integer>argument("id"));
					return null;
				});
				break;
			case "send":
				run(result, () -> {
					running().send(call.<Integer>argument("contact"), call.argument("data"));
					return null;
				});
				break;
			case "restartTransport": {
				String name = call.argument("name");
				new Thread(() -> {
					try {
						String r = running().restartTransport(name);
						main.post(() -> result.success(r));
					} catch (Exception e) {
						main.post(() -> result.error("BRAMBLE", e.toString(), null));
					}
				}, "ecp-restart-" + name).start();
				break;
			}
			case "refreshBluetooth":
				new Thread(() -> {
					try {
						String r = running().refreshBluetooth();
						Log.i("ecp", "bluetooth plugin after refresh: " + r);
						main.post(() -> result.success(r));
					} catch (Exception e) {
						main.post(() -> result.error("BRAMBLE", e.toString(), null));
					}
				}, "ecp-bt-refresh").start();
				break;
			case "connectBluetooth": {
				// Discovery takes up to ~30 s: own thread, not the worker the other calls queue on
				Integer id = call.argument("id");
				new Thread(() -> {
					try {
						String r = running().connectBluetooth(id);
						main.post(() -> result.success(r));
					} catch (Exception e) {
						Log.w("ecp", "bluetooth connect failed", e);
						main.post(() -> result.error("BRAMBLE", e.toString(), null));
					}
				}, "ecp-bt-connect").start();
				break;
			}
			case "stop":
				run(result, () -> {
					// The surviving profile keeps running: a decoy unlocked with the duress
					// code repeats the duress clean-up every time (a destroyed slot is noise)
					String keep = call.argument("keep");
					if (node != null && !profile.equals(keep)) {
						node.stop();
						node = null;
						stopped = true; // only a node that ran makes the process unusable
					}
					app.stopService(new Intent(app, EcpService.class));
					return null;
				});
				break;
			case "deleteProfiles":
				run(result, () -> deleteProfilesExcept(call.argument("keep")));
				break;
			case "deleteProfile":
				run(result, () -> deleteProfile(call.argument("profile")));
				break;
			default:
				result.notImplemented();
		}
	}

	private String start(String p, String nickname, String password) throws Exception {
		if (p == null || !PROFILE.matcher(p).matches()) throw new IllegalArgumentException("profile");
		if (node != null) {
			if (p.equals(profile)) return link;
			throw new IllegalStateException("OTHER_PROFILE");
		}
		if (stopped) throw new IllegalStateException("RESTART_NEEDED");
		// Bramble logs at INFO, including profile directory listings; keep logcat quiet
		Logger.getLogger("").setLevel(Level.WARNING);
		File dir = new File(new File(app.getFilesDir(), "bramble"), p);
		if (!dir.isDirectory() && !dir.mkdirs()) throw new IllegalStateException("profile dir");
		EcpBrambleComponent c = DaggerEcpBrambleComponent.builder()
				.ecpAndroidModule(new EcpAndroidModule(app, dir)).build();
		BrambleCoreEagerSingletons.Helper.injectEagerSingletons(c);
		BrambleAndroidEagerSingletons.Helper.injectEagerSingletons(c);
		c.inject(new EcpClientModule.EagerSingletons());
		component = c;
		BrambleNode n = new BrambleNode(c, this);
		link = n.start(nickname, password);
		node = n;
		profile = p;
		startService();
		return link;
	}

	private BrambleNode running() {
		if (node == null || !node.isRunning()) {
			Log.w("ecp", "not running: node=" + node + " stopped=" + stopped);
			throw new IllegalStateException("NOT_RUNNING");
		}
		return node;
	}

	/** Duress and wipe: removes every other profile's Bramble data (Tor keys, contacts, DB). */
	private int deleteProfilesExcept(String keep) {
		int n = 0;
		File[] dirs = new File(app.getFilesDir(), "bramble").listFiles();
		if (dirs != null) {
			for (File d : dirs) {
				if (d.getName().equals(keep)) continue;
				deleteFileOrDir(d);
				n++;
			}
		}
		File[] prefs = new File(app.getApplicationInfo().dataDir, "shared_prefs").listFiles();
		if (prefs != null) {
			for (File f : prefs) {
				String name = f.getName();
				if (name.startsWith("bramble_") && !name.equals("bramble_" + keep + ".xml")) {
					deleteFileOrDir(f);
				}
			}
		}
		return n;
	}

	/** The PIN screen's "compromised": removes one profile's Bramble data, no other. */
	private boolean deleteProfile(String p) {
		if (p == null || !PROFILE.matcher(p).matches()) throw new IllegalArgumentException("profile");
		deleteFileOrDir(new File(new File(app.getFilesDir(), "bramble"), p));
		deleteFileOrDir(new File(new File(app.getApplicationInfo().dataDir, "shared_prefs"), "bramble_" + p + ".xml"));
		return true;
	}

	private void startService() {
		Intent i = new Intent(app, EcpService.class);
		if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(i);
		else app.startService(i);
	}

	@Override
	public void onEvent(String type, Map<String, Object> fields) {
		Map<String, Object> m = new HashMap<>(fields);
		m.put("type", type);
		main.post(() -> {
			if (sink != null) sink.success(m);
		});
	}

	private <T> void run(MethodChannel.Result result, Callable<T> task) {
		String method = current;
		worker.execute(() -> {
			try {
				T value = task.call();
				main.post(() -> result.success(value));
			} catch (Exception e) {
				Log.w("ecp", "bramble call failed: " + method, e);
				String code = e instanceof IllegalStateException ? e.getMessage() : "BRAMBLE";
				main.post(() -> result.error(code, e.toString(), null));
			}
		});
	}
}
