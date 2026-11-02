package cz.l0ck.ecp.bramble;

import org.briarproject.bramble.api.FormatException;
import org.briarproject.bramble.api.client.ClientHelper;
import org.briarproject.bramble.api.client.ContactGroupFactory;
import org.briarproject.bramble.api.contact.Contact;
import org.briarproject.bramble.api.contact.ContactId;
import org.briarproject.bramble.api.contact.ContactManager.ContactHook;
import org.briarproject.bramble.api.data.BdfDictionary;
import org.briarproject.bramble.api.db.DatabaseComponent;
import org.briarproject.bramble.api.db.DbException;
import org.briarproject.bramble.api.db.Metadata;
import org.briarproject.bramble.api.db.Transaction;
import org.briarproject.bramble.api.lifecycle.LifecycleManager.OpenDatabaseHook;
import org.briarproject.bramble.api.sync.Group;
import org.briarproject.bramble.api.sync.Group.Visibility;
import org.briarproject.bramble.api.sync.InvalidMessageException;
import org.briarproject.bramble.api.sync.Message;
import org.briarproject.bramble.api.sync.MessageContext;
import org.briarproject.bramble.api.sync.validation.IncomingMessageHook;
import org.briarproject.bramble.api.sync.validation.MessageValidator;
import org.briarproject.bramble.api.system.Clock;
import org.briarproject.bramble.api.versioning.ClientVersioningManager;
import org.briarproject.bramble.api.versioning.ClientVersioningManager.ClientVersioningHook;

import javax.inject.Inject;

import static org.briarproject.bramble.api.sync.validation.IncomingMessageHook.DeliveryAction.ACCEPT_DO_NOT_SHARE;

/**
 * One contact group per contact, shaped like Briar's private messaging client, but the
 * message body is just the envelope. Validation only checks the size: Bramble already
 * authenticated the sender, and the ECP layer checks everything else.
 */
class EcpClientImpl implements EcpClient, OpenDatabaseHook, ContactHook,
		ClientVersioningHook, IncomingMessageHook, MessageValidator {

	private final DatabaseComponent db;
	private final ClientHelper clientHelper;
	private final ClientVersioningManager clientVersioningManager;
	private final ContactGroupFactory contactGroupFactory;
	private final Clock clock;

	@Inject
	EcpClientImpl(DatabaseComponent db, ClientHelper clientHelper,
			ClientVersioningManager clientVersioningManager,
			ContactGroupFactory contactGroupFactory, Clock clock) {
		this.db = db;
		this.clientHelper = clientHelper;
		this.clientVersioningManager = clientVersioningManager;
		this.contactGroupFactory = contactGroupFactory;
		this.clock = clock;
	}

	private Group getContactGroup(Contact c) {
		return contactGroupFactory.createContactGroup(CLIENT_ID, MAJOR_VERSION, c);
	}

	@Override
	public void onDatabaseOpened(Transaction txn) throws DbException {
		// A local group marks that this client has been set up for existing contacts
		Group local = contactGroupFactory.createLocalGroup(CLIENT_ID, MAJOR_VERSION);
		if (db.containsGroup(txn, local.getId())) return;
		db.addGroup(txn, local);
		for (Contact c : db.getContacts(txn)) addingContact(txn, c);
	}

	@Override
	public void addingContact(Transaction txn, Contact c) throws DbException {
		Group g = getContactGroup(c);
		db.addGroup(txn, g);
		Visibility v = clientVersioningManager.getClientVisibility(txn, c.getId(),
				CLIENT_ID, MAJOR_VERSION);
		db.setGroupVisibility(txn, c.getId(), g.getId(), v);
		clientHelper.setContactId(txn, g.getId(), c.getId());
	}

	@Override
	public void removingContact(Transaction txn, Contact c) throws DbException {
		db.removeGroup(txn, getContactGroup(c));
	}

	@Override
	public void onClientVisibilityChanging(Transaction txn, Contact c, Visibility v)
			throws DbException {
		db.setGroupVisibility(txn, c.getId(), getContactGroup(c).getId(), v);
	}

	@Override
	public MessageContext validateMessage(Message m, Group g) throws InvalidMessageException {
		int n = m.getBody().length;
		if (n == 0 || n > MAX_ENVELOPE_LENGTH) throw new InvalidMessageException();
		return new MessageContext(new Metadata());
	}

	@Override
	public DeliveryAction incomingMessage(Transaction txn, Message m, Metadata meta)
			throws DbException {
		ContactId from = clientHelper.getContactId(txn, m.getGroupId());
		txn.attach(new EcpEnvelopeReceivedEvent(from, m.getBody()));
		return ACCEPT_DO_NOT_SHARE;
	}

	@Override
	public void send(ContactId contact, byte[] envelope) throws DbException {
		if (envelope.length == 0 || envelope.length > MAX_ENVELOPE_LENGTH)
			throw new IllegalArgumentException("envelope size " + envelope.length);
		db.transaction(false, txn -> {
			Group g = getContactGroup(db.getContact(txn, contact));
			Message m = clientHelper.createMessage(g.getId(), clock.currentTimeMillis(), envelope);
			try {
				clientHelper.addLocalMessage(txn, m, new BdfDictionary(), true, false);
			} catch (FormatException e) {
				throw new AssertionError(e); // empty metadata always encodes
			}
		});
	}
}
