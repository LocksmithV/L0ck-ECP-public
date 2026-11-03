import 'dart:async';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../data/database.dart';
import '../platform/radio.dart' show Permissions;
import 'messaging_service.dart';

/// What a call needs from WebRTC. [WebRtcMedia] is the real one; tests use a fake.
abstract class CallMedia {
  /// Our offer (SDP), with every ICE candidate already in it.
  Future<String> offer();

  /// Our answer to [offer], likewise.
  Future<String> answer(String offer);

  /// The other side's answer to our offer.
  Future<void> accepted(String answer);

  /// true once the audio flows, false when the connection is lost for good.
  Stream<bool> get connected;

  Future<void> mute(bool on);
  Future<void> speaker(bool on);

  /// Whether the audio goes through a relay (SimpleX TURN) rather than directly; null when
  /// it cannot be told.
  Future<bool?> relayed();

  Future<void> close();
}

/// Audio only, Opus over DTLS-SRTP. Direct first (local network, STUN), the SimpleX relay
/// when no direct path works. The servers are SimpleX's public ones, as its own app uses them
/// (packages/simplex-chat-webrtc/src/call.ts): the relay sees both IP addresses, never the
/// audio.
class WebRtcMedia implements CallMedia {
  static const iceServers = [
    {'urls': 'stun:stun.simplex.im:443'},
    {
      'urls': 'turns:turn.simplex.im:443?transport=tcp',
      'username': 'private2',
      'credential': 'Hxuq2QxUjnhj96Zq2r4HjqHRj',
    },
  ];

  /// How long candidate gathering may take before the SDP goes out with what there is.
  static const gathering = Duration(seconds: 5);

  RTCPeerConnection? _pc;
  MediaStream? _mic;
  final _connected = StreamController<bool>.broadcast();
  Timer? _lost;

  @override
  Stream<bool> get connected => _connected.stream;

  Future<RTCPeerConnection> _open() async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
    });
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _lost?.cancel();
          _connected.add(true);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _connected.add(false);
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Often comes back by itself (network switch); give it a moment
          _lost?.cancel();
          _lost = Timer(const Duration(seconds: 10), () => _connected.add(false));
        default:
          break;
      }
    };
    final mic = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': false,
    });
    for (final t in mic.getAudioTracks()) {
      await pc.addTrack(t, mic);
    }
    _mic = mic;
    _pc = pc;
    await Helper.setSpeakerphoneOn(false); // the earpiece, like a phone call
    await _callAudio(true);
    return pc;
  }

  /// Sets [d] as ours and waits until the ICE candidates are in it.
  Future<String> _local(RTCPeerConnection pc, RTCSessionDescription d) async {
    final done = Completer<void>();
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) done.complete();
    };
    await pc.setLocalDescription(d);
    await done.future.timeout(gathering, onTimeout: () {});
    return (await pc.getLocalDescription())!.sdp!;
  }

  @override
  Future<String> offer() async {
    final pc = await _open();
    return _local(pc, await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': false}));
  }

  @override
  Future<String> answer(String offer) async {
    final pc = await _open();
    await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
    return _local(pc, await pc.createAnswer({}));
  }

  @override
  Future<void> accepted(String answer) async =>
      _pc?.setRemoteDescription(RTCSessionDescription(answer, 'answer'));

  @override
  Future<void> mute(bool on) async {
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !on;
    }
  }

  @override
  Future<void> speaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Future<bool?> relayed() async {
    final pc = _pc;
    if (pc == null) return null;
    try {
      final stats = await pc.getStats();
      final byId = {for (final r in stats) r.id: r};
      for (final r in stats) {
        if (r.type != 'candidate-pair' || r.values['state'] != 'succeeded') continue;
        if (r.values['nominated'] != true && r.values['selected'] != true) continue;
        final local = byId[r.values['localCandidateId']];
        final remote = byId[r.values['remoteCandidateId']];
        return local?.values['candidateType'] == 'relay' || remote?.values['candidateType'] == 'relay';
      }
    } catch (_) {
      // stats differ between versions; not knowing is fine
    }
    return null;
  }

  /// AudioHost: microphone through screen-off/lock, proximity sensor.
  static Future<void> _callAudio(bool on) async {
    try {
      await const MethodChannel('cz.l0ck.ecp/audio').invokeMethod('callAudio', {'on': on});
    } catch (_) {
      // without it the call still works while the app is in view
    }
  }

  @override
  Future<void> close() async {
    _lost?.cancel();
    await _callAudio(false);
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    await _pc?.close();
    _mic = null;
    _pc = null;
    await _connected.close();
  }
}

