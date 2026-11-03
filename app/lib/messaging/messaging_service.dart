import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_meshcore/ecp_meshcore.dart' show MeshCoreTransport;

import '../data/database.dart';
import '../platform/net.dart';
import '../security/lock_config.dart';
import '../security/security_service.dart';
import 'bramble_transport.dart';
import 'meshcore_app_transport.dart';
import 'panic.dart';
import 'simplex_app_transport.dart';
import 'sms_transport.dart';
import '../l10n/lang.dart';

/// Persists the router's outbox in the profile database (docs/ARCHITECTURE_V2.md §7).
class DriftOutboxStore implements OutboxStore {
  DriftOutboxStore(this.db);

  final EcpDatabase db;

  @override
  Future<void> put(OutboxEntry e) => db.into(db.outboxRows).insertOnConflictUpdate(
        OutboxRowsCompanion.insert(
          id: e.id,
          contactId: e.contactId,
          envelope: e.envelope,
          createdAt: e.createdAt,
          emergency: e.emergency,
          state: e.state.index,
          layerIndex: e.layerIndex,
          deadline: Value(e.deadline),
          smsApproved: e.smsApproved,
          tried: e.tried.join(','),
          layers: Value(e.layers?.map((l) => l.name).join(',')),
        ),
      );

  @override
  Future<void> remove(String id) =>
      (db.delete(db.outboxRows)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<OutboxEntry>> loadAll() async => [
        for (final r in await db.select(db.outboxRows).get())
          OutboxEntry(
            id: r.id,
            contactId: r.contactId,
            envelope: r.envelope,
            createdAt: r.createdAt,
            emergency: r.emergency,
            state: OutboxState.values[r.state],
            layerIndex: r.layerIndex,
            deadline: r.deadline,
            smsApproved: r.smsApproved,
            tried: r.tried.isEmpty ? [] : r.tried.split(','),
            layers: r.layers == null ? null : {for (final n in r.layers!.split(',')) PaceLayer.values.byName(n)},
          ),
      ];
}

sealed class AddContactResult {
  const AddContactResult();
}

class ContactAdded extends AddContactResult {
  const ContactAdded(this.contact, this.verification, {this.team});
  final Contact contact;
  final String verification;

  /// Set when the card was a team card: the team just joined.
  final Team? team;
}

/// The card's key was already known: its channel links were refreshed (new card, new
/// channels — e.g. a SimpleX address that did not exist when the first card was shown).
class ContactUpdated extends AddContactResult {
  const ContactUpdated(this.contact, {this.team});
  final Contact contact;
  final Team? team;
}

class ContactRejected extends AddContactResult {
  const ContactRejected(this.reason);
  final String reason;
}

/// What loading a group bundle did (MessagingService.importGroup): contacts new, changed
/// and already as in the bundle; this phone's teams and how many of them are new; the team
/// whose LoRa channel the radio moved to now, whether the PACE order changed, and the own
/// number taken over. When the same bundle is loaded twice, the second time changes nothing.
class GroupImport {
  const GroupImport({
    required this.added,
    required this.changed,
    required this.same,
    required this.teams,
    required this.newTeams,
    this.lora,
    this.pace = false,
    this.phone,
  });

  final int added, changed, same, newTeams;
  final List<Team> teams;
  final Team? lora;
  final bool pace;
  final String? phone;

  bool get nothing => added == 0 && changed == 0 && newTeams == 0 && lora == null && !pace && phone == null;
}

/// Settings key for the own phone number (layer E).
const ownPhoneKey = 'sms.number';

/// Glue between the unlocked profile, the PACE router and the message tables. Channels are
/// plugged in as [Transport]s; without any, messages wait — which is the correct behaviour
/// for a router with nothing to send through.
class MessagingService {
  MessagingService._(this.session, this.router, this._keys, this._transports);

  final Session session;
  final PaceRouter router;
  final KeyRing _keys;
  final List<Transport> _transports;

  Iterable<AppTransport> get _appTransports => _transports.whereType<AppTransport>();

  /// Bumped whenever a channel comes, goes or changes state (UI: own card, channel line).
  final ValueNotifier<int> channelsChanged = ValueNotifier(0);

  /// The running channel of type [T], if any (UI: radio settings).
  T? transport<T extends Transport>() => _transports.whereType<T>().firstOrNull;

  /// Which PACE layers have a channel plugged in, and whether it can send right now.
  Map<PaceLayer, bool> get layers => {
        for (final t in _transports)
          if (t.layer != null) t.layer!: t.isAvailable,
      };

  /// One line per app-driven channel, e.g. "Bramble: tor, lan".
  List<String> get channelStatus => [for (final t in _appTransports) t.status];

  /// The same lines, each with whether that channel can send right now (home screen).
  List<({String status, bool up})> get channelStates =>
      [for (final t in _appTransports) (status: t.status, up: t.isAvailable)];

  /// The channels a team uses besides P/A fan-out: the squad net and LoRa.
  List<String> get teamChannelStatus => [
        for (final t in _appTransports)
          if (t is BrambleSquadTransport || t is MeshCoreAppTransport) t.status
      ];
  /// Latest status per message, recorded synchronously: the router emits events during
  /// [PaceRouter.send], before the message row exists, and the row must still end up right.
  final Map<String, (String, String?)> _latest = {};
  StreamSubscription<RouterEvent>? _sub;
  Timer? _ticker;

