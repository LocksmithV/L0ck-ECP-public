import 'dart:io';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_simplex/ecp_simplex.dart';
import 'package:ecp_simplex/ffi.dart';

import '../data/database.dart';
import 'bramble_transport.dart';
import '../l10n/lang.dart';
import '../platform/net.dart';

/// PACE layer P in the app: SimpleX Chat's core (libsimplex.so) with one encrypted database
/// per ECP profile, in a directory named like the profile's Bramble one, so duress and wipe
/// remove both together (docs/ARCHITECTURE_V2.md §6).
class SimplexAppTransport extends AppTransport {
  SimplexAppTransport._(this._api, this._inner);

  static Future<SimplexAppTransport> start({
    required String dir,
    required String dbKey,
    required List<int> ownKey,
  }) async {
    await Directory(dir).create(recursive: true);
    final api = await FfiSimplex.open(dbPrefix: '$dir/simplex', key: dbKey);
    final t = SimplexTransport(api, ownKey: ownKey);
    try {
      await t.start();
    } catch (_) {
      await api.close();
      rethrow;
    }
    return SimplexAppTransport._(api, t);
  }

  final SimplexApi _api;
  final SimplexTransport _inner;

  @override
  String get id => _inner.id;

  @override
  PaceLayer? get layer => _inner.layer;

  /// Relays need the internet: without any, PACE moves on at once (no 60 s ACK wait).
  @override
  bool get isAvailable => _inner.isAvailable && Net.online.value;

  @override
  bool canReach(String contactId) => _inner.canReach(contactId);

  @override
  Future<bool> sendTo(String contactId, Uint8List data) => _inner.sendTo(contactId, data);

  /// The SimpleX contact address for the own card.
  @override
  String? get ownLink => _inner.address;

  @override
  String get status => Lang.tr.stSimplex(!_inner.isAvailable
      ? Lang.tr.unavailable
      : Net.online.value
          ? Lang.tr.active
          : Lang.tr.noInternet);

  @override
  void bind({
    required Future<void> Function(Uint8List data) onData,
    required void Function() onChanged,
  }) {
    _inner.onData = (env) => onData(env);
    _inner.onChanged = onChanged;
  }

  @override
  Future<void> contactsChanged(List<Contact> contacts) => _inner.contactsChanged(
        {for (final c in contacts) '${c.id}': c.ecpKey},
        {
          for (final c in contacts)
            if (c.simplexLink != null) '${c.id}': c.simplexLink!,
        },
      );

  Future<bool> reconnect() => _inner.reconnect();

  /// The network is back: the address it could not make before (started offline). True
  /// when it has just been made — contacts then need the new card.
  Future<bool> networkUp() async => _inner.address == null && await _inner.ensureAddress();

  @override
  Future<void> close() async {
    await _inner.close();
    await _api.close();
  }
}
