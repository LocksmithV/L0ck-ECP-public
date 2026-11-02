import 'dart:async';
import 'dart:convert';

import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_simplex/ecp_simplex.dart';
import 'package:test/test.dart';

/// Pretend SimpleX network: users have addresses; `/connect <address>` makes both sides
/// contacts (auto-accept), and `/_send` delivers a text as a `newChatItems` event.
class FakeNet {
  final Map<String, FakeSimplex> byAddress = {};
}

class FakeSimplex implements SimplexApi {
  FakeSimplex(this.net);

  final FakeNet net;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? user;
  String? address;
  final Map<int, (String name, FakeSimplex peer)> contacts = {};
  final List<String> sent = [];

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  Map<String, dynamic> _contact(int id) => {
        'contactId': id,
        'profile': {'displayName': contacts[id]!.$1},
        'activeConn': {'connId': id},
        'contactStatus': 'active',
      };

  int _add(FakeSimplex peer) {
    final id = contacts.length + 1;
    contacts[id] = (peer.user!['profile']['displayName'] as String, peer);
    return id;
  }

  void inject(Map<String, dynamic> e) => scheduleMicrotask(() => _events.add(e));

  @override
  Future<Map<String, dynamic>> cmd(String c) async {
    sent.add(c);
    final arg = c.contains(' ') ? c.substring(c.indexOf(' ') + 1) : '';
    switch (c.split(' ').first) {
      case '/user':
        if (user == null) throw SimplexError(c, 'noActiveUser');
        return {'type': 'activeUser', 'user': user};
      case '/_create':
        final p = jsonDecode(arg.substring('user '.length)) as Map<String, dynamic>;
        user = {'userId': 1, 'profile': p['profile']};
        return {'type': 'activeUser', 'user': user};
      case '/_start':
        return {'type': 'chatStarted'};
      case '/_show_address':
        if (address == null) throw SimplexError(c, 'noAddress');
        return {'type': 'userContactLink', 'contactLink': {'connLinkContact': {'connFullLink': address}}};
      case '/_address':
        address = 'https://smp.example/a#${user!['profile']['displayName']}';
        net.byAddress[address!] = this;
        return {'type': 'userContactLinkCreated', 'connLinkContact': {'connFullLink': address, 'connShortLink': address}};
      case '/_address_settings':
        return {'type': 'userContactLinkUpdated'};
      case '/_contacts':
        return {'type': 'contactsList', 'contacts': [for (final id in contacts.keys) _contact(id)]};
      case '/connect':
        final peer = net.byAddress[arg]!;
        final mine = _add(peer), theirs = peer._add(this);
        inject({'type': 'contactConnected', 'contact': _contact(mine)});
        peer.inject({'type': 'contactConnected', 'contact': peer._contact(theirs)});
        return {'type': 'sentInvitation'};
      case '/_send':
        final id = int.parse(c.split(' ')[1].substring(1));
        final msgs = jsonDecode(c.substring(c.indexOf(' json ') + 6)) as List;
        final (_, peer) = contacts[id]!;
        final back = peer.contacts.entries.firstWhere((e) => e.value.$2 == this).key;
        for (final m in msgs) {
          peer.inject({
            'type': 'newChatItems',
            'chatItems': [
              {
                'chatInfo': {'type': 'direct', 'contact': peer._contact(back)},
                'chatItem': {
                  'chatDir': {'type': 'directRcv'},
                  'content': {'type': 'rcvMsgContent', 'msgContent': m['msgContent']},
                },
              }
            ],
          });
        }
        return {'type': 'newChatItems', 'chatItems': []};
    }
    throw SimplexError(c, 'unsupported in fake');
  }

  @override
  Future<void> close() => _events.close();
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  test('profile names come from the ECP key and do not reveal it', () {
    final k = List.generate(32, (i) => i);
    final n = SimplexTransport.profileName(k);
    expect(n, matches(RegExp(r'^ecp-[0-9a-f]{16}$')));
    expect(n, SimplexTransport.profileName(List.of(k)));
  });

