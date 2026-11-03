import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Voice messages on the phone (AudioHost): recording a clip, playing one from memory.
abstract final class VoiceAudio {
  static const _channel = MethodChannel('cz.l0ck.ecp/audio');

  /// The message id now playing, if any.
  static final ValueNotifier<String?> playing = ValueNotifier(null);

  /// The recording reached its maximum length (VoicePart.maxDuration).
  static VoidCallback? onLimit;

  static bool _bound = false;

  static void _bind() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'played':
          playing.value = null;
        case 'limit':
          onLimit?.call();
      }
    });
  }

  /// Starts recording; returns the codec (VoicePart.opus / aac).
  static Future<int> start() async {
    _bind();
    playing.value = null;
    return await _channel.invokeMethod<int>('start') ?? 0;
  }

  /// Stops and returns the clip; null when it was too short to hold anything.
  static Future<({Uint8List data, int codec, int durationMs})?> stop() async {
    final m = await _channel.invokeMapMethod<String, Object?>('stop');
    if (m == null) return null;
    return (data: m['data'] as Uint8List, codec: m['codec'] as int, durationMs: m['durationMs'] as int);
  }

  static Future<void> cancel() => _channel.invokeMethod('cancel');

  /// Loudness since the last call, 0..32767 (the recording meter).
  static Future<int> level() async => await _channel.invokeMethod<int>('level') ?? 0;

  static Future<void> play(String id, Uint8List data) async {
    _bind();
    playing.value = id;
    try {
      await _channel.invokeMethod('play', {'data': data});
    } catch (_) {
      playing.value = null;
      rethrow;
    }
  }

  static Future<void> stopPlaying() async {
    playing.value = null;
    await _channel.invokeMethod('stopPlaying');
  }
}
