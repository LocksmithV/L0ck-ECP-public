import 'dart:async';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../platform/radio.dart' show Permissions;
import '../platform/voice.dart';
import 'theme.dart';

/// "0:07".
String voiceLength(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A voice message inside a chat bubble: play / stop and its length.
class VoiceClipView extends StatelessWidget {
  const VoiceClipView({super.key, required this.id, required this.payload});

  final String id;
  final Uint8List payload;

  @override
  Widget build(BuildContext context) {
    final VoicePart clip;
    try {
      clip = VoicePart.decode(payload);
    } on FormatException {
      return Text(context.l.voicePlayFailed, style: const TextStyle(color: L0ckColors.red));
    }
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceAudio.playing,
      builder: (context, playing, _) {
        final on = playing == id;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: Key('play-$id'),
            visualDensity: VisualDensity.compact,
            iconSize: 34,
            color: on ? L0ckColors.orange : L0ckColors.greenLight,
            icon: Icon(on ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            onPressed: () async {
              if (on) return VoiceAudio.stopPlaying();
              final failed = context.l.voicePlayFailed;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await VoiceAudio.play(id, clip.data);
              } catch (_) {
                messenger.showSnackBar(SnackBar(content: Text(failed)));
              }
            },
          ),
          const Icon(Icons.graphic_eq, size: 20, color: L0ckColors.dim),
          const SizedBox(width: 6),
          Text(voiceLength(clip.durationMs),
              style: const TextStyle(color: L0ckColors.text, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()])),
        ]);
      },
    );
  }
}

/// Takes the place of the message field while a clip is recorded: time, level, discard and
/// send. Recording starts as soon as it shows and stops by itself at
/// [VoicePart.maxDuration].
class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({super.key, required this.onSend, required this.onClose});

  final Future<void> Function(int codec, int durationMs, Uint8List data) onSend;

  /// Back to the message field (sent, discarded or failed).
  final VoidCallback onClose;

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final _clock = Stopwatch();
  Timer? _tick;
  double _level = 0;
  bool _recording = false, _busy = false, _atLimit = false;
  ({Uint8List data, int codec, int durationMs})? _clip;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start()); // needs the localizations
  }

  @override
  void dispose() {
    _tick?.cancel();
    VoiceAudio.onLimit = null;
    if (_recording) VoiceAudio.cancel(); // left the chat or locked: nothing is kept
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _start() async {
    final l = context.l;
    if (!await Permissions.request(const ['android.permission.RECORD_AUDIO'])) {
      if (mounted) _say(l.voiceMicDenied);
      return widget.onClose();
    }
    try {
      VoiceAudio.onLimit = () => _stop(limit: true);
      await VoiceAudio.start();
    } catch (_) {
      if (mounted) _say(l.voiceFailed);
      return widget.onClose();
    }
    if (!mounted) return VoiceAudio.cancel();
    _clock.start();
    _tick = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      final v = await VoiceAudio.level();
      if (mounted && _recording) setState(() => _level = (v / 20000).clamp(0, 1).toDouble());
    });
    setState(() => _recording = true);
  }

  /// Stops recording and keeps the clip.
  Future<void> _stop({bool limit = false}) async {
    if (!_recording) return;
    _recording = false;
    _tick?.cancel();
    _clock.stop();
    final clip = await VoiceAudio.stop();
    if (!mounted) return;
    setState(() {
      _clip = clip;
      _atLimit = limit;
    });
    if (clip == null) widget.onClose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_recording) await _stop();
    final clip = _clip;
    if (clip != null) await widget.onSend(clip.codec, clip.durationMs, clip.data);
    if (mounted) widget.onClose();
  }

  Future<void> _discard() async {
    if (_recording) {
      _recording = false;
      _tick?.cancel();
      await VoiceAudio.cancel();
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final ms = _clip?.durationMs ?? _clock.elapsedMilliseconds;
    return Row(children: [
      IconButton(
        key: const Key('voice-discard'),
        tooltip: l.voiceDiscard,
        icon: const Icon(Icons.delete_outline, color: L0ckColors.red),
        onPressed: _busy ? null : _discard,
      ),
      Icon(Icons.fiber_manual_record, size: 14, color: _recording ? L0ckColors.red : L0ckColors.dim),
      const SizedBox(width: 6),
      Text('${voiceLength(ms)} / ${voiceLength(VoicePart.maxDuration.inMilliseconds)}',
          style: const TextStyle(color: L0ckColors.text, fontFeatures: [FontFeature.tabularFigures()])),
      const SizedBox(width: 10),
      Expanded(
        child: _atLimit
            ? Text(l.voiceAtLimit, style: const TextStyle(color: L0ckColors.orange, fontSize: 12))
            : ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _recording ? _level : 0,
                  minHeight: 8,
                  backgroundColor: L0ckColors.widget,
                  color: L0ckColors.green,
                ),
              ),
      ),
      if (_recording)
        IconButton(
          key: const Key('voice-stop'),
          tooltip: l.voiceRecording,
          icon: const Icon(Icons.stop, color: L0ckColors.orange),
          onPressed: _stop,
        ),
      IconButton(
        key: const Key('voice-send'),
        tooltip: l.send,
        icon: const Icon(Icons.send, color: L0ckColors.greenLight),
        onPressed: _busy || (!_recording && _clip == null) ? null : _send,
      ),
    ]);
  }
}
