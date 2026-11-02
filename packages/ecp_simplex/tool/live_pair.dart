/// Live check on a laptop: two simplex-chat CLIs (WebSocket servers on [port1], [port2]),
/// two ECP routers, one text each way over the real SimpleX network.
///   simplex-chat -d /tmp/a/db -p 5301 -y --user-display-name a   (and b on 5302), then
///   dart run tool/live_pair.dart 5301 5302
import 'dart:async';
import 'dart:io';

import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_simplex/ecp_simplex.dart';
import 'package:ecp_simplex/ws.dart';

Future<void> main(List<String> args) async {
  final ia = await EcpIdentity.generate(), ib = await EcpIdentity.generate();
  final ta = SimplexTransport(await WsSimplex.connect(int.parse(args[0])), ownKey: ia.publicKey);
  final tb = SimplexTransport(await WsSimplex.connect(int.parse(args[1])), ownKey: ib.publicKey);
  await ta.start();
  await tb.start();
  print('addresses:\n  ${ta.address}\n  ${tb.address}');

  Future<PaceRouter> router(EcpIdentity me, EcpIdentity peer, String name, SimplexTransport t) async {
    final keys = KeyRing(senderFingerprint: await senderFingerprint(me.publicKey));
    keys.pairs[name] = await derivePairKeys(me, peer.publicKey);
    final r = PaceRouter(transports: [t], keys: keys);
    t.onData = (env) => r.receive(t, env, now: DateTime.now());
    r.events.listen((e) => print('${DateTime.now().toIso8601String().substring(11, 19)} $name-side: $e'));
    return r;
  }

  final a = await router(ia, ib, 'bob', ta), b = await router(ib, ia, 'alice', tb);
  final t0 = DateTime.now();
  await ta.contactsChanged({'bob': ib.publicKey}, {'bob': tb.address!});
  await tb.contactsChanged({'alice': ia.publicKey}, {});
  while (!(ta.canReach('bob') && tb.canReach('alice'))) {
    if (DateTime.now().difference(t0).inSeconds > 120) {
      print('FAIL: not connected');
      exit(1);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  print('connected after ${DateTime.now().difference(t0).inSeconds} s');
  final delivered = Completer<void>(), back = Completer<void>();
  a.events.listen((e) => e is MessageDelivered && !delivered.isCompleted ? delivered.complete() : null);
  b.events.listen((e) => e is MessageDelivered && !back.isCompleted ? back.complete() : null);
  final t1 = DateTime.now();
  await a.send('bob', MessageType.text, encodeText('ahoj přes SimpleX'), now: DateTime.now());
  await delivered.future.timeout(const Duration(seconds: 60));
  print('A→B delivered with ACK in ${DateTime.now().difference(t1).inMilliseconds} ms');
  final t2 = DateTime.now();
  await b.send('alice', MessageType.text, encodeText('a zpět'), now: DateTime.now());
  await back.future.timeout(const Duration(seconds: 60));
  print('B→A delivered with ACK in ${DateTime.now().difference(t2).inMilliseconds} ms');
  exit(0);
}
