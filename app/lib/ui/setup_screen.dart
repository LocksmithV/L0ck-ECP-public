import 'package:flutter/material.dart';

import '../security/security_service.dart';
import '../l10n/lang.dart';
import 'theme.dart';
import 'widgets.dart';

/// First start: nickname, PIN and (recommended) duress code.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.security, required this.onDone});

  final SecurityService security;
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _nick = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _duress = TextEditingController();
  final _duress2 = TextEditingController();
  bool _withDuress = true;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final nick = _nick.text.trim();
    final pin = _pin.text;
    final duress = _duress.text;
    String? err;
    if (nick.isEmpty || nick.length > 24) {
      err = context.l.nicknameLength;
    } else if (SecurityService.validatePin(pin) case final e?) {
      err = context.l.pinError('$e');
    } else if (pin != _pin2.text) {
      err = context.l.pinMismatch;
    } else if (_withDuress) {
      if (SecurityService.validatePin(duress) case final e?) {
        err = context.l.duressError('$e');
      } else if (duress != _duress2.text) {
        err = context.l.duressMismatch;
      } else if (duress == pin) {
        err = context.l.duressSameAsPin;
      }
    }
    setState(() => _error = err);
    if (err != null) return;

    setState(() => _busy = true);
    try {
      await widget.security.setup(
        pin: pin,
        duressPin: _withDuress ? duress : null,
        nickname: nick,
      );
      for (final c in [_pin, _pin2, _duress, _duress2]) {
        c.clear();
      }
      widget.onDone();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = context.l.setupFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const BrandHeader(),
            const SizedBox(height: 16),
            Text(context.l.firstRun,
                style: TextStyle(color: L0ckColors.greenLight, letterSpacing: 2)),
            const SizedBox(height: 20),
            TextField(
              controller: _nick,
              maxLength: 24,
              decoration: InputDecoration(labelText: context.l.nickname, counterText: ''),
            ),
            const SizedBox(height: 12),
            PinField(controller: _pin, label: context.l.pinDigits),
            const SizedBox(height: 12),
            PinField(controller: _pin2, label: context.l.pinAgain),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withDuress,
              onChanged: _busy ? null : (v) => setState(() => _withDuress = v),
              title: Text(context.l.duressCode),
              subtitle: Text(context.l.duressExplain, style: const TextStyle(color: L0ckColors.dim)),
            ),
            if (_withDuress) ...[
              PinField(controller: _duress, label: context.l.duressDigits),
              const SizedBox(height: 12),
              PinField(controller: _duress2, label: context.l.duressAgain),
            ],
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: L0ckColors.red)),
              ),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? context.l.generatingKeys : context.l.create),
            ),
          ],
        ),
      ),
    );
  }
}
