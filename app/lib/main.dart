import 'dart:io';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'l10n/lang.dart';
import 'messaging/bramble_transport.dart';
import 'messaging/meshcore_app_transport.dart';
import 'messaging/messaging_service.dart';
import 'messaging/simplex_app_transport.dart';
import 'messaging/sms_transport.dart';
import 'platform/bramble.dart';
import 'platform/radio.dart';
import 'platform/sms.dart';
import 'platform/keystore.dart';
import 'platform/notify.dart';
import 'security/native_kdf.dart';
import 'security/security_service.dart';
import 'ui/home_screen.dart';
import 'ui/conversation_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/teams_screen.dart';
import 'ui/quick_lock.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Lang.load();
  runApp(const L0ckApp());
}

class L0ckApp extends StatelessWidget {
  const L0ckApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
        valueListenable: Lang.current,
        builder: (context, locale, _) => MaterialApp(
          title: 'L0ck-ECP',
          debugShowCheckedModeBanner: false,
          theme: l0ckTheme(),
          locale: locale,
          supportedLocales: Lang.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => QuickLock(child: child!),
          home: const AppShell(),
        ),
      );
}

enum _Stage { loading, setup, locked, unlocked }

/// Setup → lock → home. Locking only covers the screen: the unlocked profile, Bramble and the
/// PACE router keep running in the background (EcpService keeps the process alive), so
/// messages arrive with the phone in a pocket (docs/ARCHITECTURE_V2.md §7).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _bramble = NativeBramble();

  SecurityService? _security;
  Session? _session;
  MessagingService? _messaging;
  _Stage _stage = _Stage.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    QuickLock.onTrigger = () {
      if (_stage != _Stage.unlocked) return;
      _lock();
      QuickLock.minimize().ignore();
    };
    _init();
  }

  Future<void> _init() async {
    const keystore = Keystore();
    NativeArgon2? argon;
    try {
      argon = await NativeArgon2.init();
    } catch (_) {
      // Falls back to the (slower) pure-Dart Argon2id; slot files are identical either way
    }
    final security = SecurityService(
      await getApplicationSupportDirectory(),
      strengthen: keystore.strengthen,
      deleteHardwareKey: keystore.deleteKey,
      stretcher: argon?.stretch,
      onProfilesDestroyed: (keep) async {
        // The destroyed profile's node goes offline first, then its data
        await _bramble.stopUnless(keep);
        await _bramble.deleteProfilesExcept(keep);
        await _deleteSimplexExcept(keep);
      },
    );
    final ready = await security.isSetUp();
    setState(() {
      _security = security;
      _stage = ready ? _Stage.locked : _Stage.setup;
    });
  }

  /// SimpleX databases live next to the profile databases, one directory per profile.
  Future<Directory> _simplexRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/simplex');

  Future<void> _deleteSimplexExcept(String? keep) async {
    final root = await _simplexRoot();
    if (!await root.exists()) return;
    await for (final d in root.list()) {
      if (d.uri.pathSegments.where((p) => p.isNotEmpty).last == keep) continue;
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _stage == _Stage.unlocked) _lock();
  }

  /// The user sees the unlocked app: no "new message" notification is due.
  void _inView() {
    _messaging?.seen();
    Notifications.clear().ignore();
    _openFromNotification();
  }

  /// After the PIN: straight to the conversation whose notification was tapped.
  Future<void> _openFromNotification() async {
    final m = _messaging;
    final target = await Notifications.takeOpen();
    if (m == null || target == null || !mounted) return;
    final db = m.session.db;
    Widget? screen;
    if (target.startsWith('c:')) {
      final c = await db.watchContact(int.tryParse(target.substring(2)) ?? -1).first;
      if (c != null) screen = ConversationScreen(messaging: m, contact: c);
    } else if (target.startsWith('t:')) {
      final t = await (db.select(db.teams)..where((t) => t.id.equals(target.substring(2)))).getSingleOrNull();
      if (t != null) screen = TeamScreen(messaging: m, team: t);
    }
    if (screen != null && mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close();
    super.dispose();
  }

  /// Screen lock only; see the class comment.
  void _lock() {
    _messaging?.inForeground = false;
    // Contacts and conversations are pushed above the shell; none may show over the lock
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _stage = _Stage.locked);
  }

  Future<void> _close() async {
    final s = _session;
    final m = _messaging;
    _session = null;
    _messaging = null;
    await m?.dispose(); // flushes replay memory before the database closes
    await s?.close();
  }

  Future<void> _unlocked(Session s) async {
    // A different profile than the one running means duress just destroyed that one
    await _close();
    final m = await MessagingService.start(s);
    if (!mounted) return;
    m.onUnseen = (n, open) => Notifications.message(n, open: open).ignore();
    setState(() {
      _session = s;
      _messaging = m;
      _stage = _Stage.unlocked;
    });
    _inView();
    // Android 13+: without this the "new message" notifications stay silent; Android 12+:
    // without the Bluetooth ones Bramble cannot use Bluetooth (squad net, layer A offline)
    Permissions.request(const [
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_ADVERTISE',
    ]).ignore();
    _startSimplex(s, m);
    _startBramble(s, m);
    _startLoRa(s, m);
    _startSms(m);
  }

  /// Layer E: always plugged in; available once SMS is allowed and a SIM is ready.
  Future<void> _startSms(MessagingService m) async {
    final t = SmsTransport(const NativeSms());
    try {
      await t.start();
    } catch (e) {
      debugPrint('sms: $e');
    }
    if (_messaging == m) await m.addTransport(t);
  }

  /// Layer P: SimpleX takes a few seconds to open its databases and reach its relays.
  Future<void> _startSimplex(Session s, MessagingService m) async {
    try {
      final t = await SimplexAppTransport.start(
        dir: '${(await _simplexRoot()).path}/${s.brambleProfile}',
        dbKey: toHex(await deriveSubkey(s.masterKey, 'simplex')),
        ownKey: s.identity.publicKey,
      );
      if (_messaging == m) {
        await m.addTransport(t);
      } else {
        await t.close();
      }
    } catch (e) {
      debugPrint('simplex: $e'); // no SimpleX: the other layers still work
    }
  }

  /// Layer C is always plugged in; it is available while a paired radio is connected.
  Future<void> _startLoRa(Session s, MessagingService m) async {
    const radio = NativeRadio();
    final t = MeshCoreAppTransport(radio, radio.connected);
    t.reconnectLink = () async {
      final address = await s.db.setting(radioAddressKey);
      if (address == null) return;
      await radio.disconnect();
      await radio.connect(address);
    };
    final key = await s.db.setting(radioChannelKey);
    final k = key == null ? null : decodeChannelKey(key);
    if (k != null) await t.setChannelSecret(k);
    if (_messaging != m) return t.close();
    await m.addTransport(t);
    final address = await s.db.setting(radioAddressKey);
    if (address != null && await Permissions.bluetooth()) await radio.connect(address);
  }

  /// Bramble takes a few seconds (account, DB, Tor); the UI does not wait for it.
  Future<void> _startBramble(Session s, MessagingService m) async {
    try {
      final t = await BrambleTransport.start(_bramble,
          profile: s.brambleProfile, nickname: s.nickname, password: s.bramblePassword);
      if (_messaging == m) {
        await m.addTransport(t);
        await m.addTransport(t.squad);
        // A fresh install grants "Nearby devices" while Bramble is starting; its Bluetooth
        // plugin then stays off until restarted
        if (await Permissions.bluetooth()) await _bramble.refreshBluetooth();
      } else {
        await t.close();
      }
    } catch (_) {
      // RESTART_NEEDED after a duress switch, or no Bramble: the other layers still work
    }
  }

  Future<void> _wiped() async {
    await _close();
    setState(() => _stage = _Stage.setup);
  }

  @override
  Widget build(BuildContext context) {
    final security = _security;
    switch (_stage) {
      case _Stage.loading:
        // Continues the system splash (same background and emblem) while keys load
        return const Scaffold(body: Center(child: BrandHeader()));
      case _Stage.setup:
        return SetupScreen(
          security: security!,
          onDone: () => setState(() => _stage = _Stage.locked),
        );
      case _Stage.locked:
        return LockScreen(
          security: security!,
          runningProfile: _session?.profileId,
          onUnlocked: _unlocked,
          onResumed: () {
            setState(() => _stage = _Stage.unlocked);
            _inView();
          },
          onWiped: _wiped,
        );
      case _Stage.unlocked:
        return HomeScreen(messaging: _messaging!, security: security!, onLock: _lock);
    }
  }
}
