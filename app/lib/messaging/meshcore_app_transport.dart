import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_meshcore/ecp_meshcore.dart';

import '../data/database.dart';
import 'bramble_transport.dart';
import '../l10n/lang.dart';

/// Settings keys in the profile database.
const radioAddressKey = 'lora.radio';
const radioChannelKey = 'lora.channel';

/// Channel keys are passed between members as base64url (22 characters for 16 bytes).
String encodeChannelKey(List<int> k) => base64Url.encode(k).replaceAll('=', '');

List<int>? decodeChannelKey(String s) {
  try {
    final k = base64Url.decode(base64Url.normalize(s.trim()));
    return k.length == 16 ? k : null;
  } on FormatException {
    return null;
  }
}

/// PACE layer C in the app: [MeshCoreTransport] on whatever radio link is up. The link comes
/// and goes (BLE range, radio switched off); the transport follows it.
class MeshCoreAppTransport extends AppTransport {
  MeshCoreAppTransport(this._link, Stream<bool> connected) {
    _inner.onChanged = () => _onChanged?.call();
    _sub = connected.listen(_onConnected);
  }

  final FrameLink _link;
  final MeshCoreTransport _inner = MeshCoreTransport();
  late final StreamSubscription<bool> _sub;
  void Function()? _onChanged;
  CompanionClient? _client;
  String? error;

  Future<void> _onConnected(bool up) async {
    if (!up) {
      await _inner.detach();
      await _client?.close();
      _client = null;
      return;
    }
    if (_client != null) return;
    final c = CompanionClient(_link);
    _client = c;
    try {
      await _inner.attach(c);
      error = null;
    } catch (e) {
      error = '$e';
      _client = null;
      await c.close();
      _onChanged?.call();
    }
  }

  /// The group's private LoRa channel, or the common ECP channel ([MeshCoreTransport]).
  Future<void> setChannelSecret(List<int> secret) => _inner.setChannelSecret(secret);

  bool get isDefaultChannel => _inner.isDefaultChannel;

  List<int> get channelSecret => _inner.secret;

  SelfInfo? get radio => _inner.selfInfo;

  /// Called by the owner to drop the radio link and connect again ("Obnovit spojení").
  Future<void> Function()? reconnectLink;
  DeviceInfo? get device => _inner.deviceInfo;

  @override
  String get id => _inner.id;

  @override
  PaceLayer? get layer => _inner.layer;

  @override
  bool get isAvailable => _inner.isAvailable;

  @override
  bool canReach(String contactId) => _inner.canReach(contactId);

  @override
  Future<bool> sendTo(String contactId, Uint8List data) => _inner.sendTo(contactId, data);

  @override
  Future<bool> broadcast(Uint8List data) => _inner.broadcast(data);

  @override
  String get status {
    final r = _inner.selfInfo;
    if (_inner.isAvailable && r != null) return Lang.tr.stLora('${_inner.deviceInfo?.model ?? r.name} · ${r.radio}');
    return error == null ? Lang.tr.loraNotConnected : Lang.tr.loraError;
  }

  @override
  void bind({
    required Future<void> Function(Uint8List data) onData,
    required void Function() onChanged,
  }) {
    _inner.onData = (env, _) => onData(env);
    _onChanged = onChanged;
  }

  /// Contacts do not matter on LoRa: a flood reaches whoever is in range.
  @override
  Future<void> contactsChanged(List<Contact> contacts) async {}

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _inner.detach();
    await _client?.close();
  }
}
