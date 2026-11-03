import 'dart:async';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../messaging/call_service.dart';
import 'theme.dart';
import 'voice.dart' show voiceLength;
import 'widgets.dart';

/// The one call: who, how far it got, how it is carried; answer / decline while it rings,
/// mute, speaker and hang up while it runs. Closes itself when the call is over.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.calls});

  final CallService calls;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.calls.current.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.calls.current.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (widget.calls.current.value == null) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {});
    }
  }

  String _phase(AppLocalizations l, CallState s) => switch (s.phase) {
        CallPhase.calling => l.callCalling,
        CallPhase.ringing => l.callIncoming,
        CallPhase.connecting => l.callConnecting,
        CallPhase.active => voiceLength(DateTime.now().difference(s.since!).inMilliseconds),
        CallPhase.ended => switch (s.reason) {
            CallSignal.declined => l.callDeclinedEnd,
            CallSignal.busy => l.callBusy,
            CallSignal.noAnswer => l.callNoAnswer,
            CallSignal.failed => l.callFailedEnd,
            _ => l.callEnded,
          },
      };

  Widget _round(IconData icon, String label, Color color, VoidCallback? onTap, {Key? key, bool on = false}) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 72,
          height: 72,
          child: FilledButton(
            key: key,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: on ? color : color.withValues(alpha: color == L0ckColors.red || color == L0ckColors.ok ? 1 : 0.18),
              foregroundColor: on || color == L0ckColors.red || color == L0ckColors.ok ? Colors.white : color,
            ),
            onPressed: onTap,
            child: Icon(icon, size: 32),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: L0ckColors.text, fontSize: 12)),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = widget.calls.current.value;
    final l = context.l;
    if (s == null) return const Scaffold();
    final ringing = s.phase == CallPhase.ringing;
    final ended = s.phase == CallPhase.ended;
    return PopScope(
      canPop: ended, // leaving does not end the call; the buttons do
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const SizedBox(height: 24),
              const L0ckTitle(size: 15),
              const Spacer(),
              const Icon(Icons.account_circle, size: 96, color: L0ckColors.greenLight),
              const SizedBox(height: 12),
              Text(s.contact.name,
                  style: const TextStyle(color: L0ckColors.data, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_phase(l, s),
                  key: const Key('call-phase'),
                  style: TextStyle(color: ended ? L0ckColors.orange : L0ckColors.text, fontSize: 18)),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, size: 14, color: L0ckColors.greenLight),
                const SizedBox(width: 6),
                Text(
                    s.relayed == null
                        ? l.callEncrypted
                        : s.relayed!
                            ? l.callRelayed
                            : l.callDirect,
                    style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
              ]),
              const Spacer(),
              if (ringing)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(Icons.call_end, l.callDecline, L0ckColors.red, widget.calls.decline, key: const Key('call-decline')),
                  _round(Icons.call, l.callAccept, L0ckColors.ok, () => widget.calls.accept(noMic: l.voiceMicDenied),
                      key: const Key('call-accept')),
                ])
              else if (!ended)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(s.muted ? Icons.mic_off : Icons.mic, l.callMute, L0ckColors.greenLight, widget.calls.toggleMute,
                      on: s.muted),
                  _round(Icons.call_end, l.callHangUp, L0ckColors.red, widget.calls.hangUp, key: const Key('call-hangup')),
                  _round(Icons.volume_up, l.callSpeaker, L0ckColors.greenLight, widget.calls.toggleSpeaker,
                      on: s.speaker),
                ]),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ),
    );
  }
}
