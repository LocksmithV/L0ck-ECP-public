package cz.l0ck.ecp.bramble;

import org.briarproject.bramble.api.FormatException;
import org.briarproject.bramble.api.Pair;
import org.briarproject.bramble.api.account.AccountManager;
import org.briarproject.bramble.api.connection.ConnectionManager;
import org.briarproject.bramble.api.connection.ConnectionRegistry;
import org.briarproject.bramble.api.contact.Contact;
import org.briarproject.bramble.api.contact.ContactId;
import org.briarproject.bramble.api.contact.ContactManager;
import org.briarproject.bramble.api.contact.PendingContact;
import org.briarproject.bramble.api.contact.PendingContactState;
import org.briarproject.bramble.api.contact.event.ContactAddedEvent;
import org.briarproject.bramble.api.contact.event.ContactRemovedEvent;
import org.briarproject.bramble.api.contact.event.PendingContactStateChangedEvent;
import org.briarproject.bramble.api.crypto.PublicKey;
import org.briarproject.bramble.api.db.ContactExistsException;
import org.briarproject.bramble.api.db.DbException;
import org.briarproject.bramble.api.db.PendingContactExistsException;
import org.briarproject.bramble.api.event.Event;
import org.briarproject.bramble.api.event.EventBus;
import org.briarproject.bramble.api.event.EventListener;
import org.briarproject.bramble.api.lifecycle.LifecycleManager;
import org.briarproject.bramble.api.plugin.BluetoothConstants;
import org.briarproject.bramble.api.plugin.LanTcpConstants;
import org.briarproject.bramble.api.plugin.Plugin;
import org.briarproject.bramble.api.plugin.PluginManager;
import org.briarproject.bramble.api.plugin.TorConstants;
import org.briarproject.bramble.api.plugin.TransportId;
import org.briarproject.bramble.api.plugin.duplex.DuplexTransportConnection;
import org.briarproject.bramble.api.plugin.event.ConnectionClosedEvent;
import org.briarproject.bramble.api.plugin.event.ConnectionOpenedEvent;
import org.briarproject.bramble.api.plugin.event.TransportActiveEvent;
import org.briarproject.bramble.api.plugin.event.TransportInactiveEvent;
import org.briarproject.bramble.api.properties.TransportPropertyManager;
import org.briarproject.bramble.api.settings.Settings;
import org.briarproject.bramble.api.settings.SettingsManager;
import org.briarproject.bramble.plugin.bluetooth.BluetoothPlugin;
import org.briarproject.bramble.util.Base32;

import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import static org.briarproject.bramble.api.contact.HandshakeLinkConstants.FORMAT_VERSION;
import static org.briarproject.bramble.api.plugin.Plugin.PREF_PLUGIN_ENABLE;

/**
 * What ECP needs from a running Bramble node, in plain types (maps, lists, byte arrays) so
 * the Android MethodChannel and the laptop peer's line protocol can pass it on unchanged.
 * One node per process and per ECP profile: Bramble's lifecycle cannot restart in-process.
 */
public class BrambleNode implements EventListener {

	/** The parts of a Bramble Dagger component the node uses. */
	public interface Graph {
		AccountManager accountManager();

		LifecycleManager lifecycleManager();

		ContactManager contactManager();

		SettingsManager settingsManager();

		EventBus eventBus();

		ConnectionRegistry connectionRegistry();

		EcpClient ecpClient();

		PluginManager pluginManager();

		TransportPropertyManager transportPropertyManager();

		ConnectionManager connectionManager();
	}

	/** Receives node events as (type, fields); called on Bramble's event thread. */
	public interface Listener {
		void onEvent(String type, Map<String, Object> fields);
	}

	private static final TransportId[] TRANSPORTS =
			{TorConstants.ID, LanTcpConstants.ID, BluetoothConstants.ID};

	private final Graph g;
	private final Listener listener;
	private final Set<String> active = new TreeSet<>();
	private volatile boolean running;

	public BrambleNode(Graph graph, Listener listener) {
		this.g = graph;
		this.listener = listener;
	}

	/**
	 * Creates the account on first use, otherwise signs in, then starts all services. Blocks
	 * until Bramble runs (Tor keeps bootstrapping in the background). Returns the handshake link.
	 */
	public String start(String nickname, String password) throws Exception {
		g.eventBus().addListener(this);
		AccountManager accounts = g.accountManager();
		if (accounts.accountExists()) accounts.signIn(password);
		else if (!accounts.createAccount(nickname, password))
			throw new IllegalStateException("account not created");
		LifecycleManager lifecycle = g.lifecycleManager();
		LifecycleManager.StartResult result = lifecycle.startServices(accounts.getDatabaseKey());
		if (result != LifecycleManager.StartResult.SUCCESS)
			throw new IllegalStateException("bramble start: " + result);
		lifecycle.waitForStartup();
		// Bramble ships with Bluetooth off; the squad net needs it on
		Settings bt = new Settings();
		bt.putBoolean(PREF_PLUGIN_ENABLE, true);
		g.settingsManager().mergeSettings(bt, BluetoothConstants.ID.getString());
		running = true;
		emit("state", map("running", true));
		return g.contactManager().getHandshakeLink();
	}

