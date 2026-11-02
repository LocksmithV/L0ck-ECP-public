import 'dart:async';
import 'dart:typed_data';

import 'frames.dart';

/// One frame per call in each direction (a BLE characteristic, or USB serial after
/// [SerialFraming]).
abstract class FrameLink {
  Stream<Uint8List> get frames;
  Future<void> send(Uint8List frame);
}

class CompanionError implements Exception {
  CompanionError(this.message, [this.code]);

  final String message;

  /// ERR_CODE_* from the firmware, when it sent one.
  final int? code;

  @override
  String toString() => 'CompanionError($message${code == null ? '' : ', code $code'})';
}

/// Talks to a MeshCore companion radio: one command at a time, each matched to its reply
/// by type; pushed frames (new messages waiting, adverts, logs) handled in between.
class CompanionClient {
  CompanionClient(this.link, {this.timeout = const Duration(seconds: 5)}) {
    _sub = link.frames.listen(_onFrame);
  }

  final FrameLink link;
  final Duration timeout;
  late final StreamSubscription<Uint8List> _sub;
  final _data = StreamController<ChannelData>.broadcast();
  Future<void> _queue = Future.value();
  (Set<int>, Completer<Uint8List>)? _pending;
  bool _draining = false;

  /// Datagrams fetched from the radio (all channels and data types).
  Stream<ChannelData> get channelData => _data.stream;

  /// Sends [cmd] once every earlier command finished; completes with the first frame whose
  /// type is in [expect], or fails on an error frame or timeout.
  Future<Uint8List> request(Uint8List cmd, Set<int> expect) {
    final done = Completer<Uint8List>();
    _queue = _queue.then((_) async {
      final c = Completer<Uint8List>();
      _pending = (expect, c);
      try {
        await link.send(cmd);
        done.complete(await c.future.timeout(timeout));
      } catch (e) {
        done.completeError(e is TimeoutException ? CompanionError('no reply to ${cmd[0]}') : e);
      } finally {
        _pending = null;
      }
    });
    return done.future;
  }

  void _onFrame(Uint8List f) {
    if (f.isEmpty) return;
    final p = _pending;
    if (p != null && !p.$2.isCompleted) {
      if (f[0] == Resp.err) {
        p.$2.completeError(CompanionError('command failed', f.length > 1 ? f[1] : null));
        return;
      }
      if (p.$1.contains(f[0])) {
        p.$2.complete(f);
        return;
      }
    }
    if (f[0] == Resp.msgWaiting) unawaited(drain());
  }

  Future<(SelfInfo, DeviceInfo)> start({String appName = 'ecp'}) async {
    final self = SelfInfo.parse(await request(appStart(appName), {Resp.selfInfo}));
    final dev = DeviceInfo.parse(await request(deviceQuery(), {Resp.deviceInfo}));
    if (self == null || dev == null) throw CompanionError('unexpected start reply');
    unawaited(drain());
    return (self, dev);
  }

  /// Finds the slot holding this channel, or writes it — over the slot of the same name
  /// (the key changed), else into the first free slot. Other channels are never touched.
  Future<int> ensureChannel(String name, List<int> secret, int maxChannels) async {
    int? same, free;
    for (var i = 0; i < maxChannels; i++) {
      final info = ChannelInfo.parse(await request(getChannel(i), {Resp.channelInfo}));
      if (info == null) continue;
      if (info.name == name && _eq(info.secret, secret)) return i;
      if (info.name == name) same ??= i;
      if (info.isEmpty) free ??= i;
    }
    final slot = same ?? free;
    if (slot == null) throw CompanionError('no free channel slot');
    await request(setChannel(slot, name, secret), {Resp.ok});
    return slot;
  }

  Future<void> sendData(int channel, int dataType, List<int> payload) =>
      request(sendChannelData(channel, dataType, payload), {Resp.ok});

  Future<Battery?> battery() async => Battery.parse(await request(getBattery(), {Resp.battery}));

  /// Fetches everything the radio queued (it keeps messages while no app is connected).
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final f = await request(syncNextMessage(), const {
          Resp.noMoreMessages, Resp.channelDataRecv, Resp.channelMsgV3, Resp.contactMsgV3,
          7, 8, // pre-v3 text message frames, ignored like the v3 ones
        });
        if (f[0] == Resp.noMoreMessages) break;
        final d = ChannelData.parse(f);
        if (d != null) _data.add(d);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await _data.close();
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