  static Future<MessagingService> start(
    Session session, {
    List<Transport> transports = const [],
  }) async {
    final db = session.db;
    final keys = KeyRing(senderFingerprint: await senderFingerprint(session.identity.publicKey));
    for (final c in await db.select(db.contacts).get()) {
      keys.pairs['${c.id}'] = await derivePairKeys(session.identity, c.ecpKey);
    }
    for (final t in await db.select(db.teams).get()) {
      keys.teams[t.id] = t.key;
    }
    final seen = {for (final r in await db.select(db.seenIds).get()) r.id: r.seenAt};
    final router = PaceRouter(
      transports: [...transports], // growable: channels can join later (addTransport)
      keys: keys,
      store: DriftOutboxStore(db),
      replay: ReplayGuard.restore(seen),
    );
    await router.restore();
    final s = MessagingService._(session, router, keys, router.transports);
    s.ownPhone = await db.setting(ownPhoneKey);
    s.panic = PanicConfig.decode(await db.setting(_panicKey));
    s.lock = LockConfig.decode(await db.setting(_lockKey));
    final order = (await db.setting(_paceOrderKey))?.split(',');
    if (order != null && order.length == PaceLayer.values.length) {
      try {
        router.profile = PaceProfile(
            'custom', [for (final n in order) PaceLayer.values.byName(n)], PaceProfile.evasion.policy);
      } on ArgumentError {
        // unknown names (older build): keep the default order
      }
    }
    s._sub = router.events.listen(s._onEvent);
    for (final t in s._appTransports) {
      s._bind(t);
    }
    await s._contactsChanged();
    // Voice clips whose other parts never came (the sender gives up after a day too)
    await (db.delete(db.voiceParts)..where((t) => t.at.isSmallerThanValue(DateTime.now().subtract(const Duration(days: 1)))))
        .go();
    s._ticker = Timer.periodic(const Duration(seconds: 5), (_) => s._tick());
    return s;
  }

  EcpDatabase get _db => session.db;

  /// Internet came or went (Net): SimpleX and Tor follow it, waiting messages try again and
  /// a message stuck on a channel that just went down moves on.
  Future<void> networkChanged() async {
    channelsChanged.value++;
    await router.availabilityChanged(DateTime.now());
  }

  /// Plugs in a channel that came up after unlock (Bramble needs a few seconds to start).
  Future<void> addTransport(Transport t) async {
    _transports.add(t);
    if (t is AppTransport) {
      _bind(t);
      await t.contactsChanged(await _db.select(_db.contacts).get());
    }
    await router.availabilityChanged(DateTime.now());
    channelsChanged.value++;
  }

  void _bind(AppTransport t) => t.bind(
        onData: (d) => router.receive(t, d, now: DateTime.now()),
        onChanged: () {
          channelsChanged.value++;
          router.availabilityChanged(DateTime.now());
        },
      );

  /// Sender fingerprint (hex, 2 bytes) → contact name, for team messages.
  final Map<String, String> senderNames = {};
  final Map<String, int> _contactByFingerprint = {};

  Future<void> _contactsChanged() async {
    final all = await _db.select(_db.contacts).get();
    senderNames.clear();
    _contactByFingerprint.clear();
    for (final c in all) {
      final fp = toHex(await senderFingerprint(c.ecpKey));
      senderNames[fp] = c.name;
      _contactByFingerprint[fp] = c.id;
    }
    for (final t in _appTransports) {
      try {
        // Not waited for longer: a channel that hangs (no network, radio out of reach)
        // must not hold up adding contacts; it carries on by itself
        await t.contactsChanged(all).timeout(const Duration(seconds: 15));
      } catch (_) {
        // A channel that is down must not stop the others
      }
    }
  }

  Future<void> _tick() async {
    await router.tick(DateTime.now());
    await _persistReplay();
  }

  Future<void> _persistReplay() async {
    final seen = router.replay.export();
    await _db.transaction(() async {
      await _db.delete(_db.seenIds).go();
      await _db.batch((b) => b.insertAll(_db.seenIds, [
            for (final e in seen.entries) SeenIdsCompanion.insert(id: e.key, seenAt: e.value),
          ]));
    });
  }

  // --- contacts ---

  Future<AddContactResult> addContactFromUri(String uri, {bool verified = false}) async {
    final ContactCard card;
    try {
      card = ContactCard.fromUri(uri);
    } on FormatException {
      return ContactRejected(Lang.tr.invalidContactLink);
    }
    if (constantTimeEquals(card.ecpKey, session.identity.publicKey)) {
      return ContactRejected(Lang.tr.ownContact);
    }
    final team = card.isTeamCard ? await _joinTeam(card.teamKey!, Lang.tr.teamOf(card.name)) : null;
    final known = await _db.contactByKey(card.ecpKey);
    if (known != null) {
      // Only add what the card has; a card never removes a channel
      await (_db.update(_db.contacts)..where((t) => t.id.equals(known.id))).write(ContactsCompanion(
        briarLink: card.briarLink == null ? const Value.absent() : Value(card.briarLink),
        simplexLink: card.simplexLink == null ? const Value.absent() : Value(card.simplexLink),
        phone: card.phone == null ? const Value.absent() : Value(card.phone),
        meshtasticId: card.meshtasticNodeId == null ? const Value.absent() : Value(card.meshtasticNodeId),
        meshcoreKey: card.meshcoreKey == null ? const Value.absent() : Value(card.meshcoreKey),
      ));
      if (verified) await setVerified(known.id, true);
      await _contactsChanged();
      if (team != null) await _joinedVia(team, known.id);
      return ContactUpdated(
          await (_db.select(_db.contacts)..where((t) => t.id.equals(known.id))).getSingle(),
          team: team);
    }
    final id = await _db.into(_db.contacts).insert(ContactsCompanion.insert(
          name: card.name,
          ecpKey: card.ecpKey,
          briarLink: Value(card.briarLink),
          simplexLink: Value(card.simplexLink),
          phone: Value(card.phone),
          meshtasticId: Value(card.meshtasticNodeId),
          meshcoreKey: Value(card.meshcoreKey),
          verified: Value(verified),
          addedAt: DateTime.now(),
        ));
    _keys.pairs['$id'] = await derivePairKeys(session.identity, card.ecpKey);
    await _contactsChanged();
    if (team != null) await _joinedVia(team, id);
    final contact = await (_db.select(_db.contacts)..where((t) => t.id.equals(id))).getSingle();
    return ContactAdded(
        contact, await verificationNumber(session.identity.publicKey, card.ecpKey),
        team: team);
  }

  // --- teams ---