	public boolean isRunning() {
		return running;
	}

	public void stop() throws InterruptedException {
		if (!running) return;
		running = false;
		g.eventBus().removeListener(this);
		g.lifecycleManager().stopServices();
		g.lifecycleManager().waitForShutdown();
	}

	public String handshakeLink() throws DbException {
		return g.contactManager().getHandshakeLink();
	}

	/** Returns "pending", "exists", or "invalid"; the contact then appears via contactAdded. */
	public String addContact(String link, String alias) throws DbException {
		try {
			g.contactManager().addPendingContact(link, alias);
			return "pending";
		} catch (ContactExistsException | PendingContactExistsException e) {
			return "exists";
		} catch (FormatException | GeneralSecurityException e) {
			return "invalid"; // also an unsupported link version
		}
	}

	public void removeContact(int contactId) throws DbException {
		g.contactManager().removeContact(new ContactId(contactId));
	}

	/** Contacts with the handshake link they were added by (how ECP matches its cards). */
	public List<Map<String, Object>> contacts() throws DbException {
		List<Map<String, Object>> out = new ArrayList<>();
		for (Contact c : g.contactManager().getContacts()) {
			Map<String, Object> m = map("id", c.getId().getInt());
			PublicKey k = c.getHandshakePublicKey();
			if (k != null) m.put("link", linkFor(k));
			m.put("links", linksTo(c.getId()));
			out.add(m);
		}
		return out;
	}

	public List<Map<String, Object>> pendingContacts() throws DbException {
		List<Map<String, Object>> out = new ArrayList<>();
		for (Pair<PendingContact, PendingContactState> p : g.contactManager().getPendingContacts()) {
			Map<String, Object> m = map("alias", p.getFirst().getAlias());
			m.put("state", p.getSecond().name());
			out.add(m);
		}
		return out;
	}

	public List<String> activeTransports() {
		synchronized (active) {
			return new ArrayList<>(active);
		}
	}

	/**
	 * First Bluetooth link to a contact. Android hides a phone's own Bluetooth address, so two
	 * new contacts cannot reach each other over Bluetooth until one link has run and both
	 * learned the other's address: both phones make themselves visible, then look for the
	 * contact's service UUID (as Briar's "Connect via Bluetooth"). Blocks during discovery.
	 * Returns connected / no-uuid / not-found / unavailable.
	 */
	public String connectBluetooth(int contactId) throws DbException {
		ContactId c = new ContactId(contactId);
		if (g.connectionRegistry().isConnected(c, BluetoothConstants.ID)) return "connected";
		Plugin p = g.pluginManager().getPlugin(BluetoothConstants.ID);
		if (!(p instanceof BluetoothPlugin)) return "unavailable";
		if (p.getState() != Plugin.State.ACTIVE && !restart(p)) {
			return "unavailable:" + p.getState() + "/" + p.getReasonsDisabled();
		}
		BluetoothPlugin bt = (BluetoothPlugin) p;
		String uuid = g.transportPropertyManager()
				.getRemoteProperties(c, BluetoothConstants.ID).get(BluetoothConstants.PROP_UUID);
		if (uuid == null || uuid.isEmpty()) return "no-uuid";
		bt.disablePolling();
		try {
			DuplexTransportConnection conn = bt.discoverAndConnectForSetup(uuid);
			if (conn == null) return "not-found";
			g.connectionManager().manageOutgoingConnection(c, BluetoothConstants.ID, conn);
			return "connected";
		} finally {
			bt.enablePolling();
		}
	}

	/**
	 * A plugin that started before the user granted "Nearby devices" (fresh install) stays
	 * INACTIVE for good; switching it off and on makes it look at the adapter again.
	 */
	private boolean restart(Plugin p) {
		g.pluginManager().setPluginEnabled(p.getId(), false);
		g.pluginManager().setPluginEnabled(p.getId(), true);
		for (int i = 0; i < 20 && p.getState() != Plugin.State.ACTIVE; i++) {
			try {
				Thread.sleep(500);
			} catch (InterruptedException e) {
				Thread.currentThread().interrupt();
				return false;
			}
		}
		return p.getState() == Plugin.State.ACTIVE;
	}

