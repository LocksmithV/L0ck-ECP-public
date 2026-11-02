import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ecp_core/ecp_core.dart';

import 'client.dart';
import 'frames.dart';

/// PACE layer C: ECP envelopes as MeshCore channel datagrams, flooded over the mesh
/// (docs/ARCHITECTURE_V2.md §7). No MeshCore contacts and no adverts are needed: whoever is
/// on the ECP channel hears the datagram, and only the addressee's keys open the envelope.
/// Any repeater relays the flood, ECP or not. Everything else on the radio — the public
/// channel, hashtag channels, MeshCore text messages — is ignored.
class MeshCoreTransport extends Transport {
  MeshCoreTransport({List<int>? channelSecret})
      : _secret = channelSecret ?? defaultChannelSecret;

  /// Application id inside MeshCore (testing range FF00–FFFF until registered).
  static const dataType = 0xFFEC;
  static const channelName = 'ecp';

  /// One well-known channel for all ECP users: it only hides ECP from casual MeshCore
  /// listeners, confidentiality comes from the envelope. A group can switch to its own
  /// private channel ([setChannelSecret]); then only its members' radios even pass the
  /// datagrams on to their apps.
  static final defaultChannelSecret =
      Uint8List.fromList(sha256.convert(utf8.encode('L0ck-ECP v1 lora channel')).bytes.sublist(0, 16));

  List<int> _secret;

  List<int> get secret => _secret;

  bool get isDefaultChannel => _eq(_secret, defaultChannelSecret);

  /// Moves to another channel key, rewriting the radio's ECP slot if one is attached.
  Future<void> setChannelSecret(List<int> secret) async {
    if (secret.length != 16) throw ArgumentError('channel secret must be 16 bytes');
    _secret = List.unmodifiable(secret);
    final c = _client, d = deviceInfo;
    if (c == null || d == null) return;
    _channel = await c.ensureChannel(channelName, _secret, d.maxChannels);
    onChanged?.call();
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  CompanionClient? _client;
  int? _channel;
  StreamSubscription<ChannelData>? _sub;
  Timer? _poll;

  SelfInfo? selfInfo;
  DeviceInfo? deviceInfo;

  /// Set by whoever owns the router.
  void Function(Uint8List envelope, ChannelData meta)? onData;
  void Function()? onChanged;

  @override
  String get id => 'meshcore';

  @override
  PaceLayer? get layer => PaceLayer.contingency;

  /// Takes over a connected radio: handshake, ECP channel slot, then listening.
  Future<void> attach(CompanionClient client) async {
    await detach();
    final (self, dev) = await client.start();
    final ch = await client.ensureChannel(channelName, _secret, dev.maxChannels);
    selfInfo = self;
    deviceInfo = dev;
    _client = client;
    _channel = ch;
    _sub = client.channelData.listen((d) {
      if (d.channel == _channel && d.dataType == dataType) onData?.call(d.payload, d);
    });
    // The radio pushes "messages waiting", but a missed push must not strand a message
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => client.drain().ignore());
    onChanged?.call();
  }

  /// The radio went away (BLE dropped, cable pulled).
  Future<void> detach() async {
    _poll?.cancel();
    await _sub?.cancel();
    final had = _client != null;
    _client = null;
    _channel = null;
    if (had) onChanged?.call();
  }

  @override
  bool get isAvailable => _client != null && _channel != null;

  /// A flood reaches whoever is in range; whether the contact is, only the ACK tells.
  @override
  bool canReach(String contactId) => isAvailable;

  @override
  Future<bool> sendTo(String contactId, Uint8List data) => _send(data);

  @override
  Future<bool> broadcast(Uint8List data) => _send(data);

  Future<bool> _send(Uint8List data) async {
    final c = _client, ch = _channel;
    if (c == null || ch == null || data.length > maxChannelData) return false;
    try {
      await c.sendData(ch, dataType, data);
      return true;
    } catch (_) {
      return false;
    }
  }
}
