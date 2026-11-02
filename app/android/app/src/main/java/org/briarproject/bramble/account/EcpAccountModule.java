package org.briarproject.bramble.account;

import org.briarproject.bramble.api.account.AccountManager;

import javax.inject.Singleton;

import dagger.Module;
import dagger.Provides;

/**
 * Lives in Bramble's package because AndroidAccountManager is package-private. Never call
 * deleteAccount(): it clears the whole app's data, not just one profile — profiles are wiped
 * by deleting their directory (docs/ARCHITECTURE_V2.md §6).
 */
@Module
public class EcpAccountModule {

	@Provides
	@Singleton
	AccountManager provideAccountManager(AndroidAccountManager accountManager) {
		return accountManager;
	}
}
