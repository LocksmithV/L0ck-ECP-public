package cz.l0ck.ecp.bramble;

import android.app.Application;
import android.content.SharedPreferences;

import org.briarproject.bramble.api.FeatureFlags;
import org.briarproject.bramble.api.crypto.KeyStrengthener;
import org.briarproject.bramble.api.crypto.PublicKey;
import org.briarproject.bramble.api.db.DatabaseConfig;
import org.briarproject.bramble.api.mailbox.MailboxDirectory;
import org.briarproject.bramble.api.plugin.BluetoothConstants;
import org.briarproject.bramble.api.plugin.LanTcpConstants;
import org.briarproject.bramble.api.plugin.PluginConfig;
import org.briarproject.bramble.api.plugin.TorControlPort;
import org.briarproject.bramble.api.plugin.TorDirectory;
import org.briarproject.bramble.api.plugin.TorSocksPort;
import org.briarproject.bramble.api.plugin.TransportId;
import org.briarproject.bramble.api.plugin.duplex.DuplexPluginFactory;
import org.briarproject.bramble.api.plugin.simplex.SimplexPluginFactory;
import org.briarproject.bramble.api.reporting.DevConfig;
import org.briarproject.bramble.plugin.bluetooth.AndroidBluetoothPluginFactory;
import org.briarproject.bramble.plugin.tcp.AndroidLanTcpPluginFactory;
import org.briarproject.bramble.plugin.tor.AndroidTorPluginFactory;

import java.io.File;
import java.util.Collection;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;
import javax.inject.Singleton;

import dagger.Module;
import dagger.Provides;

import static android.content.Context.MODE_PRIVATE;
import static java.util.Arrays.asList;
import static java.util.Collections.emptyList;
import static java.util.Collections.singletonList;
import static java.util.Collections.singletonMap;
import static org.briarproject.bramble.api.plugin.TorConstants.DEFAULT_CONTROL_PORT;
import static org.briarproject.bramble.api.plugin.TorConstants.DEFAULT_SOCKS_PORT;

/**
 * Everything of one ECP profile's Bramble node lives under that profile's directory, so
 * the duress wipe can remove a profile's Tor identity, contacts and keys in one go.
 */
@Module
class EcpAndroidModule {

	// Offset from Briar's defaults, so the app runs next to an installed Briar or Orbot
	private static final int PORT_OFFSET = 20;

	private final Application app;
	private final File dir;

	EcpAndroidModule(Application app, File profileDir) {
		this.app = app;
		this.dir = profileDir;
	}

	@Provides
	@Singleton
	Application provideApplication() {
		return app;
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
				// The account password is a 256-bit secret derived from the profile's master
				// key, which is already bound to this device's Keystore (§6)
				return null;
			}
		};
	}

	@Provides
	@Singleton
	@MailboxDirectory
	File provideMailboxDirectory() {
		return new File(dir, "mailbox");
	}

	@Provides
	@Singleton
	@TorDirectory
	File provideTorDirectory() {
		return new File(dir, "tor");
	}

	@Provides
	@Singleton
	@TorSocksPort
	int provideTorSocksPort() {
		return DEFAULT_SOCKS_PORT + PORT_OFFSET;
	}

	@Provides
	@Singleton
	@TorControlPort
	int provideTorControlPort() {
		return DEFAULT_CONTROL_PORT + PORT_OFFSET;
	}

	@Provides
	@Singleton
	PluginConfig providePluginConfig(AndroidBluetoothPluginFactory bluetooth,
			AndroidTorPluginFactory tor, AndroidLanTcpPluginFactory lan) {
		return new PluginConfig() {
			@Override
			public Collection<DuplexPluginFactory> getDuplexFactories() {
				return asList(bluetooth, tor, lan);
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
				// As in Briar: prefer LAN to Bluetooth when both are up
				return singletonMap(BluetoothConstants.ID, singletonList(LanTcpConstants.ID));
			}
		};
	}

	@Provides
	@Singleton
	DevConfig provideDevConfig() {
		// Crash reports to Briar's developers are deliberately not wired in
		return new DevConfig() {
			@Override
			public PublicKey getDevPublicKey() {
				throw new UnsupportedOperationException("no dev reports");
			}

			@Override
			public String getDevOnionAddress() {
				throw new UnsupportedOperationException("no dev reports");
			}

			@Override
			public File getReportDir() {
				return new File(dir, "reports");
			}

			@Override
			public File getLogcatFile() {
				return new File(dir, "logcat.txt");
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

	@Provides
	SharedPreferences provideSharedPreferences() {
		// Per profile, named after the profile directory (itself an unlinkable hash)
		return app.getSharedPreferences("bramble_" + dir.getName(), MODE_PRIVATE);
	}
}
