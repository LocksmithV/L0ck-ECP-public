import 'dart:async';

import 'package:flutter/services.dart';

/// A Bramble contact as the native node reports it.
class BrambleContact {
  const BrambleContact(this.id, this.link, this.links);

  final int id;

  /// The `briar://` handshake link it was added by — how it is matched to an ECP contact.
  final String? link;

  /// Transports with a live connection right now (tor / lan / bluetooth).
  final List<String> links;
}

/// The native Bramble node (android/…/bramble/BrambleHost.java). Abstract so tests and the
/// laptop peer can stand in for it.
abstract class BrambleApi {
  /// Starts (or joins) this profile's node; returns its own handshake link.
  Future<String> start({
    required String profile,
    required String nickname,
    required String password,
  });

  Future<List<BrambleContact>> contacts();

  /// pending · exists · invalid
  Future<String> addContact(String link, String alias);

  Future<void> send(int contact, Uint8List envelope);

  Future<List<String>> transports();

  /// Events: transport{transport, active}, contactAdded{id}, contactRemoved{id},
  /// connection{contact, transport, open}, pending{state}, received{contact, data, links}.
  Stream<Map<String, Object?>> get events;

  Future<void> removeContact(int contact);

  /// Restarts a Bluetooth plugin that started before "Nearby devices" was granted.
  Future<String> refreshBluetooth();

  /// Switches one transport (tor / lan / bluetooth) off and on; its state afterwards.
  Future<String> restartTransport(String name);

  /// First Bluetooth link to a Bramble contact (both phones visible, then discovery).
  /// connected · no-uuid · not-found · unavailable
  Future<String> connectBluetooth(int contact);

  /// Takes the node offline for good in this process unless it runs profile [keep]
  /// (a duress switch of profiles; repeated harmlessly on every decoy unlock).
  Future<void> stopUnless(String? keep);

  /// Deletes every Bramble profile directory except [keep] (all of them when null).
  Future<void> deleteProfilesExcept(String? keep);
}

class NativeBramble implements BrambleApi {
  const NativeBramble();

  static const _m = MethodChannel('cz.l0ck.ecp/bramble');
  static const _e = EventChannel('cz.l0ck.ecp/bramble/events');
  static final Stream<Map<String, Object?>> _events =
      _e.receiveBroadcastStream().map((e) => Map<String, Object?>.from(e as Map)).asBroadcastStream();

  @override
  Future<String> start({
    required String profile,
    required String nickname,
    required String password,
  }) async =>
      (await _m.invokeMethod<String>(
          'start', {'profile': profile, 'nickname': nickname, 'password': password}))!;

  @override
  Future<List<BrambleContact>> contacts() async => [
        for (final c in (await _m.invokeListMethod<Map>('contacts'))!)
          BrambleContact(c['id'] as int, c['link'] as String?,
              List<String>.from(c['links'] as List? ?? const [])),
      ];

  @override
  Future<String> addContact(String link, String alias) async =>
      (await _m.invokeMethod<String>('addContact', {'link': link, 'alias': alias}))!;

  @override
  Future<void> send(int contact, Uint8List envelope) =>
      _m.invokeMethod('send', {'contact': contact, 'data': envelope});

  @override
  Future<List<String>> transports() async =>
      List<String>.from((await _m.invokeListMethod<String>('transports')) ?? const []);

  @override
  Stream<Map<String, Object?>> get events => _events;

  @override
  Future<String> restartTransport(String name) async =>
      (await _m.invokeMethod<String>('restartTransport', {'name': name})) ?? 'NONE';

  @override
  Future<String> refreshBluetooth() async =>
      (await _m.invokeMethod<String>('refreshBluetooth')) ?? 'NONE';

  @override
  Future<void> removeContact(int contact) => _m.invokeMethod('removeContact', {'id': contact});

  @override
  Future<String> connectBluetooth(int contact) async =>
      (await _m.invokeMethod<String>('connectBluetooth', {'id': contact}))!;

  @override
  Future<void> stopUnless(String? keep) => _m.invokeMethod('stop', {'keep': keep});

  @override
  Future<void> deleteProfilesExcept(String? keep) =>
      _m.invokeMethod('deleteProfiles', {'keep': keep});

  /// One profile's Bramble data only (the PIN screen's "compromised"; see
  /// SecurityService.destroyProfile).
  Future<void> deleteProfile(String profile) => _m.invokeMethod('deleteProfile', {'profile': profile});
}
