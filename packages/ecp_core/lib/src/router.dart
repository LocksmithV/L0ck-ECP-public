import 'dart:async';
import 'dart:typed_data';

import 'bytes.dart';
import 'envelope.dart';
import 'keys.dart';
import 'messages.dart';

/// PACE layers, most secure first (docs/ARCHITECTURE_V2.md §7).
enum PaceLayer { primary, alternate, contingency, emergency }

/// A channel the router pushes envelope bytes through. Implementations (SimpleX, Bramble,
/// Meshtastic, MeshCore, SMS, the squad net) live in the app; the router only sees this.
abstract class Transport {
  String get id;

  /// Null for the squad net, which runs beside PACE rather than inside it.
  PaceLayer? get layer;

  bool get isAvailable;

  /// Whether this channel has an address for the contact (a phone number, a node id…).
  bool canReach(String contactId);

  /// Hands the bytes to the channel. True means accepted, not delivered — delivery is the ACK.
  Future<bool> sendTo(String contactId, Uint8List data);

  /// Everyone in range (squad net, LoRa channel). False when the channel cannot broadcast.
  Future<bool> broadcast(Uint8List data) async => false;
}

class LayerPolicy {
  const LayerPolicy(this.ackTimeout, {this.needsConfirmation = false});

  final Duration ackTimeout;

  /// The user must approve using this layer (SMS outside an emergency).
  final bool needsConfirmation;
}

class PaceProfile {
  const PaceProfile(this.name, this.order, this.policy);

  final String name;
  final List<PaceLayer> order;
  final Map<PaceLayer, LayerPolicy> policy;

  /// Default for Evasion: SimpleX → Bramble/Tor → LoRa → SMS (only after confirmation).
  static const evasion = PaceProfile('evasion', [
    PaceLayer.primary,
    PaceLayer.alternate,
    PaceLayer.contingency,
    PaceLayer.emergency,
  ], {
    PaceLayer.primary: LayerPolicy(Duration(seconds: 60)),
    PaceLayer.alternate: LayerPolicy(Duration(seconds: 120)),
    PaceLayer.contingency: LayerPolicy(Duration(seconds: 90)),
    PaceLayer.emergency: LayerPolicy(Duration(seconds: 120), needsConfirmation: true),
  });
}

/// Keys the router may use; the app keeps it in sync with its contact list.
class KeyRing {
  KeyRing({required this.senderFingerprint});

  /// 2 bytes, used inside team envelopes.
  final Uint8List senderFingerprint;
  final Map<String, PairKeys> pairs = {};
  final Map<String, Uint8List> teams = {};

  List<KeyCandidate> candidates() => [
        for (final e in pairs.entries) KeyCandidate(EnvelopeKind.pair, e.value.recv, e.key),
        for (final e in teams.entries) KeyCandidate(EnvelopeKind.team, e.value, e.key),
      ];
}

enum OutboxState { sending, waiting, awaitingConfirmation }

/// A pair message in flight. Persisted so a restart does not lose or resend it blindly.
class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.contactId,
    required this.envelope,
    required this.createdAt,
    this.emergency = false,
    this.state = OutboxState.waiting,
    this.layerIndex = 0,
    this.deadline,
    this.smsApproved = false,
    List<String>? tried,
  }) : tried = tried ?? [];

  final String id;
  final String contactId;
  final Uint8List envelope;
  final DateTime createdAt;
  final bool emergency;
  OutboxState state;
  int layerIndex;
  DateTime? deadline;
  bool smsApproved;
  final List<String> tried;
}

abstract class OutboxStore {
  Future<void> put(OutboxEntry e);
  Future<void> remove(String id);
  Future<List<OutboxEntry>> loadAll();
}

class MemoryOutboxStore implements OutboxStore {
  final Map<String, OutboxEntry> entries = {};

  @override
  Future<void> put(OutboxEntry e) async => entries[e.id] = e;

  @override
  Future<void> remove(String id) async => entries.remove(id);

  @override
  Future<List<OutboxEntry>> loadAll() async => entries.values.toList();
}

sealed class RouterEvent {
  const RouterEvent();
}

class MessageReceived extends RouterEvent {
  const MessageReceived(this.from, this.team, this.message, this.via);

