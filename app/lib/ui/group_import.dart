import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import '../messaging/sms_transport.dart';
import '../platform/radio.dart' show Permissions;
import '../platform/scanner.dart';
import 'settings_screen.dart' show layerName;
import 'theme.dart';
import 'widgets.dart';

/// Loads the group bundle the base laptop shows (tools/ecp_base): its QR codes one after
/// another, then a summary of what this phone will get, then one tap sets it up.
class GroupImportScreen extends StatefulWidget {
  const GroupImportScreen({super.key, required this.messaging, this.first, this.scan = scanQr});

  final MessagingService messaging;

  /// A part already scanned elsewhere (the add-contact scanner).
  final String? first;

  /// The QR scanner; replaced in tests.
  final Future<String?> Function({String prompt}) scan;

  @override
  State<GroupImportScreen> createState() => _GroupImportScreenState();
}

class _GroupImportScreenState extends State<GroupImportScreen> {
  var _parts = GroupBundleAssembler();
  GroupBundle? _bundle;
  String? _error, _done, _progress;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final first = widget.first;
    if (first != null) WidgetsBinding.instance.addPostFrameCallback((_) => _take(first));
  }

  /// Adds one part; true when it was taken.
  bool _take(String code) {
    final l = context.l;
    String? error;
    if (!GroupBundleAssembler.isPart(code)) {
      error = l.groupNotPart;
    } else {
      try {
        _parts.add(code);
        if (_parts.complete) _bundle = _parts.bundle();
      } on FormatException catch (e) {
        error = e.message == 'another group bundle' ? l.groupOther : l.groupBroken;
        if (_parts.complete) _parts = GroupBundleAssembler(); // a damaged whole: start over
      }
    }
    setState(() => _error = error);
    return error == null;
  }

  /// Scans part after part until the bundle is whole or the scanner is left.
  Future<void> _scan() async {
    while (mounted && _bundle == null) {
      final l = context.l;
      final prompt = _parts.total == 0 ? l.groupPromptFirst : l.groupPrompt(_parts.next, _parts.total);
      final code = await widget.scan(prompt: prompt);
      if (code == null || !mounted || !_take(code)) return;
    }
  }

  Future<void> _apply() async {
    final b = _bundle!;
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.messaging.importGroup(b, progress: (done, total) {
        if (mounted) setState(() => _progress = l.groupWorking(done, total));
      });
      if (!mounted) return;
      if (r == null) {
        _error = l.groupNotMember;
      } else {
        _done = r.nothing ? l.groupNoChange : l.groupDone(r.added, r.changed, r.same, r.newTeams);
        if (r.phone != null) {
          // As in the settings: layer E needs the SMS permissions and a fresh look at the SIM
          try {
            await Permissions.request(const ['android.permission.SEND_SMS', 'android.permission.RECEIVE_SMS']);
            await widget.messaging.transport<SmsTransport>()?.refresh();
          } catch (_) {
            // The number is set; SMS comes once allowed (settings)
          }
        }
      }
    } catch (e) {
      // Whatever went wrong is shown; the button stays for another try
      _error = l.groupFailed('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _restart() => setState(() {
        _parts = GroupBundleAssembler();
        _bundle = null;
        _error = _done = null;
      });

  Widget _summary(GroupBundle b) {
    final l = context.l;
    final self = b.indexOf(widget.messaging.session.identity.publicKey);
    final mine = [
      for (final (i, t) in b.teams.indexed)
        if (self != null && t.members.contains(self)) (i, t),
    ];
    final lora = b.loraTeam;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: l.groupContacts(b.members.length - (self == null ? 0 : 1)),
        child: Text(
          [for (final (i, m) in b.members.indexed) if (i != self) m.name].join(', '),
          style: const TextStyle(color: L0ckColors.data),
        ),
      ),
      Panel(
        title: l.groupTeamsFor,
        child: Text(mine.isEmpty ? l.groupNoTeams : mine.map((e) => e.$2.name).join(', '),
            style: const TextStyle(color: L0ckColors.data)),
      ),
      if (lora != null && mine.any((e) => e.$1 == lora))
        Text(l.groupLora(b.teams[lora].name), style: const TextStyle(color: L0ckColors.text)),
      if (widget.messaging.ownPhoneFrom(b) case final phone?)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(l.groupOwnPhone(phone), style: const TextStyle(color: L0ckColors.text)),
        ),
      if (b.pace != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(l.groupPace(b.pace!.map((p) => layerName(l, p)).join(' → ')),
              style: const TextStyle(color: L0ckColors.text)),
        ),
      const SizedBox(height: 16),
      if (self == null)
        Text(l.groupNotMember, style: const TextStyle(color: L0ckColors.red))
      else if (_done == null)
        FilledButton.icon(
          key: const Key('group-apply'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.download_done),
          label: Text(l.groupApply),
          onPressed: _busy ? null : _apply,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final b = _bundle;
    return Scaffold(
      appBar: AppBar(title: Text(l.groupBundle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(_progress!, key: const Key('group-working'), style: const TextStyle(color: L0ckColors.orange)),
          ),
        if (b == null) ...[
          Text(l.groupHelp, style: const TextStyle(color: L0ckColors.text)),
          const SizedBox(height: 16),
          if (_parts.total > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(l.groupProgress(_parts.have, _parts.total),
                  key: const Key('group-progress'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: L0ckColors.orange, fontSize: 18)),
            ),
          FilledButton.icon(
            key: const Key('group-scan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l.groupScan),
            onPressed: _scan,
          ),
        ] else
          _summary(b),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: L0ckColors.red)),
          ),
        if (_done != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_done!,
                key: const Key('group-done'), style: const TextStyle(color: L0ckColors.greenLight, fontSize: 16)),
          ),
        if (_parts.total > 0 && _done == null)
          TextButton(onPressed: _restart, child: Text(l.groupAgain)),
      ]),
    );
  }
}
