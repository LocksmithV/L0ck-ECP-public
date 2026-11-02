import 'dart:async';

import 'package:ecp_meshcore/ecp_meshcore.dart';
import 'package:flutter/services.dart';

/// Runtime permissions (MainActivity). Bluetooth needs CONNECT (and SCAN for Bramble's
/// squad net) from Android 12 on; older versions grant them at install.
class Permissions {
  static const _m = MethodChannel('cz.l0ck.ecp/permissions');

  static Future<bool> request(List<String> permissions) async =>
      await _m.invokeMethod<bool>('request', {'permissions': permissions}) ?? false;

  static Future<bool> bluetooth() => request(const [
        'android.permission.BLUETOOTH_CONNECT',
        'android.permission.BLUETOOTH_SCAN',
        'android.permission.BLUETOOTH_ADVERTISE',
      ]);
}

/// Makes this phone visible over Bluetooth for two minutes (system dialog); false if refused.
Future<bool> requestDiscoverable() async =>
    await const MethodChannel('cz.l0ck.ecp/activity').invokeMethod<bool>('discoverable') ?? false;

class PairedDevice {
  const PairedDevice(this.address, this.name);

  final String address, name;
}

/// The BLE link to a MeshCore companion (android/…/radio/RadioHost.java).
class NativeRadio implements FrameLink {
  const NativeRadio();

  static const _m = MethodChannel('cz.l0ck.ecp/radio');
  static const _e = EventChannel('cz.l0ck.ecp/radio/events');
  static final Stream<Map<String, Object?>> _events = _e
      .receiveBroadcastStream()
      .map((e) => Map<String, Object?>.from(e as Map))
      .asBroadcastStream();

  Future<List<PairedDevice>> paired() async => [
        for (final d in (await _m.invokeListMethod<Map>('bonded'))!)
          PairedDevice(d['address'] as String, d['name'] as String),
      ];

  Future<void> connect(String address) => _m.invokeMethod('connect', {'address': address});

  Future<void> disconnect() => _m.invokeMethod('disconnect');

  /// True while the GATT link is up and notifications are on.
  Stream<bool> get connected =>
      _events.where((e) => e['type'] == 'state').map((e) => e['connected'] == true);

  @override
  Stream<Uint8List> get frames =>
      _events.where((e) => e['type'] == 'frame').map((e) => e['data'] as Uint8List);

  @override
  Future<void> send(Uint8List frame) => _m.invokeMethod('write', {'data': frame});
}