  /// Contact id, or team id when [team] is true.
  final String from;
  final bool team;
  final InnerMessage message;
  final String via;
}

class MessageSent extends RouterEvent {
  const MessageSent(this.id, this.layer, this.via);
  final String id;
  final PaceLayer? layer;
  final String via;
}

class MessageDelivered extends RouterEvent {
  const MessageDelivered(this.id, this.via);
  final String id;
  final String via;
}

/// SMS is next; the UI should ask the user (`approveSms`).
class ConfirmationNeeded extends RouterEvent {
  const ConfirmationNeeded(this.id, this.layer);
  final String id;
  final PaceLayer layer;
}

/// No channel reaches the contact right now; retried on [PaceRouter.availabilityChanged].
class MessageWaiting extends RouterEvent {
  const MessageWaiting(this.id);
  final String id;
}

class MessageFailed extends RouterEvent {
  const MessageFailed(this.id);
  final String id;
}

/// Picks the most secure available channel, escalates when no ACK arrives in time, floods all
/// channels in an emergency, and relays team messages across the squad net
/// (docs/ARCHITECTURE_V2.md §7). Time is passed in, never read, so it can be simulated.
class PaceRouter {
  PaceRouter({
    required this.transports,
    required this.keys,
    this.profile = PaceProfile.evasion,
    OutboxStore? store,
    ReplayGuard? replay,
    this.maxAge = const Duration(hours: 24),
    this.retryWhenStuck = const Duration(minutes: 10),
  })  : store = store ?? MemoryOutboxStore(),
        replay = replay ?? ReplayGuard();

  final List<Transport> transports;
  final KeyRing keys;

  /// Layer order and timeouts; the app lets the user reorder layers (settings). Messages in
  /// flight continue from their current position in the new order.
  PaceProfile profile;
  final OutboxStore store;
  final ReplayGuard replay;
  final Duration maxAge;
  final Duration retryWhenStuck;

  /// Hop limit for team messages on the squad net; incoming values are capped to this, since
  /// the TTL byte sits outside the authenticated envelope.
  static const maxSquadTtl = 4;

  final _events = StreamController<RouterEvent>.broadcast(sync: true);
  final Map<String, OutboxEntry> _outbox = {};

  Stream<RouterEvent> get events => _events.stream;

  Iterable<OutboxEntry> get outbox => _outbox.values;

  /// Reloads in-flight messages after a restart.
  Future<void> restore() async {
    for (final e in await store.loadAll()) {
      _outbox[e.id] = e;
    }
  }

  // --- sending ---

  /// Sends to one contact with ACK. Returns the message id (hex).
  Future<String> send(
    String contactId,
    int type,
    List<int> payload, {
    bool emergency = false,
    required DateTime now,
  }) async {
    final pair = keys.pairs[contactId];
    if (pair == null) throw ArgumentError('no keys for contact $contactId');
    final msg = InnerMessage.create(
      type: type,
      payload: payload,
      flags: MessageFlags.ackRequested | (emergency ? MessageFlags.priority : 0),
      now: now,
    );
    final entry = OutboxEntry(
      id: toHex(msg.id),
      contactId: contactId,
      envelope: await EcpEnvelope.seal(
          kind: EnvelopeKind.pair, key: pair.send, message: msg, now: now),
      createdAt: now,
      emergency: emergency,
    );
    _outbox[entry.id] = entry;
    await _advance(entry, now);
    return entry.id;
  }

  /// One try on the first available layer of [layers] (in PACE order), no ACK, no outbox.
  /// For cheap extras that must never escalate to LoRa or SMS — read receipts. Returns the
  /// transport id used, or null.
  Future<String?> sendOnce(String contactId, int type, List<int> payload,
      {required Set<PaceLayer> layers, required DateTime now}) async {
    final pair = keys.pairs[contactId];
    if (pair == null) throw ArgumentError('no keys for contact $contactId');
    final msg = InnerMessage.create(type: type, payload: payload, now: now);
    final env = await EcpEnvelope.seal(kind: EnvelopeKind.pair, key: pair.send, message: msg, now: now);
    for (final layer in profile.order.where(layers.contains)) {
      for (final t in transports.where((t) => t.layer == layer)) {
        if (t.isAvailable && t.canReach(contactId) && await t.sendTo(contactId, env)) return t.id;
      }
    }
    return null;
  }

