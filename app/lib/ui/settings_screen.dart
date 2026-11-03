import 'dart:convert';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import '../messaging/panic.dart';
import 'about_screen.dart';
import '../messaging/sms_transport.dart';
import '../platform/biometric.dart';
import '../platform/radio.dart';
import '../security/lock_config.dart';
import '../security/security_service.dart';
import 'quick_lock.dart';
import 'radio_screen.dart';
import 'reports.dart' show statusLabel;
import 'theme.dart';
import 'widgets.dart';

String layerName(AppLocalizations l, PaceLayer layer) => switch (layer) {
      PaceLayer.primary => 'SimpleX',
      PaceLayer.alternate => l.layerAlternate,
      PaceLayer.contingency => l.layerContingency,
      PaceLayer.emergency => 'SMS',
    };

/// Country codes offered for the own number.
const _prefixes = ['+420', '+421', '+48', '+49', '+43', '+36', '+380', '+44', '+1'];

String _country(AppLocalizations l, String prefix) => switch (prefix) {
      '+420' => l.cz,
      '+421' => l.sk,
      '+48' => l.pl,
      '+49' => l.de,
      '+43' => l.at,
      '+36' => l.hu,
      '+380' => l.ua,
      '+44' => l.uk,
      _ => l.us,
    };

/// Settings in three sections that open one at a time — security, connectivity, the app —
/// and About. PIN and duress code can be changed but never shown: they are not stored
/// anywhere, only the keys derived from them.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.messaging, required this.security, required this.onFactoryReset});

  final MessagingService messaging;
  final SecurityService security;

  /// Erases everything on this phone; the app returns to the first-start setup.
  final Future<void> Function() onFactoryReset;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _prefix;
  final _number = TextEditingController();
  bool _busy = false;

  /// The open section, if any.
  String? _section;

  @override
  void initState() {
    super.initState();
    final own = widget.messaging.ownPhone ?? '';
    final p = _prefixes.where((k) => own.startsWith(k)).fold<String?>(
        null, (best, k) => best == null || k.length > best.length ? k : best);
    _prefix = p ?? '+420';
    _number.text = p == null ? own : own.substring(p.length).trim();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _savePhone() async {
    final digits = _number.text.replaceAll(RegExp(r'[^0-9]'), '');
    final number = digits.isEmpty ? null : '$_prefix $digits';
    await widget.messaging.setOwnPhone(number);
    await Permissions.request(const ['android.permission.SEND_SMS', 'android.permission.RECEIVE_SMS']);
    await widget.messaging.transport<SmsTransport>()?.refresh();
    _say(number == null ? context.l.numberRemoved : context.l.numberSaved);
    setState(() {});
  }

  /// One dialog with code fields; returns their values, or null when cancelled.
  Future<List<String>?> _ask(String title, List<String> labels, {String? note, bool pins = true}) {
    final fields = [for (final _ in labels) TextEditingController()];
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(note, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
              ),
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: pins
                    ? PinField(controller: fields[i], label: labels[i])
                    : TextField(controller: fields[i], decoration: InputDecoration(labelText: labels[i])),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, [for (final f in fields) f.text]),
              child: Text(context.l.confirm)),
        ],
      ),
    );
  }

  Future<void> _run(Future<String?> Function() op, String done) async {
    setState(() => _busy = true);
    final err = await op();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(err ?? done);
  }

  Future<void> _rename() async {
    final name = TextEditingController(text: widget.messaging.session.nickname);
    final duress = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(context.l.nickname),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: context.l.nickname)),
          const SizedBox(height: 10),
          PinField(controller: duress, label: context.l.duressOptional),
          const SizedBox(height: 6),
          Text(context.l.renameDecoyHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l.save)),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final err = await widget.security.rename(widget.messaging.session, name.text,
          duress: duress.text.isEmpty ? null : duress.text);
      if (err == null) await widget.messaging.profileChanged();
      return err;
    }, context.l.nicknameChanged);
    setState(() {});
  }

  Future<void> _changePin() async {
    final l = context.l;
    final v = await _ask(l.changePin, [l.currentPin, l.newPin, l.newPinAgain]);
    if (v == null) return;
    if (v[1] != v[2]) return _say(l.newPinsMismatch);
    await _run(
        () => widget.security.changePin(widget.messaging.session, current: v[0], newPin: v[1]),
        l.pinChanged);
  }

  Future<void> _setDuress({required bool remove}) async {
    final l = context.l;
    final v = remove
        ? await _ask(l.removeDuress, [l.currentPin], note: l.removeDuressNote)
        : await _ask(l.newDuress, [l.currentPin, l.newDuress, l.newDuressAgain], note: l.newDuressNote);
    if (v == null) return;
    if (!remove && v[1] != v[2]) return _say(l.duressCodesMismatch);
    await _run(
        () => widget.security.setDuress(widget.messaging.session,
            current: v[0], duress: remove ? null : v[1]),
        remove ? l.duressRemoved : l.duressSet);
  }

  /// A section header that opens [children] below it; opening one closes the others.
  Widget _group(String id, IconData icon, String title, String subtitle, List<Widget> children) {
    final open = _section == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: L0ckColors.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: open ? L0ckColors.green : L0ckColors.border, width: open ? 1 : 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            key: Key('section-$id'),
            leading: Icon(icon, color: open ? L0ckColors.orange : L0ckColors.greenLight),
            title: Text(title,
                style: const TextStyle(color: L0ckColors.data, fontSize: 16, fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
            trailing: Icon(open ? Icons.expand_less : Icons.expand_more, color: L0ckColors.greenLight),
            onTap: () => setState(() => _section = open ? null : id),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
      ]),
    );
  }

  /// The button only asks; the dialog's red button erases.
  Future<void> _factoryReset() async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(l.factoryResetAsk),
        content: Text(l.factoryResetHelp, style: const TextStyle(color: L0ckColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
            key: const Key('factory-reset-confirm'),
            style: FilledButton.styleFrom(backgroundColor: L0ckColors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.factoryResetConfirm),
          ),
        ],
      ),
    );
    if (ok == true) await widget.onFactoryReset();
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final m = widget.messaging;
    final l = context.l;
    void changed() => setState(() {});
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const L0ckTitle(),
            const SizedBox(width: 10),
            Text(l.settings, style: const TextStyle(color: L0ckColors.text, fontSize: 17)),
          ]),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (_busy) const LinearProgressIndicator(),
          _group('security', Icons.shield_outlined, l.secSecurity, l.secSecuritySub, [
            Panel(
              title: l.pinCodes,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.pinNotStored, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _changePin, child: Text(l.changePin)),
                OutlinedButton(onPressed: () => _setDuress(remove: false), child: Text(l.setNewDuress)),
                OutlinedButton(onPressed: () => _setDuress(remove: true), child: Text(l.removeDuress)),
              ]),
            ),
            _LockPanel(messaging: m, onChanged: changed),
            _PanicPanel(messaging: m, onChanged: changed),
          ]),
          _group('net', Icons.cell_tower, l.secConnectivity, l.secConnectivitySub, [
            Panel(
              title: l.smsNumberLayer,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  DropdownButton<String>(
                    value: _prefix,
                    dropdownColor: L0ckColors.panel,
                    items: [
                      for (final p in _prefixes) DropdownMenuItem(value: p, child: Text('$p  ${_country(l, p)}')),
                    ],
                    selectedItemBuilder: (_) => [for (final k in _prefixes) Center(child: Text(k))],
                    onChanged: (v) => setState(() => _prefix = v!),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _number,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: l.number),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(l.simChangeHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
                const SizedBox(height: 8),
                FilledButton(onPressed: _savePhone, child: Text(l.saveNumber)),
              ]),
            ),
            Panel(
              title: l.paceOrder,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.paceOrderHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) {
                    final order = [...m.paceOrder];
                    order.insert(to, order.removeAt(from));
                    m.setPaceOrder(order).then((_) => setState(() {}));
                  },
                  children: [
                    for (final (i, layer) in m.paceOrder.indexed)
                      ListTile(
                        key: ValueKey(layer),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text('${i + 1}', style: const TextStyle(color: L0ckColors.orange, fontSize: 16)),
                        title: Text(layerName(l, layer), style: const TextStyle(color: L0ckColors.text)),
                        trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                      ),
                  ],
                ),
                TextButton(
                  onPressed: () => m.setPaceOrder(PaceProfile.evasion.order).then((_) => setState(() {})),
                  child: Text(l.paceDefault),
                ),
              ]),
            ),
            _ReconnectPanel(messaging: m),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.settings_input_antenna),
                label: Text(l.loraRadio),
                onPressed: () => _push(RadioScreen(messaging: m)),
              ),
            ),
          ]),
          _group('app', Icons.tune, l.secApp, l.secAppSub, [
            Panel(
              title: l.profile,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.session.nickname,
                    style: const TextStyle(color: L0ckColors.data, fontWeight: FontWeight.bold)),
                subtitle: Text(l.nicknameOnCard, style: const TextStyle(color: L0ckColors.dim)),
                trailing: const Icon(Icons.edit),
                onTap: _rename,
              ),
            ),
            Panel(
              title: l.language,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cs', label: Text('Čeština')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {Lang.current.value.languageCode},
                onSelectionChanged: (v) async {
                  await Lang.set(Locale(v.first));
                  widget.messaging.channelsChanged.value++; // channel lines in the new language
                },
              ),
            ),
            Panel(
              title: l.factoryReset,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.factoryResetHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('factory-reset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: L0ckColors.red,
                    side: const BorderSide(color: L0ckColors.red),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l.factoryResetButton),
                  onPressed: _factoryReset,
                ),
              ]),
            ),
          ]),
          Container(
            decoration: BoxDecoration(
              color: L0ckColors.panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: L0ckColors.border, width: 0.5),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                key: const Key('about'),
                leading: const Icon(Icons.info_outline, color: L0ckColors.greenLight),
                title: Text(l.about,
                    style: const TextStyle(color: L0ckColors.data, fontSize: 16, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.chevron_right, color: L0ckColors.greenLight),
                onTap: () => _push(const AboutScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

/// When the app locks, the emergency lock and the fingerprint. Locking only by hand needs the
/// four taps; the fingerprint needs PANIC and KOMPROMITOVÁN on the PIN screen.
class _LockPanel extends StatefulWidget {
  const _LockPanel({required this.messaging, required this.onChanged});
  final MessagingService messaging;
  final VoidCallback onChanged;

  @override
  State<_LockPanel> createState() => _LockPanelState();
}

class _LockPanelState extends State<_LockPanel> {
  bool? _sensor;

  @override
  void initState() {
    super.initState();
    Biometric.available().then((v) {
      if (mounted) setState(() => _sensor = v);
    });
  }

  LockConfig get _c => widget.messaging.lock;

  Future<void> _save(LockConfig c) async {
    await widget.messaging.setLock(c);
    widget.onChanged();
  }

  /// Switching it on takes one fingerprint, so it is known to work before it is needed.
  Future<void> _biometric(bool on) async {
    final l = context.l;
    if (on && !await Biometric.authenticate(title: l.bioTitle, cancel: l.cancel)) return;
    await _save(_c.copyWith(biometric: on));
  }

  String _label(AppLocalizations l, Duration? d) => switch (d) {
        null => l.lockManual,
        Duration.zero => l.lockNow,
        _ => l.lockMinutes(d.inMinutes),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l, c = _c, p = widget.messaging.panic;
    final panicOn = p.button && p.compromiseButton;
    return Panel(
      title: l.lockTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<int>(
          key: const Key('lock-after'),
          initialValue: c.after?.inSeconds ?? -1,
          dropdownColor: L0ckColors.panel,
          decoration: InputDecoration(labelText: l.lockAfter),
          items: [
            for (final d in LockConfig.choices)
              DropdownMenuItem(value: d?.inSeconds ?? -1, child: Text(_label(l, d))),
          ],
          onChanged: (s) => _save(c.withAfter(s == null || s < 0 ? null : Duration(seconds: s))),
        ),
        const SizedBox(height: 6),
        Text(l.lockHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
        const Divider(color: L0ckColors.border),
        SwitchListTile(
          key: const Key('quick-lock'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.emergencyLock, style: const TextStyle(color: L0ckColors.text)),
          subtitle: Text(c.after == null ? l.quickLockNeeded : l.emergencyLockHelp(QuickLock.taps),
              style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
          value: c.quickLock,
          onChanged: c.after == null ? null : (v) => _save(c.copyWith(quickLock: v)),
        ),
        const Divider(color: L0ckColors.border),
        SwitchListTile(
          key: const Key('biometric-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fingerprint, color: L0ckColors.greenLight),
          title: Text(l.bioTitle, style: const TextStyle(color: L0ckColors.text)),
          subtitle: Text(
              _sensor == false && !c.biometric
                  ? l.bioUnavailable
                  : !panicOn && !c.biometric
                      ? l.bioNeedsPanic
                      : l.bioHelp(LockConfig.biometricFor.inHours),
              style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
          value: c.biometric,
          onChanged: c.biometric || (_sensor == true && panicOn) ? _biometric : null,
        ),
      ]),
    );
  }
}

/// What the PIN screen's PANIC and KOMPROMITOVÁN do. Saved as soon as something changes.
class _PanicPanel extends StatefulWidget {
  const _PanicPanel({required this.messaging, required this.onChanged});
  final MessagingService messaging;
  final VoidCallback onChanged;

  @override
  State<_PanicPanel> createState() => _PanicPanelState();
}

class _PanicPanelState extends State<_PanicPanel> {
  late PanicConfig _c = widget.messaging.panic;
  late final _text = TextEditingController(text: _c.text);

  int get _bytes => utf8.encode(_text.text.trim()).length;

  Future<void> _save(PanicConfig c) async {
    setState(() => _c = c);
    await widget.messaging.setPanic(c);
    widget.onChanged();
  }

  Widget _switch(String title, bool value, ValueChanged<bool>? on, {String? note}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title, style: const TextStyle(color: L0ckColors.text)),
        subtitle: note == null ? null : Text(note, style: const TextStyle(color: L0ckColors.orange, fontSize: 12)),
        value: value,
        onChanged: on,
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // The fingerprint has no duress code: both buttons stay while it unlocks
    final held = widget.messaging.lock.biometric;
    return Panel(
      title: l.panicTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.panicHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
        _switch(l.panicButtonOn, _c.button, held ? null : (v) => _save(_c.copyWith(button: v)),
            note: held ? l.bioLocksPanic : null),
        DropdownButtonFormField<StatusCode>(
          initialValue: _c.status,
          dropdownColor: L0ckColors.panel,
          decoration: InputDecoration(labelText: l.panicStatus),
          items: [
            for (final st in StatusCode.values)
              if (st != StatusCode.ok) DropdownMenuItem(value: st, child: Text(statusLabel(st))),
          ],
          onChanged: (v) => _save(_c.copyWith(status: v)),
        ),
        TextField(
          controller: _text,
          maxLines: null,
          decoration: InputDecoration(
            labelText: l.panicText,
            counterText: l.textBudget(_bytes, maxReportText),
            errorText: _bytes > maxReportText ? l.tooLongLora : null,
          ),
          onChanged: (t) {
            setState(() {});
            if (utf8.encode(t.trim()).length <= maxReportText) _save(_c.copyWith(text: t.trim()));
          },
        ),
        _switch(l.attachPosition, _c.position, (v) => _save(_c.copyWith(position: v))),
        _switch(l.panicToContacts, _c.contacts, (v) => _save(_c.copyWith(contacts: v))),
        _switch(l.panicToTeams, _c.teams, (v) => _save(_c.copyWith(teams: v))),
        const Divider(color: L0ckColors.border),
        _switch(l.compromiseOn, _c.compromiseButton,
            held ? null : (v) => _save(_c.copyWith(compromiseButton: v)),
            note: held ? l.bioLocksPanic : null),
        Text(l.compromiseHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
      ]),
    );
  }
}

/// "Obnovit spojení": after mobile data, Wi-Fi or Bluetooth dropped and came back, a channel
/// can be restarted by hand instead of waiting for it to notice.
class _ReconnectPanel extends StatefulWidget {
  const _ReconnectPanel({required this.messaging});

  final MessagingService messaging;

  @override
  State<_ReconnectPanel> createState() => _ReconnectPanelState();
}

class _ReconnectPanelState extends State<_ReconnectPanel> {
  Map<String, String> get _channels => {
        'simplex': 'SimpleX',
        'tor': 'Tor (Bramble)',
        'lan': 'Wi-Fi / LAN (Bramble)',
        'bluetooth': 'Bluetooth (Bramble)',
        'lora': context.l.loraRadioShort,
        'sms': 'SMS',
      };
  final Map<String, String> _result = {};
  final Set<String> _busy = {};

  Future<void> _refresh(String k) async {
    setState(() => _busy.add(k));
    final r = await widget.messaging.refreshChannel(k);
    if (!mounted) return;
    setState(() {
      _busy.remove(k);
      _result[k] = r;
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: widget.messaging.channelsChanged,
        builder: (_, _, _) => Panel(
          title: context.l.reconnect,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final line in widget.messaging.channelStatus)
              Text(line, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
            const SizedBox(height: 6),
            for (final e in _channels.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.value, style: const TextStyle(color: L0ckColors.text)),
                subtitle: _result[e.key] == null
                    ? null
                    : Text(_result[e.key]!, style: const TextStyle(color: L0ckColors.greenLight)),
                trailing: _busy.contains(e.key)
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        tooltip: context.l.reconnectOne(e.value),
                        icon: const Icon(Icons.refresh, color: L0ckColors.greenLight),
                        onPressed: () => _refresh(e.key),
                      ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.sync),
              label: Text(context.l.reconnectAll),
              onPressed: _busy.isNotEmpty
                  ? null
                  : () async {
                      for (final k in _channels.keys) {
                        await _refresh(k);
                      }
                    },
            ),
          ]),
        ),
      );
}
