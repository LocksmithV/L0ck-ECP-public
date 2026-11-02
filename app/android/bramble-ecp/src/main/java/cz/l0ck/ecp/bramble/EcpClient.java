package cz.l0ck.ecp.bramble;

import org.briarproject.bramble.api.contact.ContactId;
import org.briarproject.bramble.api.db.DbException;
import org.briarproject.bramble.api.sync.ClientId;

/**
 * Bramble client that carries ECP envelopes (docs/ARCHITECTURE_V2.md §3) between contacts as
 * opaque bytes. Bramble adds transport encryption, store-and-forward and Tor/LAN/Bluetooth;
 * the ECP layer above does its own end-to-end crypto, ACKs and de-duplication.
 */
public interface EcpClient {

	ClientId CLIENT_ID = new ClientId("cz.l0ck.ecp.envelope");
	int MAJOR_VERSION = 0;
	int MINOR_VERSION = 0;

	/** Envelopes are small (position 44 B, SITREP ≤ 140 B); anything near this is garbage. */
	int MAX_ENVELOPE_LENGTH = 4096;

	/** Queues an envelope for the contact; Bramble delivers it whenever a link is up. */
	void send(ContactId contact, byte[] envelope) throws DbException;
}