  /// Team message: squad net broadcast plus every channel that can broadcast (LoRa).
  /// No ACK — receipt is confirmed by members' replies, not per message.
  Future<String> sendTeam(String teamId, int type, List<int> payload,
          {required DateTime now}) async =>
      (await sendTeamTo(teamId, type, payload, now: now)).id;

  /// As [sendTeam], and the same envelope also goes to each of [members] (contact ids) over
  /// the first available of [fanOut] — store-and-forward channels, so members out of radio
  /// range get it too. Duplicates are dropped by id at the receiver. Returns the message id
  /// and the transports used.
  Future<({String id, Set<String> via})> sendTeamTo(String teamId, int type, List<int> payload,
      {required DateTime now,
      Iterable<String> members = const [],
      Set<PaceLayer> fanOut = const {PaceLayer.primary, PaceLayer.alternate}}) async {
    final key = keys.teams[teamId];
    if (key == null) throw ArgumentError('no key for team $teamId');
    final msg = InnerMessage.create(
        type: type, payload: payload, senderFingerprint: keys.senderFingerprint, now: now);
    final env =
        await EcpEnvelope.seal(kind: EnvelopeKind.team, key: key, message: msg, now: now);
    replay.accept(msg, now: now); // our own echo coming back must not be relayed again
    final via = <String>{};
    for (final t in transports.where((t) => t.isAvailable)) {
      final ok = t.layer == null
          ? await t.broadcast(_squadFrame(maxSquadTtl, env))
          : await t.broadcast(env);
      if (ok) via.add(t.id);
    }
    for (final m in members) {
      member:
      for (final layer in profile.order.where(fanOut.contains)) {
        for (final t in transports.where((t) => t.layer == layer)) {
          if (t.isAvailable && t.canReach(m) && await t.sendTo(m, env)) {
            via.add(t.id);
            break member;
          }
        }
      }
    }
    return (id: toHex(msg.id), via: via);
  }

  /// The user agreed to fall back to SMS for this message.
  Future<void> approveSms(String id, {required DateTime now}) async {
    final e = _outbox[id];
    if (e == null || e.state != OutboxState.awaitingConfirmation) return;
    e.smsApproved = true;
    await _advance(e, now);
  }

  /// Call periodically (a few seconds) and after restarts.
  Future<void> tick(DateTime now) async {
    for (final e in _outbox.values.toList()) {
      if (now.difference(e.createdAt) > maxAge) {
        await _finish(e);
        _events.add(MessageFailed(e.id));
        continue;
      }
      final deadline = e.deadline;
      if (deadline == null || now.isBefore(deadline)) continue;
      if (e.state == OutboxState.sending) {
        if (!e.emergency) e.layerIndex++; // no ACK in time: next layer
        await _advance(e, now);
      } else if (e.state == OutboxState.waiting) {
        e.layerIndex = 0;
        await _advance(e, now);
      }
    }
  }

  /// A channel came up or went down: waiting messages try again from the most secure layer.
  Future<void> availabilityChanged(DateTime now) async {
    for (final e in _outbox.values.where((e) => e.state == OutboxState.waiting).toList()) {
      e.layerIndex = 0;
      await _advance(e, now);
    }
  }

  Future<void> _advance(OutboxEntry e, DateTime now) async {
    if (e.emergency) return _flood(e, now);
    final order = profile.order;
    for (var i = e.layerIndex; i < order.length; i++) {
      final layer = order[i];
      final candidates = transports
          .where((t) => t.layer == layer && t.isAvailable && t.canReach(e.contactId))
          .toList();
      if (candidates.isEmpty) continue;
      final policy = profile.policy[layer]!;
      if (policy.needsConfirmation && !e.smsApproved) {
        e
          ..state = OutboxState.awaitingConfirmation
          ..layerIndex = i
          ..deadline = null;
        await store.put(e);
        _events.add(ConfirmationNeeded(e.id, layer));
        return;
      }
      for (final t in candidates) {
        if (await t.sendTo(e.contactId, e.envelope)) {
          e
            ..state = OutboxState.sending
            ..layerIndex = i
            ..deadline = now.add(policy.ackTimeout)
            ..tried.add(t.id);
          await store.put(e);
          _events.add(MessageSent(e.id, layer, t.id));
          return;
        }
      }
    }
    // Nothing reachable on any remaining layer: wait for a channel, then start from the top
    e
      ..state = OutboxState.waiting
      ..layerIndex = 0
      ..deadline = now.add(retryWhenStuck);
    await store.put(e);
    _events.add(MessageWaiting(e.id));
  }