	/**
	 * Settings, "Obnovit spojení": switches one transport (tor / lan / bluetooth) off and on,
	 * e.g. after mobile data or Wi-Fi came back. Returns its state afterwards.
	 */
	public String restartTransport(String name) {
		for (TransportId t : TRANSPORTS) {
			if (!shortName(t).equals(name)) continue;
			Plugin p = g.pluginManager().getPlugin(t);
			if (p == null) return "NONE";
			restart(p);
			return p.getState().name();
		}
		return "NONE";
	}

	/** After "Nearby devices" was granted: wakes a Bluetooth plugin that started without it. */
	public String refreshBluetooth() {
		Plugin p = g.pluginManager().getPlugin(BluetoothConstants.ID);
		if (p == null) return "NONE";
		if (p.getState() != Plugin.State.ACTIVE) restart(p);
		return p.getState().name();
	}

	/** Bluetooth plugin state, for the UI: ACTIVE / INACTIVE / DISABLED / ENABLING … */
	public String bluetoothState() {
		Plugin p = g.pluginManager().getPlugin(BluetoothConstants.ID);
		return p == null ? "NONE" : p.getState().name();
	}

	public void send(int contactId, byte[] envelope) throws DbException {
		g.ecpClient().send(new ContactId(contactId), envelope);
	}

	// --- events ---

	@Override
	public void eventOccurred(Event e) {
		if (e instanceof EcpEnvelopeReceivedEvent) {
			EcpEnvelopeReceivedEvent r = (EcpEnvelopeReceivedEvent) e;
			Map<String, Object> m = map("contact", r.getContactId().getInt());
			m.put("data", r.getEnvelope());
			m.put("links", linksTo(r.getContactId()));
			emit("received", m);
		} else if (e instanceof TransportActiveEvent) {
			transport(((TransportActiveEvent) e).getTransportId(), true);
		} else if (e instanceof TransportInactiveEvent) {
			transport(((TransportInactiveEvent) e).getTransportId(), false);
		} else if (e instanceof ConnectionOpenedEvent) {
			ConnectionOpenedEvent o = (ConnectionOpenedEvent) e;
			connection(o.getContactId(), o.getTransportId(), true);
		} else if (e instanceof ConnectionClosedEvent) {
			ConnectionClosedEvent c = (ConnectionClosedEvent) e;
			connection(c.getContactId(), c.getTransportId(), false);
		} else if (e instanceof ContactAddedEvent) {
			emit("contactAdded", map("id", ((ContactAddedEvent) e).getContactId().getInt()));
		} else if (e instanceof ContactRemovedEvent) {
			emit("contactRemoved", map("id", ((ContactRemovedEvent) e).getContactId().getInt()));
		} else if (e instanceof PendingContactStateChangedEvent) {
			emit("pending", map("state",
					((PendingContactStateChangedEvent) e).getPendingContactState().name()));
		}
	}

	private void transport(TransportId t, boolean up) {
		String s = shortName(t);
		synchronized (active) {
			if (up) active.add(s);
			else active.remove(s);
		}
		Map<String, Object> m = map("transport", s);
		m.put("active", up);
		emit("transport", m);
	}

	private void connection(ContactId c, TransportId t, boolean open) {
		Map<String, Object> m = map("contact", c.getInt());
		m.put("transport", shortName(t));
		m.put("open", open);
		emit("connection", m);
	}

	private List<String> linksTo(ContactId c) {
		List<String> out = new ArrayList<>();
		for (TransportId t : TRANSPORTS) {
			if (g.connectionRegistry().isConnected(c, t)) out.add(shortName(t));
		}
		return out;
	}

	private void emit(String type, Map<String, Object> fields) {
		try {
			listener.onEvent(type, fields);
		} catch (RuntimeException ignored) {
			// A broken listener must not take Bramble's event thread down
		}
	}

	/** tor / lan / bluetooth — the last part of Bramble's transport id. */
	static String shortName(TransportId t) {
		String s = t.getString();
		return s.substring(s.lastIndexOf('.') + 1);
	}

	/** Same encoding as Bramble's own handshake links. */
	static String linkFor(PublicKey k) {
		byte[] key = k.getEncoded();
		byte[] raw = new byte[key.length + 1];
		raw[0] = FORMAT_VERSION;
		System.arraycopy(key, 0, raw, 1, key.length);
		return "briar://" + Base32.encode(raw).toLowerCase(Locale.US);
	}

	private static Map<String, Object> map(String k, Object v) {
		Map<String, Object> m = new LinkedHashMap<>();
		m.put(k, v);
		return m;
	}
}