  /// Team id: the same for every member, since it comes from the shared key.
  static Future<String> teamIdFor(List<int> key) async =>
      toHex(await deriveSubkey(key, 'team-id')).substring(0, 16);

  /// The team's private LoRa channel key (MeshCore channel, 16 bytes).
  static Future<Uint8List> teamLoraKey(List<int> key) async =>
      Uint8List.fromList((await deriveSubkey(key, 'lora')).sublist(0, 16));

  Future<Team> createTeam(String name) => _joinTeam(randomBytes(32), name);

  /// Joined [team] through [contactId]'s team QR: they are a member, and they learn that we
  /// are one too (control 0x03), so their team messages reach us over SimpleX/Bramble.
  Future<void> _joinedVia(Team team, int contactId) async {
    await addTeamMember(team.id, contactId);
    await router.send('$contactId', MessageType.control, [_teamMember, ...fromHex(team.id)],
        now: DateTime.now());
  }

  /// Leaves a team: known members are told (control 0x04, SimpleX/Tor only, best effort),
  /// then the team, its messages and its key are gone from this phone. If the LoRa radio was
  /// on this team's channel it goes back to the common ECP channel. Anyone who still has the
  /// team key can of course keep reading their own copies.
  Future<void> leaveTeam(String teamId) async {
    final now = DateTime.now();
    for (final c in await _teamMemberIds(teamId)) {
      await router.sendOnce('$c', MessageType.control, [_teamLeft, ...fromHex(teamId)],
          layers: const {PaceLayer.primary, PaceLayer.alternate}, now: now);
    }
    final team = await (_db.select(_db.teams)..where((t) => t.id.equals(teamId))).getSingleOrNull();
    if (team != null && await _db.setting(radioChannelKey) == encodeChannelKey(await teamLoraKey(team.key))) {
      await _db.setSetting(radioChannelKey, null);
      await transport<MeshCoreAppTransport>()?.setChannelSecret(MeshCoreTransport.defaultChannelSecret);
    }
    await (_db.delete(_db.messages)..where((t) => t.teamId.equals(teamId))).go();
    await (_db.delete(_db.teamMembers)..where((t) => t.teamId.equals(teamId))).go();
    await (_db.delete(_db.teams)..where((t) => t.id.equals(teamId))).go();
    _keys.teams.remove(teamId);
    channelsChanged.value++;
  }

  Future<void> addTeamMember(String teamId, int contactId) => _db
      .into(_db.teamMembers)
      .insert(TeamMembersCompanion.insert(teamId: teamId, contactId: contactId),
          mode: InsertMode.insertOrIgnore);

  Future<void> removeTeamMember(String teamId, int contactId) => (_db.delete(_db.teamMembers)
        ..where((t) => t.teamId.equals(teamId) & t.contactId.equals(contactId)))
      .go();

  Future<List<int>> _teamMemberIds(String teamId) async => [
        for (final r in await (_db.select(_db.teamMembers)..where((t) => t.teamId.equals(teamId))).get())
          r.contactId,
      ];