  test('first start creates the profile and an auto-accepting address; restart reuses them',
      () async {
    final api = FakeSimplex(FakeNet());
    final t = SimplexTransport(api, ownKey: List.filled(32, 1));
    await t.start();
    expect(t.address, startsWith('https://'));
    expect(api.sent.where((c) => c.startsWith('/_address_settings')).single, contains('autoAccept'));
    final t2 = SimplexTransport(api, ownKey: List.filled(32, 1));
    await t2.start();
    expect(t2.address, t.address);
    expect(api.sent.where((c) => c.startsWith('/_create')), hasLength(1));
  });

  group('two routers over SimpleX', () {
    late PaceRouter alice, bob;
    late SimplexTransport ta, tb;
    late FakeSimplex sa;
    final got = <String>[], delivered = <String>[];

    setUp(() async {
      got.clear();
      delivered.clear();
      final net = FakeNet();
      final ia = await EcpIdentity.generate(), ib = await EcpIdentity.generate();
      sa = FakeSimplex(net);
      ta = SimplexTransport(sa, ownKey: ia.publicKey);
      tb = SimplexTransport(FakeSimplex(net), ownKey: ib.publicKey);
      await ta.start();
      await tb.start();
      Future<PaceRouter> router(EcpIdentity me, EcpIdentity peer, String name, SimplexTransport t) async {
        final keys = KeyRing(senderFingerprint: await senderFingerprint(me.publicKey));
        keys.pairs[name] = await derivePairKeys(me, peer.publicKey);
        final r = PaceRouter(transports: [t], keys: keys);
        t.onData = (env) => r.receive(t, env, now: DateTime.now());
        return r;
      }

      alice = await router(ia, ib, 'bob', ta);
      bob = await router(ib, ia, 'alice', tb);
      bob.events.listen((e) {
        if (e is MessageReceived && e.message.type == MessageType.text) {
          got.add(decodeText(e.message.payload));
        }
      });
      alice.events.listen((e) {
        if (e is MessageDelivered) delivered.add(e.via);
      });
      // Cards swapped in person: alice connects to bob's address (one side is enough)
      await ta.contactsChanged({'bob': ib.publicKey}, {'bob': tb.address!});
      await tb.contactsChanged({'alice': ia.publicKey}, {});
      await settle();
    });

    test('contacts are matched by profile name, and a text and its ACK go over P', () async {
      expect(ta.canReach('bob'), isTrue);
      expect(tb.canReach('alice'), isTrue, reason: 'learned from the incoming connection');
      await alice.send('bob', MessageType.text, encodeText('přes SimpleX'), now: DateTime.now());
      await settle();
      expect(got, ['přes SimpleX']);
      expect(delivered, ['simplex']);
    });

    test('connecting is asked once, not on every contact list change', () async {
      await ta.contactsChanged({'bob': List.filled(32, 9)}, {'bob': tb.address!});
      expect(sa.sent.where((c) => c.startsWith('/connect')), hasLength(1));
    });

    test('ordinary SimpleX texts and other chats are ignored', () async {
      var envelopes = 0;
      tb.onData = (_) => envelopes++;
      final b = tb.api as FakeSimplex;
      b.inject({
        'type': 'newChatItems',
        'chatItems': [
          {
            'chatInfo': {'type': 'direct'},
            'chatItem': {
              'chatDir': {'type': 'directRcv'},
              'content': {'type': 'rcvMsgContent', 'msgContent': {'type': 'text', 'text': 'ahoj'}},
            },
          },
          {
            'chatInfo': {'type': 'group'},
            'chatItem': {
              'chatDir': {'type': 'groupRcv'},
              'content': {'type': 'rcvMsgContent', 'msgContent': {'type': 'text', 'text': 'ecp1:AAAA'}},
            },
          },
        ],
      });
      await settle();
      expect(envelopes, 0);
    });
  });
}
