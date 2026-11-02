import 'dart:async';

import 'package:flutter/material.dart';

import '../security/security_service.dart';
import '../l10n/lang.dart';
import 'theme.dart';
import 'widgets.dart';

/// PIN entry. Real PIN and duress code behave identically on screen.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.security,
    this.runningProfile,
    required this.onUnlocked,
    required this.onResumed,
    required this.onWiped,
  });

  final SecurityService security;

  /// The profile still open in the background, if any (see SecurityService.unlock).
  final String? runningProfile;
  final ValueChanged<Session> onUnlocked;

  /// The code matched the running profile: only the screen unlocks.
  final VoidCallback onResumed;
  final VoidCallback onWiped;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _message;
  DateTime? _waitUntil;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.security.attemptState().then((s) {
      if (s.$2 != null && s.$2!.isAfter(DateTime.now())) _startWait(s.$2!);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startWait(DateTime until) {
    _waitUntil = until;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_waitUntil!)) {
        _tick?.cancel();
        _waitUntil = null;
      }
      setState(() {});
    });
    setState(() {});
  }

  Future<void> _unlock() async {
    final pin = _pin.text;
    if (pin.isEmpty || _busy || _waitUntil != null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome =
        await widget.security.unlock(pin, runningProfile: widget.runningProfile);
    _pin.clear();
    if (!mounted) return;
    switch (outcome) {
      case Unlocked(:final session):
        widget.onUnlocked(session);
      case StillUnlocked():
        widget.onResumed();
      case WrongCode(:final retryAfter):
        setState(() {
          _busy = false;
          _message = context.l.wrongCode;
        });
        if (retryAfter > Duration.zero) _startWait(DateTime.now().add(retryAfter));
      case MustWait(:final remaining):
        setState(() => _busy = false);
        _startWait(DateTime.now().add(remaining));
      case Wiped():
        widget.onWiped();
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waitUntil != null;
    final secs = waiting ? _waitUntil!.difference(DateTime.now()).inSeconds + 1 : 0;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandHeader(),
              const SizedBox(height: 28),
              PinField(
                controller: _pin,
                label: context.l.pin,
                autofocus: true,
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || waiting ? null : _unlock,
                child: Text(_busy
                    ? context.l.verifying
                    : waiting
                        ? context.l.retryIn(secs)
                        : context.l.unlock),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: L0ckColors.red)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
