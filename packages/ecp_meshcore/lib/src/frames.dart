import 'dart:convert';
import 'dart:typed_data';

/// MeshCore companion protocol frames (firmware `examples/companion_radio/MyMesh.cpp`,
/// docs `companion_protocol.md`, companion firmware v1.12+). Little-endian throughout.
/// One BLE write/notification is one frame; over USB serial frames are wrapped, see
/// [SerialFraming].
abstract final class Cmd {
  static const appStart = 1;
  static const syncNextMessage = 10;
  static const getBattery = 20;
  static const deviceQuery = 22;
  static const getChannel = 31;
  static const setChannel = 32;
  static const sendChannelData = 62;
}

abstract final class Resp {
  static const ok = 0;
  static const err = 1;
  static const selfInfo = 5;
  static const noMoreMessages = 10;
  static const battery = 12;
  static const deviceInfo = 13;
  static const contactMsgV3 = 16;
  static const channelMsgV3 = 17;
  static const channelInfo = 18;
  static const channelDataRecv = 27;
  // Pushed at any time, not replies
  static const msgWaiting = 0x83;
}

/// Largest datagram the radio will send (`MAX_GROUP_DATA_LENGTH`).
const maxChannelData = 165;

/// Flood the whole mesh (no stored path) — the only routing ECP uses on LoRa.
const floodPath = 0xFF;

Uint8List appStart(String appName) =>
    Uint8List.fromList([Cmd.appStart, 0, 0, 0, 0, 0, 0, 0, ...utf8.encode(appName)]);

/// 0x03 = the protocol version this client understands (v3 message frames).
Uint8List deviceQuery() => Uint8List.fromList([Cmd.deviceQuery, 3]);

Uint8List getChannel(int index) => Uint8List.fromList([Cmd.getChannel, index]);

Uint8List setChannel(int index, String name, List<int> secret) {
  if (secret.length != 16) throw ArgumentError('channel secret must be 16 bytes');
  final n = utf8.encode(name);
  if (n.length > 32) throw ArgumentError('channel name over 32 bytes');
  return Uint8List(50)
    ..[0] = Cmd.setChannel
    ..[1] = index
    ..setRange(2, 2 + n.length, n)
    ..setRange(34, 50, secret);
}

Uint8List sendChannelData(int index, int dataType, List<int> payload) {
  if (payload.isEmpty || payload.length > maxChannelData) {
    throw ArgumentError('datagram of ${payload.length} B (1–$maxChannelData)');
  }
  return Uint8List.fromList([
    Cmd.sendChannelData, index, floodPath, dataType & 0xFF, dataType >> 8, ...payload,
  ]);
}

Uint8List syncNextMessage() => Uint8List.fromList([Cmd.syncNextMessage]);

Uint8List getBattery() => Uint8List.fromList([Cmd.getBattery]);

String _cstr(List<int> b) {
  final end = b.indexOf(0);
  return utf8.decode(end < 0 ? b : b.sublist(0, end), allowMalformed: true).trim();
}

int _u32(List<int> b, int o) => b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;

class SelfInfo {
  SelfInfo(this.publicKey, this.txPower, this.freqMHz, this.bwKHz, this.sf, this.cr, this.name);

  static SelfInfo? parse(Uint8List f) {
    if (f.length < 58 || f[0] != Resp.selfInfo) return null;
    return SelfInfo(f.sublist(4, 36), f[2], _u32(f, 48) / 1000.0, _u32(f, 52) / 1000.0, f[56],
        f[57], _cstr(f.sublist(58)));
  }

  final Uint8List publicKey;
  final int txPower;
  final double freqMHz, bwKHz;
  final int sf, cr;
  final String name;

  String get radio => '${freqMHz.toStringAsFixed(3)} MHz · BW ${bwKHz.toStringAsFixed(1)} · '
      'SF$sf · CR$cr · $txPower dBm';
}

class DeviceInfo {
  DeviceInfo(this.firmwareVersion, this.maxChannels, this.model, this.version,
      [this.pathHashMode]);

  static DeviceInfo? parse(Uint8List f) {
    if (f.length < 2 || f[0] != Resp.deviceInfo) return null;
    if (f[1] < 3 || f.length < 80) return DeviceInfo(f[1], 1, '', '');
    return DeviceInfo(f[1], f[3], _cstr(f.sublist(20, 60)), _cstr(f.sublist(60, 80)),
        f.length > 81 ? f[81] : null);
  }

  final int firmwareVersion;
  final int maxChannels;
  final String model, version;

  /// Bytes per repeater hash in flood paths, minus one (firmware v10+). Regional meshes
  /// agree on it (e.g. 2-byte hashes); ECP leaves it as the radio is set.
  final int? pathHashMode;

  int? get pathHashBytes => pathHashMode == null ? null : pathHashMode! + 1;
}

class ChannelInfo {
  ChannelInfo(this.index, this.name, this.secret);

  static ChannelInfo? parse(Uint8List f) {
    if (f.length < 50 || f[0] != Resp.channelInfo) return null;
    return ChannelInfo(f[1], _cstr(f.sublist(2, 34)), f.sublist(34, 50));
  }

  final int index;
  final String name;
  final Uint8List secret;

  bool get isEmpty => name.isEmpty && secret.every((b) => b == 0);
}

class ChannelData {
  ChannelData(this.channel, this.dataType, this.payload, this.snr, this.flooded);

  static ChannelData? parse(Uint8List f) {
    if (f.length < 9 || f[0] != Resp.channelDataRecv) return null;
    final len = f[8];
    if (9 + len > f.length) return null;
    final snr = (f[1] < 128 ? f[1] : f[1] - 256) / 4.0;
    return ChannelData(f[4], f[6] | f[7] << 8, f.sublist(9, 9 + len), snr, f[5] != 0xFF);
  }

  final int channel;
  final int dataType;
  final Uint8List payload;

  /// Signal-to-noise ratio of the last hop, dB.
  final double snr;
  final bool flooded;
}

class Battery {
  Battery(this.millivolts);

  static Battery? parse(Uint8List f) =>
      f.length < 3 || f[0] != Resp.battery ? null : Battery(f[1] | f[2] << 8);

  final int millivolts;
}

/// USB serial wraps each frame: app → radio `'<' len16 frame`, radio → app `'>' len16 frame`
/// (`ArduinoSerialInterface.cpp`).
class SerialFraming {
  final _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  static Uint8List wrap(List<int> frame) =>
      Uint8List.fromList([0x3C, frame.length & 0xFF, frame.length >> 8, ...frame]);

  /// Feeds raw bytes from the port; returns every complete radio → app frame.
  List<Uint8List> feed(List<int> bytes) {
    _buf.add(_pending);
    _buf.add(bytes);
    var b = _buf.takeBytes();
    final out = <Uint8List>[];
    var i = 0;
    while (true) {
      while (i < b.length && b[i] != 0x3E) {
        i++; // skip anything that is not a frame start (boot noise, debug text)
      }
      if (i + 3 > b.length) break;
      final len = b[i + 1] | b[i + 2] << 8;
      if (i + 3 + len > b.length) break;
      out.add(Uint8List.fromList(b.sublist(i + 3, i + 3 + len)));
      i += 3 + len;
    }
    _pending = Uint8List.fromList(b.sublist(i));
    return out;
  }
}
