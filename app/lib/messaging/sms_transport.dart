import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';

import '../data/database.dart';
import '../platform/sms.dart';
import 'bramble_transport.dart';
import '../l10n/lang.dart';

/// PACE layer E: the envelope as one plain SMS, base64url with no recognisable prefix
/// (docs/ARCHITECTURE_V2.md §3). Only SMS from numbers on a contact's card are even tried;
/// anything else (operator messages, a stranger) is left alone. Sending needs the user's
/// confirmation unless it is an emergency — the router decides that.
class SmsTransport extends AppTransport {
  SmsTransport(this._api);

  final SmsApi _api;
  StreamSubscription<(String, String)>? _sub;
  Future<void> Function(Uint8List)? _onData;
  void Function()? _onChanged;
  ({bool send, bool receive, bool sim}) _state = (send: false, receive: false, sim: false);

  /// ECP contact id → number from the card.
  final Map<String, String> _numberOf = {};

  /// Numbers compare by their last 9 digits: "+420 601 …", "00420601…" and "601…" are the
  /// same phone, whatever form the network or the card used.
  static String key(String number) {
    final d = number.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length > 9 ? d.substring(d.length - 9) : d;
  }

  static String encode(List<int> envelope) => base64Url.encode(envelope).replaceAll('=', '');

  static Uint8List? decode(String body) {
    final t = body.trim();
    if (t.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(t)) return null;
    try {
      return base64Url.decode(base64Url.normalize(t));
    } on FormatException {
      return null;
    }
  }

  Future<void> start() async {
    await refresh();
    _sub = _api.received.listen((m) async {
      final (from, body) = m;
      if (!_numberOf.values.any((n) => key(n) == key(from))) return;
      final env = decode(body);
      if (env != null) await _onData?.call(env);
    });
  }

  /// Re-reads permissions and SIM state (after the user granted SMS, inserted a SIM…).
  Future<void> refresh() async {
    _state = await _api.status();
    _onChanged?.call();
  }

  @override
  String get id => 'sms';

  @override
  PaceLayer? get layer => PaceLayer.emergency;

  @override
  bool get isAvailable => _state.send && _state.sim;

  @override
  bool canReach(String contactId) => _numberOf.containsKey(contactId);

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async {
    final to = _numberOf[contactId];
    if (to == null || !isAvailable) return false;
    return _api.send(to, encode(data));
  }

  @override
  String get status => !_state.sim
      ? Lang.tr.smsNoSim
      : !_state.send || !_state.receive
          ? Lang.tr.smsNotAllowed
          : Lang.tr.smsReady;

  @override
  void bind({
    required Future<void> Function(Uint8List data) onData,
    required void Function() onChanged,
  }) {
    _onData = onData;
    _onChanged = onChanged;
  }

  @override
  Future<void> contactsChanged(List<Contact> contacts) async {
    _numberOf
      ..clear()
      ..addAll({
        for (final c in contacts)
          if (c.phone != null && c.phone!.trim().isNotEmpty) '${c.id}': c.phone!,
      });
  }

  @override
  Future<void> close() async => _sub?.cancel();
}