enum CallPhase { calling, ringing, connecting, active, ended }

/// The one call there can be: who, which way, how far it got.
@immutable
class CallState {
  const CallState({
    required this.contact,
    required this.outgoing,
    required this.phase,
    this.since,
    this.muted = false,
    this.speaker = false,
    this.relayed,
    this.reason,
  });

  final Contact contact;
  final bool outgoing;
  final CallPhase phase;

  /// When the audio started flowing.
  final DateTime? since;
  final bool muted, speaker;
  final bool? relayed;

  /// Why it ended (CallSignal.hangUp …), once [phase] is ended.
  final int? reason;

  CallState copyWith({CallPhase? phase, DateTime? since, bool? muted, bool? speaker, bool? relayed, int? reason}) =>
      CallState(
        contact: contact,
        outgoing: outgoing,
        phase: phase ?? this.phase,
        since: since ?? this.since,
        muted: muted ?? this.muted,
        speaker: speaker ?? this.speaker,
        relayed: relayed ?? this.relayed,
        reason: reason ?? this.reason,
      );
}

/// 1:1 calls: the set-up goes as CallSignals over SimpleX/Bramble (MessagingService), the
/// audio over WebRTC. One call at a time; a second caller hears "busy".
class CallService {
  CallService(this.messaging, {CallMedia Function()? media, this.ringFor = const Duration(seconds: 45)})
      : _newMedia = media ?? WebRtcMedia.new {
    _sub = messaging.callSignals.listen((e) => _onSignal(e.$1, e.$2));
  }

  /// The unlocked profile's call service (set by the app shell), for the screens.
  static CallService? instance;

  final MessagingService messaging;
  final CallMedia Function() _newMedia;

  /// How long a call rings before it counts as not answered.
  final Duration ringFor;

  /// The current call; null when there is none. The UI follows it.
  final ValueNotifier<CallState?> current = ValueNotifier(null);

  /// An incoming call starts ringing (the shell shows the call screen, or a notification).
  void Function(CallState call)? onIncoming;

  /// The call ended (the shell stops the ringing notification).
  VoidCallback? onEnded;

  StreamSubscription<(int, CallSignal)>? _sub;
  CallMedia? _media;
  StreamSubscription<bool>? _mediaSub;
  Uint8List? _id;
  String? _offer;
  Timer? _ring;

  bool get busy => current.value != null && current.value!.phase != CallPhase.ended;

  void _set(CallState s) => current.value = s;

  /// Calls [contact]; returns why not, or null when it rings.
  Future<String?> call(Contact contact, {required String noChannel, required String noMic}) async {
    if (busy) return null;
    if (!messaging.canCall(contact.id)) return noChannel;
    if (!await _micAllowed()) return noMic;
    final id = randomBytes(8);
    _id = id;
    _set(CallState(contact: contact, outgoing: true, phase: CallPhase.calling));
    try {
      final media = _attach(_newMedia());
      final sdp = await media.offer();
      if (_id != id) return null; // hung up while gathering
      if (!await messaging.sendCallSignal(contact.id, CallSignal.sdp(id, CallSignal.offer, sdp))) {
        await _finish(CallSignal.failed, notify: false);
        return noChannel;
      }
    } catch (e) {
      debugPrint('call: $e');
      await _finish(CallSignal.failed, notify: false);
      return noMic;
    }
    _ring = Timer(ringFor, () => _finish(CallSignal.noAnswer));
    return null;
  }

  Future<void> accept({required String noMic}) async {
    final s = current.value, offer = _offer, id = _id;
    if (s == null || s.phase != CallPhase.ringing || offer == null || id == null) return;
    _ring?.cancel();
    _set(s.copyWith(phase: CallPhase.connecting));
    onEnded?.call(); // stop ringing
    try {
      if (!await _micAllowed()) throw StateError(noMic);
      final sdp = await _attach(_newMedia()).answer(offer);
      if (_id != id) return;
      if (!await messaging.sendCallSignal(s.contact.id, CallSignal.sdp(id, CallSignal.answer, sdp))) {
        await _finish(CallSignal.failed);
      }
    } catch (e) {
      debugPrint('call: $e');
      await _finish(CallSignal.failed);
    }
  }