  Future<Team> _joinTeam(List<int> key, String name) async {
    final id = await teamIdFor(key);
    final known = await (_db.select(_db.teams)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (known != null) return known;
    await _db.into(_db.teams).insert(TeamsCompanion.insert(
        id: id, name: name, key: Uint8List.fromList(key), joinedAt: DateTime.now()));
    _keys.teams[id] = Uint8List.fromList(key);
    return (_db.select(_db.teams)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Switches the LoRa radio to the team's private channel (same key for every member).
  /// The choice is saved first; a radio that does not answer in time (or has no free slot)
  /// gets the channel when it connects again.
  Future<void> useTeamLoRa(Team t) async {
    final k = await teamLoraKey(t.key);
    await _db.setSetting(radioChannelKey, encodeChannelKey(k));
    try {
      await transport<MeshCoreAppTransport>()?.setChannelSecret(k).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('lora channel: $e');
    }
    channelsChanged.value++;
  }

  // --- group setup from the base laptop (tools/ecp_base) ---

  /// Sets this phone up from a [GroupBundle]: the other members become contacts, verified
  /// (the base saw every phone in person); the teams that list this phone are joined, with
  /// the other members as team members; the radio moves to the chosen team's LoRa channel
  /// when this phone is in that team; the PACE order is taken over. A phone number the base
  /// gave this phone's own card (typed in there, or corrected) becomes the own number. Every
  /// phone imports the same bundle, so nobody needs to be told. Null when this phone is not
  /// in the bundle. [progress] hears how many of the other members are set up so far.
  Future<GroupImport?> importGroup(GroupBundle b, {void Function(int done, int total)? progress}) async {
    final self = b.indexOf(session.identity.publicKey);
    if (self == null) return null;
    // First, so that only contacts known before hear of it; the members have it in the bundle
    final phone = ownPhoneFrom(b);
    if (phone != null) await setOwnPhone(phone);
    // Loaded again (a corrected bundle): only what differs is written
    final ids = <int, int>{};
    var added = 0, changed = 0, same = 0;
    final total = b.members.length - 1;
    for (final (i, m) in b.members.indexed) {
      if (i == self) continue;
      progress?.call(added + changed + same, total);
      final known = await _db.contactByKey(m.ecpKey);
      if (known == null) {
        if (await addContactFromUri(m.toUri(), verified: true) case ContactAdded(:final contact)) {
          ids[i] = contact.id;
          added++;
        }
        continue;
      }
      ids[i] = known.id;
      final update = _cardChanges(known, m);
      if (update == null) {
        same++;
      } else {
        await (_db.update(_db.contacts)..where((t) => t.id.equals(known.id))).write(update);
        changed++;
      }
    }
    if (changed > 0) await _contactsChanged();
    final teams = <int, Team>{};
    var newTeams = 0;
    for (final (i, t) in b.teams.indexed) {
      if (!t.members.contains(self)) continue; // another group's key: not kept
      final id = await teamIdFor(t.key);
      if (await (_db.select(_db.teams)..where((x) => x.id.equals(id))).getSingleOrNull() == null) newTeams++;
      final team = await _joinTeam(t.key, t.name);
      for (final m in t.members) {
        final id = ids[m];
        if (id != null) await addTeamMember(team.id, id); // insert-or-ignore
      }
      teams[i] = team;
    }
    var lora = b.loraTeam == null ? null : teams[b.loraTeam!];
    if (lora != null &&
        await _db.setting(radioChannelKey) == encodeChannelKey(await teamLoraKey(lora.key))) {
      lora = null; // the radio is on that channel already
    }
    if (lora != null) await useTeamLoRa(lora);
    final pace = b.pace != null && b.pace!.join() != paceOrder.join();
    if (pace) await setPaceOrder(b.pace!);
    channelsChanged.value++;
    return GroupImport(
        added: added, changed: changed, same: same, teams: teams.values.toList(), newTeams: newTeams,
        lora: lora, pace: pace, phone: phone);
  }

  /// What a bundle card would change on a known contact: the name the base gave it, the
  /// channels the card has (a card never removes one) and the verified mark. Null: nothing.
  ContactsCompanion? _cardChanges(Contact c, ContactCard m) {
    Value<T> diff<T>(T? card, T? now) => card != null && card != now ? Value(card) : const Value.absent();
    final update = ContactsCompanion(
      name: m.name != c.name ? Value(m.name) : const Value.absent(),
      briarLink: diff(m.briarLink, c.briarLink),
      simplexLink: diff(m.simplexLink, c.simplexLink),
      phone: diff(m.phone, c.phone),
      meshtasticId: diff(m.meshtasticNodeId, c.meshtasticId),
      meshcoreKey: m.meshcoreKey != null && !constantTimeEquals(m.meshcoreKey!, c.meshcoreKey ?? const [])
          ? Value(m.meshcoreKey)
          : const Value.absent(),
      verified: c.verified ? const Value.absent() : const Value(true),
    );
    final any = [update.name, update.briarLink, update.simplexLink, update.phone, update.meshtasticId,
      update.meshcoreKey, update.verified].any((v) => v.present);
    return any ? update : null;
  }

  /// The number on this phone's own card in [b] when it differs from the own number, else
  /// null.
  String? ownPhoneFrom(GroupBundle b) {
    final self = b.indexOf(session.identity.publicKey);
    final phone = self == null ? null : b.members[self].phone?.trim();
    return phone == null || phone.isEmpty || phone == ownPhone ? null : phone;
  }

  /// The team's name is a local label: each member may call it as they like.
  Future<void> renameTeam(String id, String name) =>
      (_db.update(_db.teams)..where((t) => t.id.equals(id))).write(TeamsCompanion(name: Value(name)));

  /// The team QR: the own contact card plus the team key. Show it only in person — whoever
  /// photographs it reads the team's traffic.
  String teamCardUri(Team t) => ContactCard(
        name: session.nickname,
        ecpKey: session.identity.publicKey,
        briarLink: transport<BrambleTransport>()?.ownLink,
        simplexLink: transport<SimplexAppTransport>()?.ownLink,
        phone: ownPhone,
        teamKey: t.key,
      ).toUri();

  /// A team message goes out once on every channel that can broadcast (squad net, LoRa);
  /// there is no ACK, members answer instead.
  /// A team message goes out once on every broadcast channel (squad net, LoRa) and to each
  /// known member over SimpleX/Bramble (store-and-forward, so members far away get it too).
  /// There is no ACK; members answer instead.
  Future<void> sendTeamText(String teamId, String text) =>
      sendTeamPayload(teamId, MessageType.text, encodeText(text));

  Future<void> sendTeamPayload(String teamId, int type, Uint8List payload) async {
    final now = DateTime.now();
    final members = [for (final c in await _teamMemberIds(teamId)) '$c'];
    final r = await router.sendTeamTo(teamId, type, payload, now: now, members: members);
    final id = r.id;
    final via = r.via.toList()..sort();
    await _db.into(_db.messages).insert(MessagesCompanion.insert(
          id: id,
          teamId: Value(teamId),
          outgoing: true,
          type: type,
          payload: payload,
          at: now,
          status: via.isEmpty ? 'failed' : 'sent',
          statusAt: Value(now),
          via: Value(via.isEmpty ? null : via.join('+')),
        ));
  }

  /// The user opened the conversation: incoming messages are seen, and the sender learns
  /// it — over SimpleX/Bramble only, once; a read receipt never goes by LoRa or SMS.
  Future<void> markRead(int contactId) async {
    final unread = await (_db.select(_db.messages)
          ..where((t) =>
              t.contactId.equals(contactId) & t.outgoing.equals(false) & t.status.equals('received')))
        .get();
    if (unread.isEmpty) return;
    final now = DateTime.now();
    await (_db.update(_db.messages)..where((t) => t.id.isIn([for (final m in unread) m.id])))
        .write(MessagesCompanion(status: const Value('seen'), statusAt: Value(now)));
    for (var i = 0; i < unread.length; i += 20) {
      final ids = unread.skip(i).take(20).expand((m) => fromHex(m.id));
      await router.sendOnce('$contactId', MessageType.control, [_readReceipt, ...ids],
          layers: const {PaceLayer.primary, PaceLayer.alternate}, now: now);
    }
  }

  Future<void> markTeamRead(String teamId) => (_db.update(_db.messages)
        ..where((t) => t.teamId.equals(teamId) & t.status.equals('received')))
      .write(MessagesCompanion(status: const Value('seen'), statusAt: Value(DateTime.now())));

  Future<void> renameContact(int id, String name) =>
      (_db.update(_db.contacts)..where((t) => t.id.equals(id))).write(ContactsCompanion(name: Value(name)));

  /// Clears a chat on this phone only: its messages and any voice or file parts still coming
  /// in. The contact or team stays; nothing is sent.
  Future<void> clearChat({int? contactId, String? teamId}) async {
    if (contactId != null) {
      await (_db.delete(_db.messages)..where((t) => t.contactId.equals(contactId))).go();
      await (_db.delete(_db.voiceParts)..where((t) => t.clip.like('c:$contactId:%'))).go();
    }
    if (teamId != null) {
      await (_db.delete(_db.messages)..where((t) => t.teamId.equals(teamId))).go();
      await (_db.delete(_db.voiceParts)..where((t) => t.clip.like('t:$teamId:%'))).go();
    }
  }

  /// Forgets a contact: messages, team memberships, keys, and the Bramble contact.
  Future<void> deleteContact(int id) async {
    await (_db.delete(_db.messages)..where((t) => t.contactId.equals(id))).go();
    await (_db.delete(_db.teamMembers)..where((t) => t.contactId.equals(id))).go();
    await transport<BrambleTransport>()?.forget('$id');
    await (_db.delete(_db.contacts)..where((t) => t.id.equals(id))).go();
    _keys.pairs.remove('$id');
    await _contactsChanged();
  }

  // --- reconnecting (settings) ---

  /// Restarts one channel after a break in connectivity: simplex, tor, lan, bluetooth, lora,
  /// sms. Returns a short status for the user.
  Future<String> refreshChannel(String which) async {
    final l = Lang.tr;
    final result = switch (which) {
      'simplex' => switch (await transport<SimplexAppTransport>()?.reconnect()) {
          true => l.rcConnectingRelays,
          false => l.rcError,
          null => l.rcNotRunning,
        },
      'tor' || 'lan' || 'bluetooth' => switch (await transport<BrambleTransport>()?.restart(which)) {
          'ACTIVE' => l.rcRunning,
          'ENABLING' || 'STARTING_STOPPING' => l.rcStarting,
          'INACTIVE' => which == 'bluetooth' ? l.rcBtInactive : l.waitingNetwork,
          null => l.rcBrambleNotRunning,
          final s => s.toLowerCase(),
        },
      'lora' => await () async {
          final t = transport<MeshCoreAppTransport>();
          if (t?.reconnectLink == null) return l.rcNoRadio;
          await t!.reconnectLink!();
          return l.rcConnectingRadio;
        }(),
      'sms' => await () async {
          await transport<SmsTransport>()?.refresh();
          return transport<SmsTransport>()?.status ?? l.rcNotRunning;
        }(),
      _ => '?',
    };
    await router.availabilityChanged(DateTime.now());
    channelsChanged.value++;
    return result;
  }

  // --- PACE order ---

  // --- PANIC (PIN screen) ---

  static const _panicKey = 'panic';

  /// What the PIN screen's PANIC sends (settings).
  PanicConfig panic = const PanicConfig();

  Future<void> setPanic(PanicConfig c) async {
    panic = c;
    await _db.setSetting(_panicKey, c.encode());
  }

  // --- locking (settings) ---

  static const _lockKey = 'lock';

  /// When the app locks itself and whether a fingerprint may open it.
  LockConfig lock = const LockConfig();

  Future<void> setLock(LockConfig c) async {
    lock = c;
    await _db.setSetting(_lockKey, c.encode());
  }

  /// PANIC, without the PIN: the configured status (or "compromised") with [position], then
  /// the own text, to every contact and team [panic] names. Emergency mode: every channel at
  /// once, SMS without asking. Returns the contact message ids and how many contacts and
  /// teams it went to.
  Future<({List<String> ids, int contacts, int teams})> sendPanic({bool compromised = false, Position? position}) async {
    final c = panic;
    final status =
        StatusReport(compromised ? StatusCode.compromised : c.status, c.position ? position : null).encode();
    final text = compromised || c.text.trim().isEmpty ? null : encodeText(c.text.trim());
    final ids = <String>[];
    var contacts = 0;
    if (c.contacts) {
      for (final k in await _db.select(_db.contacts).get()) {
        contacts++;
        ids.add(await sendPayload(k.id, MessageType.report, status, emergency: true));
        if (text != null) ids.add(await sendPayload(k.id, MessageType.text, text, emergency: true));
      }
    }
    var teams = 0;
    if (c.teams) {
      for (final t in await _db.select(_db.teams).get()) {
        await sendTeamPayload(t.id, MessageType.report, status);
        if (text != null) await sendTeamPayload(t.id, MessageType.text, text);
        teams++;
      }
    }
    return (ids: ids, contacts: contacts, teams: teams);
  }

  /// Waits until every message in [ids] is delivered, or [max] has passed — before the
  /// profile that sent them is destroyed, so its channels get the chance to hand them on.
  Future<void> awaitDelivery(List<String> ids, Duration max) async {
    final end = DateTime.now().add(max);
    while (DateTime.now().isBefore(end)) {
      final rows = await (_db.select(_db.messages)..where((t) => t.id.isIn(ids))).get();
      if (rows.every((m) => m.status == 'delivered' || m.status == 'read')) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  static const _paceOrderKey = 'pace.order';

  List<PaceLayer> get paceOrder => router.profile.order;

  /// Reorders the PACE layers (settings). SMS still needs confirmation wherever it stands.
  Future<void> setPaceOrder(List<PaceLayer> order) async {
    router.profile = PaceProfile('custom', List.unmodifiable(order), PaceProfile.evasion.policy);
    await _db.setSetting(_paceOrderKey, order.map((l) => l.name).join(','));
    channelsChanged.value++;
  }

  Future<String> verificationFor(Contact c) =>
      verificationNumber(session.identity.publicKey, c.ecpKey);

  Future<void> setVerified(int contactId, bool verified) =>
      (_db.update(_db.contacts)..where((t) => t.id.equals(contactId)))
          .write(ContactsCompanion(verified: Value(verified)));

  /// True while the user looks at the unlocked app; otherwise new messages are announced.
  bool inForeground = false;
  int _unseen = 0;

  /// Called with the number of messages that arrived while the app was not in view, and
  /// the conversation of the latest (`c:CONTACT_ID` / `t:TEAM_ID`).
  void Function(int unseen, String open)? onUnseen;

  /// The user is back in the app: nothing is unseen any more.
  void seen() {
    inForeground = true;
    _unseen = 0;
  }

  /// Own number for layer E, as the user typed it (Android cannot read it reliably).
  String? ownPhone;

  /// Sets the own number (e.g. a local SIM in the deployment area). The QR follows at once,
  /// and every contact is told over the ECP channels, so nobody has to scan again.
  Future<void> setOwnPhone(String? number) async {
    final n = number?.trim();
    final changed = (n == null || n.isEmpty ? null : n) != ownPhone;
    ownPhone = n == null || n.isEmpty ? null : n;
    await _db.setSetting(ownPhoneKey, ownPhone);
    channelsChanged.value++;
    if (changed) await _announceCard();
  }

  /// The nickname changed (settings): new QR, and contacts learn the new name.
  Future<void> profileChanged() async {
    channelsChanged.value++;
    await _announceCard();
  }

  /// Control message 0x01: the sender's current name and number, as a minimal card (fits LoRa).
  static const _cardUpdate = 0x01;

  Future<void> _announceCard() async {
    final card = ContactCard(name: session.nickname, ecpKey: session.identity.publicKey, phone: ownPhone);
    final payload = [_cardUpdate, ...card.encode()];
    for (final c in await _db.select(_db.contacts).get()) {
      await router.send('${c.id}', MessageType.control, payload, now: DateTime.now());
    }
  }

  /// A contact's card update. Accepted only when the card's key is that contact's key — the
  /// envelope already proved who sent it. The number in it is authoritative (none = removed).
  /// Control 0x02: "I have read these" — 8-byte message ids.
  static const _readReceipt = 0x02;

  /// Control 0x03: "I am in this team" — the 8-byte team id.
  static const _teamMember = 0x03;

  /// Control 0x04: "I left this team" — the 8-byte team id.
  static const _teamLeft = 0x04;

  Future<void> _onControl(String from, List<int> payload) async {
    final id = int.tryParse(from);
    if (payload.isEmpty || id == null) return;
    if (payload[0] == _readReceipt) {
      final now = DateTime.now();
      for (var i = 1; i + 8 <= payload.length; i += 8) {
        final mid = toHex(payload.sublist(i, i + 8));
        await (_db.update(_db.messages)
              ..where((t) => t.id.equals(mid) & t.contactId.equals(id) & t.outgoing.equals(true)))
            .write(MessagesCompanion(status: const Value('read'), statusAt: Value(now)));
      }
      return;
    }
    if (payload[0] == _teamMember && payload.length == 9) {
      final team = toHex(payload.sublist(1));
      if (_keys.teams.containsKey(team)) await addTeamMember(team, id);
      return;
    }
    if (payload[0] == _teamLeft && payload.length == 9) {
      await removeTeamMember(toHex(payload.sublist(1)), id);
      return;
    }
    if (payload[0] != _cardUpdate) return;
    final ContactCard card;
    try {
      card = ContactCard.decode(payload.sublist(1));
    } on FormatException {
      return;
    }
    final c = await (_db.select(_db.contacts)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (c == null || !constantTimeEquals(c.ecpKey, card.ecpKey)) return;
    await (_db.update(_db.contacts)..where((t) => t.id.equals(id)))
        .write(ContactsCompanion(phone: Value(card.phone), name: Value(card.name)));
    await _contactsChanged();
  }

  /// The own card, with every channel that is up (briar://, SimpleX address, phone number).
  String myContactUri() => ContactCard(
        name: session.nickname,
        ecpKey: session.identity.publicKey,
        briarLink: transport<BrambleTransport>()?.ownLink,
        simplexLink: transport<SimplexAppTransport>()?.ownLink,
        phone: ownPhone,
      ).toUri();

  // --- messages ---

  Future<void> sendText(int contactId, String text, {bool emergency = false}) =>
      sendPayload(contactId, MessageType.text, encodeText(text), emergency: emergency);

  /// Any message type (position, report, text) to one contact, through PACE.
  Future<String> sendPayload(int contactId, int type, Uint8List payload, {bool emergency = false}) async {
    final now = DateTime.now();
    final id = await router.send('$contactId', type, payload, emergency: emergency, now: now);
    final s = _latest[id];
    await _db.into(_db.messages).insert(MessagesCompanion.insert(
          id: id,
          contactId: Value(contactId),
          outgoing: true,
          type: type,
          payload: payload,
          at: now,
          status: s?.$1 ?? 'sending',
          via: Value(s?.$2),
        ));
    await _apply(id); // an event may have landed while the insert ran
    return id;
  }

  // --- calls (CallService) ---

  /// Local-only message type: a call in the conversation (who called, how it ended, how
  /// long). Payload: `result u8 · seconds u16`. Never sent.
  static const callLogType = 0x87;
  static const callAnswered = 0, callMissed = 1, callDeclined = 2, callFailed = 3;

  final _callSignals = StreamController<(int, CallSignal)>.broadcast();

  /// Call set-up from contacts (CallService listens).
  Stream<(int contactId, CallSignal signal)> get callSignals => _callSignals.stream;

  /// A call can go now: SimpleX or Bramble carries the set-up, and the audio has a path —
  /// the internet, or the same Wi-Fi (a Bramble LAN link to that contact).
  bool canCall(int contactId) =>
      canSendVoice(contactId) &&
      (Net.online.value || (transport<BrambleTransport>()?.linksTo('$contactId').contains('lan') ?? false));

  /// One try over SimpleX/Bramble, no queue: a call set-up that comes late is useless.
  Future<bool> sendCallSignal(int contactId, CallSignal signal) async =>
      await router.sendOnce('$contactId', MessageType.call, signal.encode(),
          layers: _voiceLayersFor(contactId), now: DateTime.now()) !=
      null;

  /// Puts a finished call into the conversation; a missed one counts as unread.
  Future<void> logCall(int contactId, {required bool outgoing, required int result, int seconds = 0}) async {
    final now = DateTime.now();
    await _db.into(_db.messages).insert(MessagesCompanion.insert(
          id: toHex(randomBytes(8)),
          contactId: Value(contactId),
          outgoing: outgoing,
          type: callLogType,
          payload: (ByteWriter()
                ..u8(result)
                ..u16(seconds.clamp(0, 0xffff)))
              .toBytes(),
          at: now,
          status: outgoing ? 'delivered' : (result == callMissed ? 'received' : 'seen'),
          statusAt: Value(now),
        ));
    if (!outgoing && result == callMissed && !inForeground) onUnseen?.call(++_unseen, 'c:$contactId');
  }

  // --- voice messages ---

  /// Voice goes over SimpleX and Bramble only: too big for LoRa, too dear for SMS. Bramble
  /// only by Tor or the local network, never Bluetooth alone (too slow).
  static const voiceLayers = {PaceLayer.primary, PaceLayer.alternate};

  bool _voiceReach(Transport t, int contactId) => t is BrambleTransport
      ? t.canReachWithoutBluetooth('$contactId')
      : t.canReach('$contactId');

  /// The layers a voice message (or call set-up) to [contactId] may use, in PACE order:
  /// without Bramble while it has nothing but a Bluetooth link to them.
  Set<PaceLayer> _voiceLayersFor(int contactId) {
    final b = transport<BrambleTransport>();
    final btOnly = b != null && b.canReach('$contactId') && !b.canReachWithoutBluetooth('$contactId');
    return btOnly ? const {PaceLayer.primary} : voiceLayers;
  }

  /// A channel fit for voice reaches [contactId] right now (UI: the microphone button).
  bool canSendVoice(int contactId) =>
      _transports.any((t) => voiceLayers.contains(t.layer) && t.isAvailable && _voiceReach(t, contactId));

  /// The team's voice reaches someone now: a member over SimpleX, or Bramble by Tor/LAN.
  Future<bool> canSendTeamVoice(String teamId) async => (await _teamMemberIds(teamId)).any(canSendVoice);

  /// A recorded clip to one contact, in [VoicePart]s with ACK over [voiceLayers] (it waits,
  /// never goes by LoRa or SMS). One message row shows the whole clip; it has the last
  /// part's id and is "delivered" once every part is.
  Future<String> sendVoice(int contactId, int codec, int durationMs, Uint8List audio) {
    final parts = VoicePart.split(randomBytes(4), codec, durationMs, audio);
    return _sendInParts(contactId, MessageType.voice, [for (final p in parts) p.encode()], VoicePart.join(parts).encode());
  }

  /// A recorded clip to a team: each part to the members over SimpleX, or Bramble by
  /// Tor/LAN — not broadcast on the squad net (Bluetooth) or LoRa.
  Future<void> sendTeamVoice(String teamId, int codec, int durationMs, Uint8List audio) {
    final parts = VoicePart.split(randomBytes(4), codec, durationMs, audio);
    return _sendTeamInParts(teamId, MessageType.voice, [for (final p in parts) p.encode()], VoicePart.join(parts).encode());
  }

  /// A photo or file to one contact, like a voice clip: [FilePart]s over SimpleX/Bramble.
  Future<String> sendAttachment(int contactId, Attachment a) {
    final blob = a.encode();
    return _sendInParts(
        contactId, MessageType.file, [for (final p in FilePart.split(randomBytes(4), blob)) p.encode()], blob);
  }

  Future<void> sendTeamAttachment(String teamId, Attachment a) {
    final blob = a.encode();
    return _sendTeamInParts(
        teamId, MessageType.file, [for (final p in FilePart.split(randomBytes(4), blob)) p.encode()], blob);
  }

  Future<String> _sendInParts(int contactId, int type, List<Uint8List> parts, Uint8List whole) async {
    final now = DateTime.now();
    final layers = _voiceLayersFor(contactId);
    final earlier = <String>[];
    var id = '';
    for (final (i, p) in parts.indexed) {
      id = await router.send('$contactId', type, p, layers: layers, now: now);
      if (i < parts.length - 1) earlier.add(id);
    }
    _holdUntilAllParts(id, earlier);
    final s = _latest[id];
    await _db.into(_db.messages).insert(MessagesCompanion.insert(
          id: id,
          contactId: Value(contactId),
          outgoing: true,
          type: type,
          payload: whole,
          at: now,
          status: s?.$1 ?? 'sending',
          via: Value(s?.$2),
        ));
    await _apply(id);
    return id;
  }

  Future<void> _sendTeamInParts(String teamId, int type, List<Uint8List> parts, Uint8List whole) async {
    final now = DateTime.now();
    // Members Bramble reaches only by Bluetooth get it over SimpleX alone
    final groups = <Set<PaceLayer>, List<String>>{};
    for (final c in await _teamMemberIds(teamId)) {
      groups.putIfAbsent(_voiceLayersFor(c), () => []).add('$c');
    }
    final via = <String>{};
    var id = '';
    for (final p in parts) {
      for (final g in groups.entries) {
        final r = await router.sendTeamTo(teamId, type, p, now: now, members: g.value, fanOut: g.key, broadcast: false);
        id = r.id;
        via.addAll(r.via);
      }
    }
    if (id.isEmpty) id = toHex(randomBytes(8)); // nobody in the team yet
    await _db.into(_db.messages).insert(MessagesCompanion.insert(
          id: id,
          teamId: Value(teamId),
          outgoing: true,
          type: type,
          payload: whole,
          at: now,
          status: via.isEmpty ? 'failed' : 'sent',
          statusAt: Value(now),
          via: Value(via.isEmpty ? null : (via.toList()..sort()).join('+')),
        ));
  }

  // A clip's earlier parts have no row of their own: they hold back the row's "delivered"
  // and can fail it.
  final Map<String, String> _partOf = {}; // earlier part id → the row's id
  final Map<String, Set<String>> _partsLeft = {}; // row id → earlier parts not delivered yet
  final Set<String> _waitingForParts = {}; // rows whose last part is delivered already

  void _holdUntilAllParts(String row, List<String> earlier) {
    if (earlier.isEmpty) return;
    _partsLeft[row] = {...earlier};
    for (final p in earlier) {
      _partOf[p] = row;
      _latest.remove(p);
    }
  }

  /// An incoming voice or file part: a one-part message is complete at once; parts of a
  /// longer one wait in [VoiceParts] until the last arrives. Null when the message is not
  /// complete yet; else the payload for the message row.
  Future<Uint8List?> _part(int type, String from, bool team, String? sender, List<int> payload) async {
    // One part at a time: two last parts arriving together would both see the set complete
    // and show the message twice (seen on a slower phone)
    final before = _parts;
    final done = Completer<void>();
    _parts = done.future;
    await before;
    try {
      return await _partNow(type, from, team, sender, payload);
    } finally {
      done.complete();
    }
  }

  Future<void> _parts = Future.value();

  Future<Uint8List?> _partNow(int type, String from, bool team, String? sender, List<int> payload) async {
    final String id;
    final int index, count;
    try {
      if (type == MessageType.voice) {
        final p = VoicePart.decode(payload);
        if (p.count == 1) return Uint8List.fromList(payload);
        (id, index, count) = ('v:${p.clipHex}', p.index, p.count);
      } else {
        final p = FilePart.decode(payload);
        (id, index, count) = ('f:${p.fileHex}', p.index, p.count);
      }
    } on FormatException {
      return null;
    }
    final key = team ? 't:$from:${sender ?? ''}:$id' : 'c:$from:$id';
    await _db.into(_db.voiceParts).insertOnConflictUpdate(
        VoicePartsCompanion.insert(clip: key, idx: index, payload: Uint8List.fromList(payload), at: DateTime.now()));
    final rows = await (_db.select(_db.voiceParts)..where((t) => t.clip.equals(key))).get();
    if (rows.length < count) return null;
    final Uint8List whole;
    try {
      whole = type == MessageType.voice
          ? VoicePart.join([for (final r in rows) VoicePart.decode(r.payload)]).encode()
          : FilePart.join([for (final r in rows) FilePart.decode(r.payload)]);
      if (type == MessageType.file) Attachment.decode(whole); // only a real attachment shows
    } on Object {
      return null; // mixed or broken parts: wait for the rest (old ones are dropped at start)
    }
    await (_db.delete(_db.voiceParts)..where((t) => t.clip.equals(key))).go();
    return whole;
  }

  Future<void> approveSms(String messageId) =>
      router.approveSms(messageId, now: DateTime.now());

  Future<void> _onEvent(RouterEvent e) async {
    switch (e) {
      case MessageSent(:final id, :final via):
        await _status(id, 'sent', via);
      case MessageDelivered(:final id, :final via):
        await _status(id, 'delivered', via, terminal: true);
      case MessageWaiting(:final id):
        await _status(id, 'waiting', null);
      case ConfirmationNeeded(:final id):
        await _status(id, 'confirm', null);
      case MessageFailed(:final id):
        await _status(id, 'failed', null, terminal: true);
      case MessageReceived(:final from, :final team, :final message, :final via):
        if (message.type == MessageType.ack) return;
        if (message.type == MessageType.control) {
          if (!team) await _onControl(from, message.payload);
          return;
        }
        if (message.type == MessageType.call) {
          final id = int.tryParse(from);
          if (team || id == null) return;
          try {
            _callSignals.add((id, CallSignal.decode(message.payload)));
          } on FormatException {
            // not a call signal we understand
          }
          return;
        }
        final fp = message.senderFingerprint == null ? null : toHex(message.senderFingerprint!);
        var payload = Uint8List.fromList(message.payload);
        if (message.type == MessageType.voice || message.type == MessageType.file) {
          final whole = await _part(message.type, from, team, fp, payload);
          if (whole == null) return; // more parts to come
          payload = whole;
        }
        if (!inForeground) onUnseen?.call(++_unseen, team ? 't:$from' : 'c:$from');
        if (team && fp != null) {
          final writer = _contactByFingerprint[fp];
          if (writer != null) await addTeamMember(from, writer);
        }
        await _db.into(_db.messages).insertOnConflictUpdate(MessagesCompanion.insert(
              id: toHex(message.id),
              contactId: Value(team ? null : int.tryParse(from)),
              teamId: Value(team ? from : null),
              sender: Value(message.senderFingerprint == null
                  ? null
                  : toHex(message.senderFingerprint!)),
              outgoing: false,
              type: message.type,
              payload: payload,
              // Local receipt time: ordering by the sender's clock breaks with clock skew
              // (seen in the field: phone without network time ~11 min off)
              at: DateTime.now(),
              status: 'received',
              via: Value(via),
            ));
    }
  }

  Future<void> _status(String id, String status, String? via, {bool terminal = false}) async {
    final row = _partOf[id];
    if (row != null) {
      // An earlier part of a voice clip
      if (status == 'delivered' || status == 'failed') _partOf.remove(id);
      if (status == 'failed') return _status(row, 'failed', null, terminal: true);
      if (status == 'delivered') {
        final left = _partsLeft[row]?..remove(id);
        if (left != null && left.isEmpty) {
          _partsLeft.remove(row);
          if (_waitingForParts.remove(row)) await _status(row, 'delivered', via, terminal: true);
        }
      }
      return;
    }
    if (status == 'delivered' && (_partsLeft[id]?.isNotEmpty ?? false)) {
      _waitingForParts.add(id); // the last part is there, earlier ones are not yet
      return;
    }
    final prev = _latest[id];
    _latest[id] = (status, via ?? prev?.$2); // synchronously, before any await
    final updated = await _apply(id);
    if (terminal && updated > 0) _latest.remove(id);
  }

  Future<int> _apply(String id) async {
    final s = _latest[id];
    if (s == null) return 0;
    return (_db.update(_db.messages)..where((t) => t.id.equals(id))).write(MessagesCompanion(
      status: Value(s.$1),
      statusAt: Value(DateTime.now()),
      via: s.$2 == null ? const Value.absent() : Value(s.$2),
    ));
  }

  Future<void> dispose() async {
    _ticker?.cancel();
    await _callSignals.close();
    await _sub?.cancel();
    for (final t in _appTransports) {
      await t.close();
    }
    await _persistReplay();
  }
}
