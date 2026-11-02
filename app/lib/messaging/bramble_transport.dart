import 'dart:async';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';

import '../data/database.dart';
import '../platform/bramble.dart';
import '../l10n/lang.dart';

/// A transport the app drives itself: it pushes what arrives into the router and says when
/// its availability changed. MessagingService binds it on start.
abstract class AppTransport extends Transport {
  void bind({
    required Future<void> Function(Uint8List data) onData,
    required void Function() onChanged,
  });

  /// The ECP contact list changed (added, removed, new links on a card).
  Future<void> contactsChanged(List<Contact> contacts);

  /// Extra fields for the own contact card (e.g. the `briar://` link).
  String? get ownLink => null;

  /// One line for the UI, e.g. "Bramble: tor, lan".
  String get status;

  Future<void> close();
}

/// What a Bramble message carries: its first byte (docs/ARCHITECTURE_V2.md §7).
abstract final class BrambleKind {
  static const pair = 0; // an ECP pair envelope (PACE layer A)
  static const squad = 1; // a squad-net frame: TTL byte + team envelope
}

/// PACE layer A: Bramble over Tor, with LAN and Bluetooth whenever Bramble finds a closer path
/// (docs/ARCHITECTURE_V2.md §1, §7). Bramble queues and retries on its own; the router's ACK
/// timeout decides when to try the next layer anyway. The same node also carries the squad
/// net ([squad]), outside PACE.
class BrambleTransport extends AppTransport {
  BrambleTransport._(this._api, this._myLink) {
    squad = BrambleSquadTransport._(this);
  }

  /// Team traffic to whoever is linked over LAN or Bluetooth right now.
  late final BrambleSquadTransport squad;

  /// Bramble contact id → transports with a live connection (tor / lan / bluetooth).
  final Map<int, Set<String>> _links = {};

  static Future<BrambleTransport> start(
    BrambleApi api, {
    required String profile,
    required String nickname,
    required String password,
  }) async {
    final link = await api.start(profile: profile, nickname: nickname, password: password);
    final t = BrambleTransport._(api, link);
    t._active.addAll(await api.transports());
    for (final c in await api.contacts()) {
      t._links[c.id] = c.links.toSet();
    }
    t._sub = api.events.listen(t._onEvent);
    await t._refreshContacts();
    return t;
  }

  final BrambleApi _api;
  final String _myLink;
  final Set<String> _active = {};

  /// ECP contact id → its card's `briar://` link.
  final Map<String, String> _linkOf = {};

  /// `briar://` link → Bramble contact id.
  final Map<String, int> _brambleId = {};

  StreamSubscription<Map<String, Object?>>? _sub;
  Future<void> Function(Uint8List)? _onData;
  void Function()? _onChanged;

  @override
  String get id => 'bramble';

  @override
  PaceLayer? get layer => PaceLayer.alternate;

  @override
  String? get ownLink => _myLink;

  @override
  String get status =>
      Lang.tr.stBramble(_active.isEmpty ? Lang.tr.waitingNetwork : (_active.toList()..sort()).join(', '));

  /// Up as soon as any of Tor, LAN or Bluetooth is.
  @override
  bool get isAvailable => _active.isNotEmpty;

  @override
  bool canReach(String contactId) => _brambleId.containsKey(_linkOf[contactId]);

  /// Links to [contactId] right now (tor / lan / bluetooth).
  Set<String> linksTo(String contactId) => _links[_brambleId[_linkOf[contactId]]] ?? const {};

  /// Settings, "Obnovit spojení": restart of one transport (tor / lan / bluetooth).
  Future<String> restart(String name) => _api.restartTransport(name);

  /// Removes the Bramble contact behind an ECP contact that is being deleted.
  Future<void> forget(String contactId) async {
    final b = _brambleId[_linkOf[contactId]];
    if (b != null) await _api.removeContact(b);
  }

  /// See BrambleApi.connectBluetooth; null when the contact is not a Bramble contact yet.
  Future<String?> connectBluetooth(String contactId) async {
    final b = _brambleId[_linkOf[contactId]];
    return b == null ? null : _api.connectBluetooth(b);
  }

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async {
    final b = _brambleId[_linkOf[contactId]];
    if (b == null || !isAvailable) return false;
    return _send(b, BrambleKind.pair, data);
  }

  Future<bool> _send(int contact, int kind, List<int> data) async {
    try {
      await _api.send(contact, Uint8List.fromList([kind, ...data]));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void bind({
    required Future<void> Function(Uint8List data) onData,
    required void Function() onChanged,
  }) {
    _onData = onData;
    _onChanged = onChanged;
  }

  @override
  Future<void> contactsChanged(List<Contact> contacts) async {
    _linkOf
      ..clear()
      ..addEntries([
        for (final c in contacts)
          if (c.briarLink != null) MapEntry('${c.id}', c.briarLink!),
      ]);
    // Idempotent: Bramble answers "exists" for contacts it already has or is adding
    for (final e in _linkOf.entries) {
      if (!_brambleId.containsKey(e.value)) await _api.addContact(e.value, e.key);
    }
    _onChanged?.call();
  }

  Future<void> _refreshContacts() async {
    _brambleId
      ..clear()
      ..addEntries([
        for (final c in await _api.contacts())
          if (c.link != null) MapEntry(c.link!, c.id),
      ]);
  }

  Future<void> _onEvent(Map<String, Object?> e) async {
    switch (e['type']) {
      case 'received':
        final d = e['data'] as Uint8List;
        if (d.isEmpty) return;
        final body = Uint8List.sublistView(d, 1);
        if (d[0] == BrambleKind.pair) await _onData?.call(body);
        if (d[0] == BrambleKind.squad) await squad._onData?.call(body);
      case 'connection':
        final c = e['contact'] as int, t = e['transport'] as String;
        final set = _links.putIfAbsent(c, () => {});
        e['open'] == true ? set.add(t) : set.remove(t);
        _onChanged?.call();
      case 'transport':
        final t = e['transport'] as String;
        e['active'] == true ? _active.add(t) : _active.remove(t);
        _onChanged?.call();
      case 'contactAdded' || 'contactRemoved':
        await _refreshContacts();
        _onChanged?.call();
    }
  }

  @override
  Future<void> close() async => _sub?.cancel();
}

/// The squad net over Bramble (outside PACE, layer null): a team frame goes to every contact
/// linked over LAN or Bluetooth right now, and the router relays it on with a lower TTL.
/// Never over Tor — the squad net is the local fallback when nothing else works.
class BrambleSquadTransport extends AppTransport {
  BrambleSquadTransport._(this._b);

  static const local = {'lan', 'bluetooth'};

  final BrambleTransport _b;
  Future<void> Function(Uint8List)? _onData;

  Iterable<int> get _inRange =>
      _b._links.entries.where((e) => e.value.any(local.contains)).map((e) => e.key);

  @override
  String get id => 'squad';

  @override
  PaceLayer? get layer => null;

  @override
  bool get isAvailable => _inRange.isNotEmpty;

  @override
  bool canReach(String contactId) => false; // team frames only, never pair messages

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async => false;

  @override
  Future<bool> broadcast(Uint8List data) async {
    var any = false;
    for (final c in _inRange.toList()) {
      any = await _b._send(c, BrambleKind.squad, data) || any;
    }
    return any;
  }

  @override
  String get status => Lang.tr.stSquad(_inRange.length);

  @override
  void bind({
    required Future<void> Function(Uint8List data) onData,
    required void Function() onChanged,
  }) =>
      _onData = onData;

  @override
  Future<void> contactsChanged(List<Contact> contacts) async {}

  @override
  Future<void> close() async {}
}
