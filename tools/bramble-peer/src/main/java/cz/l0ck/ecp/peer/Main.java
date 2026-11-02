package cz.l0ck.ecp.peer;

import org.briarproject.bramble.BrambleCoreEagerSingletons;
import org.briarproject.bramble.BrambleJavaEagerSingletons;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

import cz.l0ck.ecp.bramble.BrambleNode;
import cz.l0ck.ecp.bramble.EcpClientModule;

/**
 * Line protocol, one JSON object per line on stdout:
 * <pre>
 *   start NICK PASSWORD     → {"re":"start","ok":true,"value":"briar://…"}
 *   link | contacts | pending | transports
 *   add LINK ALIAS          → value: pending | exists | invalid
 *   send CONTACT HEX        → value: null
 *   quit
 *   events                  → {"ev":"received","contact":1,"data":"<hex>","links":["lan"]} …
 * </pre>
 * Bramble's own logging goes to stderr. Usage: bramble-peer DIR
 */
public class Main {

	private static final PrintStream OUT = new PrintStream(System.out, true, StandardCharsets.UTF_8);

	public static void main(String[] args) throws Exception {
		if (args.length != 1) {
			System.err.println("usage: bramble-peer DIR");
			System.exit(2);
		}
		Logger.getLogger("").setLevel(Level.WARNING);
		File dir = new File(args[0]);
		if (!dir.isDirectory() && !dir.mkdirs()) throw new IllegalStateException("no dir " + dir);

		PeerComponent c = DaggerPeerComponent.builder().peerModule(new PeerModule(dir)).build();
		BrambleCoreEagerSingletons.Helper.injectEagerSingletons(c);
		BrambleJavaEagerSingletons.Helper.injectEagerSingletons(c);
		c.inject(new EcpClientModule.EagerSingletons());

		BrambleNode node = new BrambleNode(c, (type, fields) -> {
			Map<String, Object> m = new java.util.LinkedHashMap<>();
			m.put("ev", type);
			m.putAll(fields);
			print(m);
		});

		BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
		for (String line; (line = in.readLine()) != null; ) {
			String[] a = line.trim().split("\\s+");
			if (a[0].isEmpty()) continue;
			Map<String, Object> re = new java.util.LinkedHashMap<>();
			re.put("re", a[0]);
			try {
				Object value = switch (a[0]) {
					case "start" -> node.start(a[1], a[2]);
					case "link" -> node.handshakeLink();
					case "add" -> node.addContact(a[1], a.length > 2 ? a[2] : "peer");
					case "contacts" -> node.contacts();
					case "pending" -> node.pendingContacts();
					case "transports" -> node.activeTransports();
					case "send" -> {
						node.send(Integer.parseInt(a[1]), HexFormat.of().parseHex(a[2]));
						yield null;
					}
					case "quit" -> {
						node.stop();
						print(Map.of("re", "quit", "ok", true));
						System.exit(0);
						yield null;
					}
					default -> throw new IllegalArgumentException("unknown command");
				};
				re.put("ok", true);
				re.put("value", value);
			} catch (Exception e) {
				re.put("ok", false);
				re.put("error", e.toString());
			}
			print(re);
		}
		node.stop();
		System.exit(0);
	}

	private static synchronized void print(Map<String, Object> m) {
		OUT.println(json(m));
	}

	static String json(Object o) {
		if (o == null) return "null";
		if (o instanceof Boolean || o instanceof Number) return o.toString();
		if (o instanceof byte[] b) return '"' + HexFormat.of().formatHex(b) + '"';
		if (o instanceof Map<?, ?> m) {
			StringBuilder sb = new StringBuilder("{");
			for (Map.Entry<?, ?> e : m.entrySet()) {
				if (sb.length() > 1) sb.append(',');
				sb.append(json(String.valueOf(e.getKey()))).append(':').append(json(e.getValue()));
			}
			return sb.append('}').toString();
		}
		if (o instanceof List<?> l) {
			StringBuilder sb = new StringBuilder("[");
			for (Object x : l) {
				if (sb.length() > 1) sb.append(',');
				sb.append(json(x));
			}
			return sb.append(']').toString();
		}
		StringBuilder sb = new StringBuilder("\"");
		for (char ch : o.toString().toCharArray()) {
			switch (ch) {
				case '"' -> sb.append("\\\"");
				case '\\' -> sb.append("\\\\");
				case '\n' -> sb.append("\\n");
				default -> {
					if (ch < 0x20) sb.append(String.format("\\u%04x", (int) ch));
					else sb.append(ch);
				}
			}
		}
		return sb.append('"').toString();
	}
}
