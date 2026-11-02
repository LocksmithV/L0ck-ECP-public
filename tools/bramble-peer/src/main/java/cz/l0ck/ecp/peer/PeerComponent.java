package cz.l0ck.ecp.peer;

import org.briarproject.bramble.BrambleCoreEagerSingletons;
import org.briarproject.bramble.BrambleCoreModule;
import org.briarproject.bramble.BrambleJavaEagerSingletons;
import org.briarproject.bramble.BrambleJavaModule;

import javax.inject.Singleton;

import cz.l0ck.ecp.bramble.BrambleNode;
import cz.l0ck.ecp.bramble.EcpClientModule;
import dagger.Component;

@Singleton
@Component(modules = {
		BrambleCoreModule.class,
		BrambleJavaModule.class,
		EcpClientModule.class,
		PeerModule.class
})
interface PeerComponent extends BrambleCoreEagerSingletons, BrambleJavaEagerSingletons,
		BrambleNode.Graph {

	void inject(EcpClientModule.EagerSingletons init);
}
