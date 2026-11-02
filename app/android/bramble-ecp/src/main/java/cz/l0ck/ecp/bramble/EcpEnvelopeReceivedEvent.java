package cz.l0ck.ecp.bramble;

import org.briarproject.bramble.api.contact.ContactId;
import org.briarproject.bramble.api.event.Event;

/** Broadcast after the transaction that stored an incoming envelope has committed. */
public class EcpEnvelopeReceivedEvent extends Event {

	private final ContactId contactId;
	private final byte[] envelope;

	EcpEnvelopeReceivedEvent(ContactId contactId, byte[] envelope) {
		this.contactId = contactId;
		this.envelope = envelope;
	}

	public ContactId getContactId() {
		return contactId;
	}

	public byte[] getEnvelope() {
		return envelope;
	}
}