  /// Emergency: every channel that reaches the contact at once, SMS included, repeated each
  /// timeout until an ACK arrives.
  Future<void> _flood(OutboxEntry e, DateTime now) async {
    var any = false;
    for (final t in transports.where((t) => t.layer != null)) {
      if (!t.isAvailable || !t.canReach(e.contactId)) continue;
      if (await t.sendTo(e.contactId, e.envelope)) {
        any = true;
        e.tried.add(t.id);
        _events.add(MessageSent(e.id, t.layer, t.id));
      }
    }
    final longest = profile.policy.values
        .map((p) => p.ackTimeout)
        .reduce((a, b) => a > b ? a : b);
    e
      ..state = any ? OutboxState.sending : OutboxState.waiting
      ..deadline = now.add(any ? longest : retryWhenStuck);
    await store.put(e);
    if (!any) _events.add(MessageWaiting(e.id));
  }

  Future<void> _finish(OutboxEntry e) async {
    _outbox.remove(e.id);
    await store.remove(e.id);
  }

  // --- receiving ---

  /// Bytes from a channel. [via] tells the router which transport, and whether this is a
  /// squad-net frame (layer null) that may need relaying.
  Future<void> receive(Transport via, List<int> data, {required DateTime now}) async {
    var envelope = Uint8List.fromList(data);
    var ttl = 0;
    if (via.layer == null) {
      if (envelope.isEmpty) return;
      ttl = envelope[0] > maxSquadTtl ? maxSquadTtl : envelope[0];
      envelope = Uint8List.sublistView(envelope, 1);
    }
    final opened = await EcpEnvelope.open(envelope, keys.candidates(), now: now);
    if (opened == null) return; // not for us, forged or stale
    final m = opened.message;
    final from = opened.via.owner as String;
    final team = opened.via.kind == EnvelopeKind.team;

    final age = (m.sentAt - ecpTime(now)).abs();
    if (age > replay.window.inSeconds) return;
    final fresh = replay.accept(m, now: now);

    if (!fresh) {
      // A duplicate means our ACK may have been lost: confirm again, deliver nothing new
      if (!team && m.wantsAck && m.type != MessageType.ack) await _ack(from, m, via, now);
      return;
    }

    if (team && via.layer == null && ttl > 1) {
      final frame = _squadFrame(ttl - 1, envelope);
      for (final t in transports.where((t) => t.layer == null && t.isAvailable)) {
        await t.broadcast(frame);
      }
    }

    if (!team && m.type == MessageType.ack) {
      final id = toHex(decodeAck(m.payload));
      final e = _outbox[id];
      if (e != null && e.contactId == from) {
        await _finish(e);
        _events.add(MessageDelivered(id, via.id));
      }
      return;
    }

    _events.add(MessageReceived(from, team, m, via.id));
    if (!team && m.wantsAck) await _ack(from, m, via, now);
  }

  /// ACK back the way the message came; if that channel refuses, the most secure one that
  /// reaches the sender. ACKs are not themselves acknowledged or escalated.
  Future<void> _ack(String contactId, InnerMessage m, Transport via, DateTime now) async {
    final pair = keys.pairs[contactId];
    if (pair == null) return;
    final ack = await EcpEnvelope.seal(
      kind: EnvelopeKind.pair,
      key: pair.send,
      message: InnerMessage.create(
          type: MessageType.ack, payload: encodeAck(m.id), now: now),
      now: now,
    );
    if (via.layer != null && via.canReach(contactId) && await via.sendTo(contactId, ack)) {
      return;
    }
    for (final layer in profile.order.where((l) => l != PaceLayer.emergency)) {
      for (final t in transports.where(
          (t) => t.layer == layer && t.isAvailable && t.canReach(contactId))) {
        if (await t.sendTo(contactId, ack)) return;
      }
    }
  }

  static Uint8List _squadFrame(int ttl, List<int> envelope) =>
      Uint8List.fromList([ttl, ...envelope]);

  Future<void> dispose() => _events.close();
}
