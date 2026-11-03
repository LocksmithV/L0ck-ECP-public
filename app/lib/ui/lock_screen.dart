import 'dart:async';

import 'package:flutter/material.dart';

import '../security/security_service.dart';
import '../l10n/lang.dart';
import 'theme.dart';
import 'widgets.dart';

/// PIN entry. Real PIN and duress code behave identically on screen.
///
/// While a profile runs behind it, two emergency buttons need no PIN: PANIC sends the
/// configured status at once; KOMPROMITOVÁN asks for a confirmation at the other end of the
/// screen, then reports "compromised" and destroys that profile.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.security,
    this.runningProfile,
    required this.onUnlocked,
    required this.onResumed,
    required this.onWiped,
    this.onPanic,
    this.onCompromise,
    this.onBiometric,
  });

  final SecurityService security;

  /// The profile still open in the background, if any (see SecurityService.unlock).
  final String? runningProfile;
  final ValueChanged<Session> onUnlocked;

  /// The code matched the running profile: only the screen unlocks.
  final VoidCallback onResumed;
  final VoidCallback onWiped;

  /// Sends PANIC and returns a line for the screen; null hides the button.
  final Future<String> Function()? onPanic;

  /// Reports "compromised" and destroys the running profile; null hides the button.
  final Future<void> Function()? onCompromise;

  /// Asks for a fingerprint and resumes the running profile on a match; null hides it.
  final Future<void> Function()? onBiometric;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _message;
  DateTime? _waitUntil;
  Timer? _tick;

  bool _panicBusy = false, _confirming = false;
  String? _panicResult;
  Timer? _confirmTimeout;

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
    _confirmTimeout?.cancel();
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

  Future<void> _panic() async {
    if (_panicBusy) return;
    final failed = context.l.panicFailed;
    setState(() {
      _panicBusy = true;
      _panicResult = context.l.panicSending;
    });
    String result;
    try {
      result = await widget.onPanic!();
    } catch (_) {
      result = failed;
    }
    if (!mounted) return;
    setState(() {
      _panicBusy = false;
      _panicResult = result;
    });
  }

  /// The first tap only arms it; the confirmation sits at the top of the screen, away from
  /// the button, and disappears after a few seconds.
  void _armCompromise() {
    _confirmTimeout?.cancel();
    if (_confirming) {
      setState(() => _confirming = false);
      return;
    }
    setState(() => _confirming = true);
    _confirmTimeout = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _confirming = false);
    });
  }

  Future<void> _compromise() async {
    _confirmTimeout?.cancel();
    setState(() {
      _confirming = false;
      _panicBusy = true;
      _panicResult = context.l.panicSending;
    });
    await widget.onCompromise!();
    if (!mounted) return;
    // Afterwards the screen is a plain PIN screen again: nothing tells what happened
    setState(() {
      _panicBusy = false;
      _panicResult = null;
    });
  }

  Widget _emergencyButtons() {
    final panic = widget.onPanic, compromise = widget.onCompromise;
    if (panic == null && compromise == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_panicResult != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_panicResult!,
                textAlign: TextAlign.center, style: const TextStyle(color: L0ckColors.orange)),
          ),
        Row(children: [
          if (panic != null)
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                key: const Key('panic'),
                style: FilledButton.styleFrom(
                  backgroundColor: L0ckColors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                ),
                icon: const Icon(Icons.campaign),
                label: Text(context.l.panicButton,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                onPressed: _panicBusy ? null : _panic,
              ),
            ),
          if (panic != null && compromise != null) const SizedBox(width: 10),
          if (compromise != null)
            Expanded(
              flex: 2,
              child: OutlinedButton(
                key: const Key('compromise'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: L0ckColors.red,
                  side: BorderSide(color: _confirming ? L0ckColors.orange : L0ckColors.red),
                  minimumSize: const Size.fromHeight(56),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: _panicBusy ? null : _armCompromise,
                child: FittedBox(child: Text(context.l.compromiseButton)),
              ),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waitUntil != null;
    final secs = waiting ? _waitUntil!.difference(DateTime.now()).inSeconds + 1 : 0;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
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
                      if (widget.onBiometric != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton.icon(
                            key: const Key('biometric'),
                            icon: const Icon(Icons.fingerprint, size: 28),
                            label: Text(context.l.bioButton),
                            onPressed: _busy || waiting ? null : widget.onBiometric,
                          ),
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
            ),
            _emergencyButtons(),
          ]),
          if (_confirming)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: FilledButton.icon(
                key: const Key('confirm-compromise'),
                style: FilledButton.styleFrom(
                  backgroundColor: L0ckColors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(64),
                ),
                icon: const Icon(Icons.delete_forever),
                label: Text(context.l.confirmCompromise, textAlign: TextAlign.center),
                onPressed: _compromise,
              ),
            ),
        ]),
      ),
    );
  }
}
