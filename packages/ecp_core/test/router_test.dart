import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

/// Simulated network: transports queue deliveries, the test pumps them, and time only moves
/// when the test says so.
class Net {
  final Map<String, Node> nodes = {};
  final List<(String to, String transport, Uint8List data)> queue = [];

  Future<void> pump(DateTime now) async {
    while (queue.isNotEmpty) {
      final (to, tid, data) = queue.removeAt(0);
      final node = nodes[to]!;
      await node.router.receive(node.transport(tid), data, now: now);
    }
  }
}

class FakeTransport extends Transport {
  FakeTransport(this.id, this.layer, this.net, this.owner);

  @override
  final String id;
  @override
  final PaceLayer? layer;
  final Net net;
  final String owner;

  bool available = true;

  /// Accepts the send but the bytes never arrive (a dead relay, a lost LoRa packet).
  bool lossy = false;

  /// contactId (as known by [owner]) → node name of that contact.
  final Map<String, String> reach = {};

  /// Squad net: who is in radio range of [owner].
  final Set<String> neighbors = {};

  int sends = 0;

  @override
  bool get isAvailable => available;

  @override
  bool canReach(String contactId) => reach.containsKey(contactId);

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async {
    if (!available || !canReach(contactId)) return false;
    sends++;
    if (!lossy) net.queue.add((reach[contactId]!, id, data));
    return true;
  }

  @override
  Future<bool> broadcast(Uint8List data) async {
    if (!available) return false;
    sends++;
    if (!lossy) {
      for (final n in neighbors) {
        net.queue.add((n, id, data));
      }
    }
    return true;
  }
}

class Node {
  Node(this.name, this.router, this.transports);

  final String name;
  final PaceRouter router;
  final Map<String, FakeTransport> transports;
  final List<RouterEvent> events = [];

  FakeTransport transport(String id) => transports[id]!;

  List<MessageReceived> get received => events.whereType<MessageReceived>().toList();
}

const pace = {
  'simplex': PaceLayer.primary,
  'bramble': PaceLayer.alternate,
  'lora': PaceLayer.contingency,
  'sms': PaceLayer.emergency,
  'squad': null,
};

