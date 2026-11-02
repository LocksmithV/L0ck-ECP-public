import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import 'about_screen.dart';
import '../messaging/sms_transport.dart';
import '../platform/radio.dart';
import '../security/security_service.dart';
import 'quick_lock.dart';
import 'theme.dart';
import 'widgets.dart';

String _layerName(AppLocalizations l, PaceLayer layer) => switch (layer) {
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

/// Settings: name, own number for SMS, PIN and duress code, and the emergency lock. PIN and
/// duress code can be changed but never shown — they are not stored anywhere, only the keys
/// derived from them.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.messaging,
    required this.security,
    required this.onLock,
  });

  final MessagingService messaging;
  final SecurityService security;
  final VoidCallback onLock;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _prefix;
  final _number = TextEditingController();
  bool _busy = false;

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

  @override
  Widget build(BuildContext context) {
    final m = widget.messaging;
    return Scaffold(
      appBar: AppBar(title: Text(context.l.settings)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (_busy) const LinearProgressIndicator(),
          Panel(
            title: context.l.profile,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.session.nickname,
                  style: const TextStyle(color: L0ckColors.data, fontWeight: FontWeight.bold)),
              subtitle: Text(context.l.nicknameOnCard, style: const TextStyle(color: L0ckColors.dim)),
              trailing: const Icon(Icons.edit),
              onTap: _rename,
            ),
          ),
          Panel(
            title: context.l.smsNumberLayer,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                DropdownButton<String>(
                  value: _prefix,
                  dropdownColor: L0ckColors.panel,
                  items: [
                    for (final p in _prefixes)
                      DropdownMenuItem(value: p, child: Text('$p  ${_country(context.l, p)}')),
                  ],
                  selectedItemBuilder: (_) => [for (final k in _prefixes) Center(child: Text(k))],
                  onChanged: (v) => setState(() => _prefix = v!),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: context.l.number),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(context.l.simChangeHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _savePhone, child: Text(context.l.saveNumber)),
            ]),
          ),
          _ReconnectPanel(messaging: m),
          Panel(
            title: context.l.paceOrder,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.l.paceOrderHelp, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
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
                  for (final (i, l) in m.paceOrder.indexed)
                    ListTile(
                      key: ValueKey(l),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text('${i + 1}', style: const TextStyle(color: L0ckColors.orange, fontSize: 16)),
                      title: Text(_layerName(context.l, l), style: const TextStyle(color: L0ckColors.text)),
                      trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    ),
                ],
              ),
              TextButton(
                onPressed: () => m.setPaceOrder(PaceProfile.evasion.order).then((_) => setState(() {})),
                child: Text(context.l.paceDefault),
              ),
            ]),
          ),
          Panel(
            title: context.l.security,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.l.pinNotStored, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _changePin, child: Text(context.l.changePin)),
              OutlinedButton(
                  onPressed: () => _setDuress(remove: false),
                  child: Text(context.l.setNewDuress)),
              OutlinedButton(
                  onPressed: () => _setDuress(remove: true), child: Text(context.l.removeDuress)),
            ]),
          ),
          Panel(
            title: context.l.emergencyLock,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.l.emergencyLockHelp(QuickLock.taps), style: const TextStyle(color: L0ckColors.text)),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: L0ckColors.red.withValues(alpha: 0.25),
                  side: const BorderSide(color: L0ckColors.red),
                  minimumSize: const Size.fromHeight(64),
                ),
                icon: const Icon(Icons.lock, size: 28),
                label: Text(context.l.lockAndHide, style: const TextStyle(fontSize: 16)),
                onPressed: () {
                  widget.onLock();
                  QuickLock.minimize().ignore();
                },
              ),
            ]),
          ),
          Panel(
            title: context.l.language,
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
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline),
            label: Text(context.l.about),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          const SizedBox(height: 24),
        ]),
      ),
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
