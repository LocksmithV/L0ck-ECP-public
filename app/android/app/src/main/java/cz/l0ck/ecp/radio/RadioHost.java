package cz.l0ck.ecp.radio;

import android.annotation.SuppressLint;
import android.app.Application;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * BLE link to a MeshCore companion radio (Nordic UART service). Byte frames only — the
 * companion protocol itself lives in Dart (packages/ecp_meshcore). One write or notification
 * is one frame. Reconnects by itself while a radio is selected, so a node walking out of and
 * back into range rejoins without the user.
 */
@SuppressLint("MissingPermission") // BLUETOOTH_CONNECT is requested by the Dart side first
public final class RadioHost {

	public static final String METHODS = "cz.l0ck.ecp/radio";
	public static final String EVENTS = "cz.l0ck.ecp/radio/events";

	private static final UUID SERVICE = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
	private static final UUID RX = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
	private static final UUID TX = UUID.fromString("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
	private static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

	private static RadioHost instance;

	public static synchronized RadioHost get(Application app) {
		if (instance == null) instance = new RadioHost(app);
		return instance;
	}

	private final Application app;
	private final Handler main = new Handler(Looper.getMainLooper());
	// All GATT state below is touched on the main thread only (callbacks are posted there)
	private final ArrayDeque<byte[]> writes = new ArrayDeque<>();
	private EventChannel.EventSink sink;
	private String address;
	private BluetoothGatt gatt;
	private BluetoothGattCharacteristic rx;
	private boolean ready, writing;

	private RadioHost(Application app) {
		this.app = app;
	}

	public void attach(BinaryMessenger messenger) {
		new MethodChannel(messenger, METHODS).setMethodCallHandler(this::onCall);
		new EventChannel(messenger, EVENTS).setStreamHandler(new EventChannel.StreamHandler() {
			@Override
			public void onListen(Object arguments, EventChannel.EventSink events) {
				sink = events;
				emitState();
			}

			@Override
			public void onCancel(Object arguments) {
				sink = null;
			}
		});
	}

	private void onCall(MethodCall call, MethodChannel.Result result) {
		try {
			switch (call.method) {
				case "bonded":
					result.success(bonded());
					break;
				case "connect":
					connect(call.argument("address"));
					result.success(null);
					break;
				case "disconnect":
					disconnect();
					result.success(null);
					break;
				case "write":
					if (!ready) {
						result.error("NOT_CONNECTED", "radio not connected", null);
						return;
					}
					writes.add(call.argument("data"));
					pump();
					result.success(null);
					break;
				default:
					result.notImplemented();
			}
		} catch (Exception e) {
			Log.w("ecp", "radio call failed: " + call.method, e);
			result.error("RADIO", e.toString(), null);
		}
	}

	private BluetoothAdapter adapter() {
		BluetoothManager m = app.getSystemService(BluetoothManager.class);
		return m == null ? null : m.getAdapter();
	}

	/** Paired devices; the radio is paired once in Android's Bluetooth settings (BLE PIN). */
	private List<Map<String, Object>> bonded() {
		List<Map<String, Object>> out = new ArrayList<>();
		BluetoothAdapter a = adapter();
		if (a == null) return out;
		for (BluetoothDevice d : a.getBondedDevices()) {
			if (d.getType() == BluetoothDevice.DEVICE_TYPE_CLASSIC) continue;
			Map<String, Object> m = new HashMap<>();
			m.put("address", d.getAddress());
			m.put("name", d.getName() == null ? "" : d.getName());
			out.add(m);
		}
		return out;
	}

	private void connect(String addr) {
		disconnect();
		BluetoothAdapter a = adapter();
		if (a == null || addr == null) throw new IllegalStateException("no Bluetooth");
		address = addr;
		open(false);
	}

	private void open(boolean auto) {
		BluetoothDevice d = adapter().getRemoteDevice(address);
		// autoConnect: the stack waits for the radio to come back in range, without timeout
		gatt = d.connectGatt(app, auto, callback, BluetoothDevice.TRANSPORT_LE);
	}

	private void disconnect() {
		address = null;
		close();
	}

	private void close() {
		ready = false;
		writing = false;
		writes.clear();
		rx = null;
		if (gatt != null) {
			gatt.disconnect();
			gatt.close();
			gatt = null;
		}
		emitState();
	}

	private void pump() {
		if (!ready || writing || writes.isEmpty() || gatt == null) return;
		byte[] f = writes.poll();
		writing = true;
		boolean ok;
		if (Build.VERSION.SDK_INT >= 33) {
			ok = gatt.writeCharacteristic(rx, f, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
					== BluetoothGatt.GATT_SUCCESS;
		} else {
			rx.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
			rx.setValue(f);
			ok = gatt.writeCharacteristic(rx);
		}
		if (!ok) {
			writing = false;
			Log.w("ecp", "radio write rejected");
		}
	}

	private final BluetoothGattCallback callback = new BluetoothGattCallback() {
		@Override
		public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
			main.post(() -> {
				if (g != gatt) return;
				if (state == BluetoothProfile.STATE_CONNECTED) {
					g.requestMtu(512);
				} else if (state == BluetoothProfile.STATE_DISCONNECTED) {
					String keep = address;
					close();
					if (keep != null) {
						address = keep;
						open(true); // walked out of range: rejoin when it is back
					}
				}
			});
		}

		@Override
		public void onMtuChanged(BluetoothGatt g, int mtu, int status) {
			main.post(() -> {
				if (g == gatt) g.discoverServices();
			});
		}

		@Override
		public void onServicesDiscovered(BluetoothGatt g, int status) {
			main.post(() -> {
				if (g != gatt) return;
				BluetoothGattService s = g.getService(SERVICE);
				BluetoothGattCharacteristic tx = s == null ? null : s.getCharacteristic(TX);
				rx = s == null ? null : s.getCharacteristic(RX);
				if (tx == null || rx == null) {
					Log.w("ecp", "not a MeshCore companion (no UART service)");
					g.disconnect();
					return;
				}
				g.setCharacteristicNotification(tx, true);
				BluetoothGattDescriptor d = tx.getDescriptor(CCCD);
				byte[] on = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;
				if (Build.VERSION.SDK_INT >= 33) {
					g.writeDescriptor(d, on);
				} else {
					d.setValue(on);
					g.writeDescriptor(d);
				}
			});
		}

		@Override
		public void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor d, int status) {
			main.post(() -> {
				if (g != gatt) return;
				ready = status == BluetoothGatt.GATT_SUCCESS;
				emitState();
				pump();
			});
		}

		@Override
		public void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
			main.post(() -> {
				writing = false;
				pump();
			});
		}

		@Override
		public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c,
				byte[] value) {
			byte[] f = value.clone();
			main.post(() -> emit("frame", f));
		}

		@Override
		@SuppressWarnings("deprecation")
		public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {
			if (Build.VERSION.SDK_INT >= 33) return; // the overload above gets it
			byte[] f = c.getValue().clone();
			main.post(() -> emit("frame", f));
		}
	};

	private void emitState() {
		Map<String, Object> m = new HashMap<>();
		m.put("type", "state");
		m.put("connected", ready);
		m.put("address", address);
		if (sink != null) sink.success(m);
	}

	private void emit(String type, byte[] data) {
		Map<String, Object> m = new HashMap<>();
		m.put("type", type);
		m.put("data", data);
		if (sink != null) sink.success(m);
	}
}