void main() {
  final t0 = DateTime.utc(2026, 11, 2, 10);
  late Net net;
  late Node alice, bob;

  Future<Node> node(String name, EcpIdentity id) async {
    final keys = KeyRing(senderFingerprint: await senderFingerprint(id.publicKey));
    final ts = {for (final e in pace.entries) e.key: FakeTransport(e.key, e.value, net, name)};
    final n = Node(name, PaceRouter(transports: ts.values.toList(), keys: keys), ts);
    n.router.events.listen(n.events.add);
    net.nodes[name] = n;
    return n;
  }

  Future<void> befriend(Node a, EcpIdentity ia, Node b, EcpIdentity ib) async {
    a.router.keys.pairs[b.name] = await derivePairKeys(ia, ib.publicKey);
    b.router.keys.pairs[a.name] = await derivePairKeys(ib, ia.publicKey);
    for (final id in ['simplex', 'bramble', 'lora', 'sms']) {
      a.transport(id).reach[b.name] = b.name;
      b.transport(id).reach[a.name] = a.name;
    }
  }

  setUp(() async {
    net = Net();
    final ia = await EcpIdentity.generate();
    final ib = await EcpIdentity.generate();
    alice = await node('alice', ia);
    bob = await node('bob', ib);
    await befriend(alice, ia, bob, ib);
  });

  List<PaceLayer?> sentLayers(Node n) =>
      n.events.whereType<MessageSent>().map((e) => e.layer).toList();

  Future<String> sendText(String s, {bool emergency = false, DateTime? at}) => alice.router
      .send('bob', MessageType.text, encodeText(s), emergency: emergency, now: at ?? t0);

  test('primary works: delivered over SimpleX, ACK closes it', () async {
    final id = await sendText('hello');
    await net.pump(t0);
    expect(bob.received.single.from, 'alice');
    expect(decodeText(bob.received.single.message.payload), 'hello');
    expect(alice.events.whereType<MessageDelivered>().single.id, id);
    expect(alice.router.outbox, isEmpty);
    expect(sentLayers(alice), [PaceLayer.primary]);
  });

  test('no ACK in time: escalates P → A', () async {
    alice.transport('simplex').lossy = true;
    final id = await sendText('escalate');
    await net.pump(t0);
    expect(bob.received, isEmpty);
    await alice.router.tick(t0.add(const Duration(seconds: 59)));
    expect(sentLayers(alice), [PaceLayer.primary], reason: 'not before the timeout');
    final later = t0.add(const Duration(seconds: 61));
    await alice.router.tick(later);
    await net.pump(later);
    expect(sentLayers(alice), [PaceLayer.primary, PaceLayer.alternate]);
    expect(alice.events.whereType<MessageDelivered>().single.via, 'bramble');
    expect(alice.events.whereType<MessageDelivered>().single.id, id);
  });

  test('unavailable layers are skipped straight to LoRa', () async {
    alice.transport('simplex').available = false;
    alice.transport('bramble').available = false;
    await sendText('off-grid');
    await net.pump(t0);
    expect(sentLayers(alice), [PaceLayer.contingency]);
    expect(bob.received.single.via, 'lora');
  });

  test('the channel waiting for an ACK goes down: next layer at once, not at the timeout', () async {
    alice.transport('simplex').lossy = true; // handed over, but the internet is already gone
    await sendText('now');
    await net.pump(t0);
    expect(sentLayers(alice), [PaceLayer.primary]);
    alice.transport('simplex').available = false;
    final soon = t0.add(const Duration(seconds: 2));
    await alice.router.availabilityChanged(soon);
    await net.pump(soon);
    expect(sentLayers(alice), [PaceLayer.primary, PaceLayer.alternate]);
    expect(bob.received.single.via, 'bramble');
  });

  test('only SMS left: the approval is asked for at once, with no ACK waits', () async {
    for (final id in ['simplex', 'bramble', 'lora']) {
      alice.transport(id).available = false;
    }
    final id = await sendText('sms only');
    expect(alice.events.whereType<ConfirmationNeeded>().single.id, id);
    expect(sentLayers(alice), isEmpty);
  });

  test('SMS only after the user approves it', () async {
    for (final id in ['simplex', 'bramble', 'lora']) {
      alice.transport(id).available = false;
    }
    final msg = await sendText('last resort');
    expect(alice.events.whereType<ConfirmationNeeded>().single.id, msg);
    expect(alice.transport('sms').sends, 0);
    await alice.router.approveSms(msg, now: t0);
    await net.pump(t0);
    expect(alice.transport('sms').sends, 1);
    expect(alice.events.whereType<MessageDelivered>().single.via, 'sms');
  });

  test('nothing reachable: waits, then sends on the most secure layer that comes up', () async {
    for (final t in alice.transports.values) {
      t.available = false;
    }
    await sendText('later');
    expect(alice.events.last, isA<MessageWaiting>());
    alice.transport('bramble').available = true;
    await alice.router.availabilityChanged(t0.add(const Duration(minutes: 1)));
    await net.pump(t0);
    expect(sentLayers(alice), [PaceLayer.alternate]);
    expect(bob.received, hasLength(1));
  });

  test('lost ACK: duplicate is not delivered twice but is acknowledged again', () async {
    bob.transport('simplex').lossy = true; // Bob's ACK back over SimpleX gets lost
    await sendText('dup');
    await net.pump(t0);
    expect(bob.received, hasLength(1));
    expect(alice.events.whereType<MessageDelivered>(), isEmpty);
    final later = t0.add(const Duration(seconds: 61));
    await alice.router.tick(later); // escalates to Bramble, Bob sees it again
    await net.pump(later);
    expect(bob.received, hasLength(1), reason: 'no second delivery to the UI');
    expect(alice.events.whereType<MessageDelivered>().single.via, 'bramble');
  });

  test('emergency floods every channel at once, SMS included, without asking', () async {
    await sendText('HELP', emergency: true);
    expect(alice.events.whereType<ConfirmationNeeded>(), isEmpty);
    expect(
        sentLayers(alice).toSet(),
        {PaceLayer.primary, PaceLayer.alternate, PaceLayer.contingency, PaceLayer.emergency});
    await net.pump(t0);
    expect(bob.received, hasLength(1), reason: 'four copies, one delivery');
    expect(alice.events.whereType<MessageDelivered>(), hasLength(1));
  });

  test('gives up after maxAge', () async {
    for (final t in alice.transports.values) {
      t.available = false;
    }
    final id = await sendText('too late');
    await alice.router.tick(t0.add(const Duration(hours: 25)));
    expect(alice.events.whereType<MessageFailed>().single.id, id);
    expect(alice.router.outbox, isEmpty);
  });

  test('an in-flight message survives a restart', () async {
    final store = MemoryOutboxStore();
    final keys = alice.router.keys;
    final r1 = PaceRouter(
        transports: alice.transports.values.toList(), keys: keys, store: store);
    alice.transport('simplex').lossy = true;
    await r1.send('bob', MessageType.text, encodeText('persist'), now: t0);
    final r2 = PaceRouter(
        transports: alice.transports.values.toList(), keys: keys, store: store);
    final events = <RouterEvent>[];
    r2.events.listen(events.add);
    await r2.restore();
    expect(r2.outbox, hasLength(1));
    await r2.tick(t0.add(const Duration(seconds: 61)));
    expect(events.whereType<MessageSent>().single.layer, PaceLayer.alternate);
  });

  test('ACK from a different contact does not close the message', () async {
    final ic = await EcpIdentity.generate();
    final carol = await node('carol', ic);
    final ia = await EcpIdentity.generate(); // alice's identity is not kept; rebuild pair
    alice.router.keys.pairs['carol'] = await derivePairKeys(ia, ic.publicKey);
    carol.router.keys.pairs['alice'] = await derivePairKeys(ic, ia.publicKey);
    alice.transport('simplex').lossy = true;
    final id = await sendText('for bob only');
    // Carol forges an ACK for Bob's message id
    final fake = await EcpEnvelope.seal(
      kind: EnvelopeKind.pair,
      key: carol.router.keys.pairs['alice']!.send,
      message: InnerMessage.create(
          type: MessageType.ack, payload: fromHex(id), now: t0),
      now: t0,
    );
    await alice.router.receive(alice.transport('simplex'), fake, now: t0);
    expect(alice.events.whereType<MessageDelivered>(), isEmpty);
    expect(alice.router.outbox, hasLength(1));
  });

  group('squad net (outside PACE)', () {
    late Node a, b, c;

    setUp(() async {
      net = Net();
      final team = randomBytes(32);
      Future<Node> member(String n) async {
        final m = await node(n, await EcpIdentity.generate());
        m.router.keys.teams['T1'] = team;
        return m;
      }

      a = await member('a');
      b = await member('b');
      c = await member('c');
      // A line: a ↔ b ↔ c; a and c are out of range of each other
      a.transport('squad').neighbors.add('b');
      b.transport('squad').neighbors.addAll(['a', 'c']);
      c.transport('squad').neighbors.add('b');
      for (final n in [a, b, c]) {
        for (final id in ['simplex', 'bramble', 'lora', 'sms']) {
          n.transport(id).available = false;
        }
      }
    });

    test('a team order hops a → b → c, once each, no echo storm', () async {
      await a.router.sendTeam('T1', MessageType.report,
          const StatusReport(StatusCode.moving).encode(), now: t0);
      await net.pump(t0);
      expect(b.received.single.team, isTrue);
      expect(c.received.single.from, 'T1', reason: 'reached c through b');
      expect(a.received, isEmpty, reason: 'own message echoed back is ignored');
      expect(b.received, hasLength(1));
      expect(net.queue, isEmpty);
    });

    test('hop limit: an inflated TTL is capped', () async {
      // Build a frame claiming TTL 200; the router must not trust it beyond maxSquadTtl
      final env = await EcpEnvelope.seal(
        kind: EnvelopeKind.team,
        key: a.router.keys.teams['T1']!,
        message: InnerMessage.create(
            type: MessageType.text,
            payload: encodeText('x'),
            senderFingerprint: a.router.keys.senderFingerprint,
            now: t0),
        now: t0,
      );
      await b.router.receive(b.transport('squad'), [200, ...env], now: t0);
      final relayed = net.queue.where((q) => q.$2 == 'squad').map((q) => q.$3[0]).toSet();
      expect(relayed, {PaceRouter.maxSquadTtl - 1});
    });
  });

  test('sendOnce: one try on the allowed layers, never LoRa or SMS, no ACK', () async {
    alice.transport('simplex').available = false;
    alice.transport('bramble').available = false;
    final via = await alice.router.sendOnce('bob', MessageType.control, [2, 1],
        layers: {PaceLayer.primary, PaceLayer.alternate}, now: t0);
    expect(via, isNull);
    expect(alice.transport('lora').sends, 0);
    expect(alice.transport('sms').sends, 0);
    alice.transport('bramble').available = true;
    expect(
        await alice.router.sendOnce('bob', MessageType.control, [2, 1],
            layers: {PaceLayer.primary, PaceLayer.alternate}, now: t0),
        'bramble');
    await net.pump(t0);
    expect(bob.received.single.message.type, MessageType.control);
    expect(alice.router.outbox, isEmpty);
  });

  test('reordered PACE: LoRa before Tor', () async {
    alice.router.profile = PaceProfile('custom', [
      PaceLayer.primary,
      PaceLayer.contingency,
      PaceLayer.alternate,
      PaceLayer.emergency,
    ], PaceProfile.evasion.policy);
    alice.transport('simplex').available = false;
    await sendText('lora first');
    expect(sentLayers(alice), [PaceLayer.contingency]);
  });

  test('team fan-out: a member out of radio range gets it over P/A', () async {
    final team = randomBytes(32);
    alice.router.keys.teams['T'] = team;
    bob.router.keys.teams['T'] = team;
    alice.transport('lora').available = false; // nobody on the air, no squad neighbours
    final r = await alice.router.sendTeamTo('T', MessageType.text, encodeText('k mostu'),
        now: t0, members: ['bob']);
    expect(r.via, contains('simplex'), reason: 'fan-out over P (the fakes also broadcast)');
    await net.pump(t0);
    expect(bob.received.single.team, isTrue);
    expect(decodeText(bob.received.single.message.payload), 'k mostu');
  });
}