  Future<void> decline() => _finish(CallSignal.declined);

  Future<void> hangUp() => _finish(CallSignal.hangUp);

  Future<void> toggleMute() async {
    final s = current.value;
    if (s == null) return;
    await _media?.mute(!s.muted);
    _set(s.copyWith(muted: !s.muted));
  }

  Future<void> toggleSpeaker() async {
    final s = current.value;
    if (s == null) return;
    await _media?.speaker(!s.speaker);
    _set(s.copyWith(speaker: !s.speaker));
  }

  Future<bool> _micAllowed() => Permissions.request(const ['android.permission.RECORD_AUDIO']);

  CallMedia _attach(CallMedia m) {
    _media = m;
    _mediaSub = m.connected.listen((up) async {
      final s = current.value;
      if (s == null || s.phase == CallPhase.ended) return;
      if (!up) return _finish(CallSignal.failed);
      if (s.phase == CallPhase.active) return; // back after a short drop
      _set(s.copyWith(phase: CallPhase.active, since: DateTime.now()));
      final relayed = await m.relayed();
      final now = current.value;
      if (relayed != null && now != null && now.phase == CallPhase.active) _set(now.copyWith(relayed: relayed));
    });
    return m;
  }

  Future<void> _onSignal(int from, CallSignal sig) async {
    final s = current.value;
    final ours = _id != null && sig.callHex == toHex(_id!) && s != null && s.contact.id == from;
    switch (sig.kind) {
      case CallSignal.offer:
        if (ours) return; // the same offer twice
        if (busy) {
          await messaging.sendCallSignal(from, CallSignal.ended(sig.callId, CallSignal.busy));
          return;
        }
        final contact = await messaging.session.db.watchContact(from).first;
        if (contact == null) return;
        _id = sig.callId;
        _offer = sig.sdp;
        final ringing = CallState(contact: contact, outgoing: false, phase: CallPhase.ringing);
        _set(ringing);
        onIncoming?.call(ringing);
        _ring = Timer(ringFor, () => _finish(CallSignal.noAnswer, notify: false));
      case CallSignal.answer:
        if (!ours || s.phase != CallPhase.calling) return;
        _ring?.cancel();
        _set(s.copyWith(phase: CallPhase.connecting));
        try {
          await _media?.accepted(sig.sdp);
        } catch (e) {
          debugPrint('call: $e');
          await _finish(CallSignal.failed);
        }
      case CallSignal.end:
        if (ours) await _finish(sig.reason, notify: false);
    }
  }

  /// Ends the call: tells the other side (unless [notify] is false — they ended it, or never
  /// heard of it), closes the audio, and logs it in the conversation.
  Future<void> _finish(int reason, {bool notify = true}) async {
    final s = current.value, id = _id;
    if (s == null || s.phase == CallPhase.ended || id == null) return;
    _ring?.cancel();
    _id = null;
    _offer = null;
    _set(s.copyWith(phase: CallPhase.ended, reason: reason));
    onEnded?.call();
    if (notify) await messaging.sendCallSignal(s.contact.id, CallSignal.ended(id, reason));
    await _mediaSub?.cancel();
    await _media?.close();
    _media = null;
    final seconds = s.since == null ? 0 : DateTime.now().difference(s.since!).inSeconds;
    final result = s.since != null
        ? MessagingService.callAnswered
        : reason == CallSignal.declined
            ? MessagingService.callDeclined
            : reason == CallSignal.noAnswer || (!s.outgoing && reason == CallSignal.hangUp)
                ? MessagingService.callMissed
                : MessagingService.callFailed;
    try {
      await messaging.logCall(s.contact.id, outgoing: s.outgoing, result: result, seconds: seconds);
    } catch (_) {
      // the profile may be closing
    }
    // The call screen shows how it ended for a moment
    Timer(const Duration(seconds: 2), () {
      if (current.value?.phase == CallPhase.ended) current.value = null;
    });
  }

  Future<void> dispose() async {
    await hangUp();
    await _sub?.cancel();
  }
}
