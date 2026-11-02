import 'package:flutter/services.dart';

/// Phone SMS (android/…/sms/SmsHost.java). Abstract so tests can stand in for it.
abstract class SmsApi {
  /// send / receive permission and whether a SIM is ready.
  Future<({bool send, bool receive, bool sim})> status();

  /// True once the network accepted every part; false on any failure (no credit, no signal).
  Future<bool> send(String to, String text);

  /// Incoming SMS: (sender number, text).
  Stream<(String, String)> get received;
}

class NativeSms implements SmsApi {
  const NativeSms();

  static const _m = MethodChannel('cz.l0ck.ecp/sms');
  static const _e = EventChannel('cz.l0ck.ecp/sms/events');
  static final Stream<(String, String)> _in = _e
      .receiveBroadcastStream()
      .map((e) => Map<String, Object?>.from(e as Map))
      .map((m) => (m['from'] as String, m['body'] as String))
      .asBroadcastStream();

  @override
  Future<({bool send, bool receive, bool sim})> status() async {
    final m = Map<String, Object?>.from((await _m.invokeMethod<Map>('status'))!);
    return (send: m['send'] == true, receive: m['receive'] == true, sim: m['sim'] == true);
  }

  @override
  Future<bool> send(String to, String text) async =>
      await _m.invokeMethod<bool>('send', {'to': to, 'text': text}) ?? false;

  @override
  Stream<(String, String)> get received => _in;
}
