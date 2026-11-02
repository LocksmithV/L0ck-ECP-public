package cz.l0ck.ecp.bramble;

import org.briarproject.bramble.api.contact.ContactManager;
import org.briarproject.bramble.api.lifecycle.LifecycleManager;
import org.briarproject.bramble.api.sync.validation.ValidationManager;
import org.briarproject.bramble.api.versioning.ClientVersioningManager;

import javax.inject.Inject;
import javax.inject.Singleton;

import dagger.Module;
import dagger.Provides;

import static cz.l0ck.ecp.bramble.EcpClient.CLIENT_ID;
import static cz.l0ck.ecp.bramble.EcpClient.MAJOR_VERSION;
import static cz.l0ck.ecp.bramble.EcpClient.MINOR_VERSION;

@Module
public class EcpClientModule {

	/** Inject before starting Bramble, so the client's hooks are registered in time. */
	public static class EagerSingletons {
		@Inject
		EcpClient ecpClient;
	}

	@Provides
	@Singleton
	EcpClient provideEcpClient(LifecycleManager lifecycleManager, ContactManager contactManager,
			ValidationManager validationManager,
			ClientVersioningManager clientVersioningManager, EcpClientImpl client) {
		lifecycleManager.registerOpenDatabaseHook(client);
		contactManager.registerContactHook(client);
		validationManager.registerMessageValidator(CLIENT_ID, MAJOR_VERSION, client);
		validationManager.registerIncomingMessageHook(CLIENT_ID, MAJOR_VERSION, client);
		clientVersioningManager.registerClient(CLIENT_ID, MAJOR_VERSION, MINOR_VERSION, client);
		return client;
	}
}
