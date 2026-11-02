package cz.l0ck.ecp.bramble;

import org.briarproject.bramble.BrambleAndroidEagerSingletons;
import org.briarproject.bramble.BrambleAndroidModule;
import org.briarproject.bramble.BrambleAppComponent;
import org.briarproject.bramble.BrambleCoreEagerSingletons;
import org.briarproject.bramble.BrambleCoreModule;
import org.briarproject.bramble.account.EcpAccountModule;
import org.briarproject.bramble.mailbox.ModularMailboxModule;
import org.briarproject.bramble.system.ClockModule;

import javax.inject.Singleton;

import dagger.Component;

@Singleton
@Component(modules = {
		BrambleCoreModule.class,
		BrambleAndroidModule.class,
		ClockModule.class,
		ModularMailboxModule.class,
		EcpAccountModule.class,
		EcpClientModule.class,
		EcpAndroidModule.class
})
interface EcpBrambleComponent extends BrambleCoreEagerSingletons,
		BrambleAndroidEagerSingletons, BrambleAppComponent, BrambleNode.Graph {

	void inject(EcpClientModule.EagerSingletons init);
}
