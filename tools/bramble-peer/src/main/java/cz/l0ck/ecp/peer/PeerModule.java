package cz.l0ck.ecp.peer;

import org.briarproject.bramble.account.AccountModule;
import org.briarproject.bramble.api.FeatureFlags;
import org.briarproject.bramble.api.crypto.KeyStrengthener;
import org.briarproject.bramble.api.db.DatabaseConfig;
import org.briarproject.bramble.api.mailbox.MailboxDirectory;
import org.briarproject.bramble.api.plugin.PluginConfig;
import org.briarproject.bramble.api.plugin.TorControlPort;
import org.briarproject.bramble.api.plugin.TorDirectory;
import org.briarproject.bramble.api.plugin.TorSocksPort;
import org.briarproject.bramble.api.plugin.TransportId;
import org.briarproject.bramble.api.plugin.duplex.DuplexPluginFactory;
import org.briarproject.bramble.api.plugin.simplex.SimplexPluginFactory;
import org.briarproject.bramble.battery.DefaultBatteryManagerModule;
import org.briarproject.bramble.event.DefaultEventExecutorModule;
import org.briarproject.bramble.plugin.tcp.LanTcpPluginFactory;
import org.briarproject.bramble.plugin.tor.UnixTorPluginFactory;
import org.briarproject.bramble.system.ClockModule;
import org.briarproject.bramble.system.DefaultTaskSchedulerModule;
import org.briarproject.bramble.system.DefaultThreadFactoryModule;
import org.briarproject.bramble.system.DefaultWakefulIoExecutorModule;
import org.briarproject.bramble.system.DesktopSecureRandomModule;

import java.io.File;
import java.util.Collection;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;
import javax.inject.Singleton;

import dagger.Module;
import dagger.Provides;

import static java.util.Arrays.asList;
import static java.util.Collections.emptyList;
import static java.util.Collections.emptyMap;
import static org.briarproject.bramble.api.plugin.TorConstants.DEFAULT_CONTROL_PORT;
import static org.briarproject.bramble.api.plugin.TorConstants.DEFAULT_SOCKS_PORT;

/** Linux node with Tor and LAN, everything under one directory. */
@Module(includes = {
		AccountModule.class,
		ClockModule.class,
		DefaultBatteryManagerModule.class,
		DefaultEventExecutorModule.class,
		DefaultTaskSchedulerModule.class,
		DefaultWakefulIoExecutorModule.class,
		DefaultThreadFactoryModule.class,
		DesktopSecureRandomModule.class
})
class PeerModule {

	// Offset from Briar's defaults, so the peer runs next to briar-headless or a system Tor;
	// BRAMBLE_PORT_OFFSET lets two peers share one machine
	private static final int PORT_OFFSET =
			Integer.parseInt(System.getenv().getOrDefault("BRAMBLE_PORT_OFFSET", "30"));

	private final File dir;

	PeerModule(File dir) {
		this.dir = dir;
	}

	@Provides
	@Singleton
	DatabaseConfig provideDatabaseConfig() {
		File db = new File(dir, "db"), key = new File(dir, "key");
		return new DatabaseConfig() {
			@Override
			public File getDatabaseDirectory() {
				return db;
			}

			@Override
			public File getDatabaseKeyDirectory() {
				return key;
			}

			@Nullable
			@Override
			public KeyStrengthener getKeyStrengthener() {
				return null; // test peer, throwaway data
			}
		};
	}

	@Provides
	@MailboxDirectory
	File provideMailboxDirectory() {
		return new File(dir, "mailbox");
	}

	@Provides
	@TorDirectory
	File provideTorDirectory() {
		return new File(dir, "tor");
	}

	@Provides
	@TorSocksPort
	int provideTorSocksPort() {
		return DEFAULT_SOCKS_PORT + PORT_OFFSET;
	}

	@Provides
	@TorControlPort
	int provideTorControlPort() {
		return DEFAULT_CONTROL_PORT + PORT_OFFSET;
	}

	@Provides
	@Singleton
	PluginConfig providePluginConfig(UnixTorPluginFactory tor, LanTcpPluginFactory lan) {
		return new PluginConfig() {
			@Override
			public Collection<DuplexPluginFactory> getDuplexFactories() {
				return asList(tor, lan);
			}

			@Override
			public Collection<SimplexPluginFactory> getSimplexFactories() {
				return emptyList();
			}

			@Override
			public boolean shouldPoll() {
				return true;
			}

			@Override
			public Map<TransportId, List<TransportId>> getTransportPreferences() {
				return emptyMap();
			}
		};
	}

	@Provides
	FeatureFlags provideFeatureFlags() {
		return new FeatureFlags() {
			@Override
			public boolean shouldEnableImageAttachments() {
				return false;
			}

			@Override
			public boolean shouldEnableProfilePictures() {
				return false;
			}

			@Override
			public boolean shouldEnableDisappearingMessages() {
				return false;
			}

			@Override
			public boolean shouldEnablePrivateGroupsInCore() {
				return false;
			}

			@Override
			public boolean shouldEnableForumsInCore() {
				return false;
			}

			@Override
			public boolean shouldEnableBlogsInCore() {
				return false;
			}
		};
	}
}
