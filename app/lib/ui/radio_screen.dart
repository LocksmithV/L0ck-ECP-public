import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_meshcore/ecp_meshcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/lang.dart';
import '../messaging/meshcore_app_transport.dart';
import '../messaging/messaging_service.dart';
import '../platform/radio.dart';
import 'theme.dart';

/// PACE layer C: which MeshCore radio (paired over Bluetooth) and which LoRa channel. The
/// radio's own settings (frequency, preset, path hashes) stay as the local mesh uses them,
/// so community repeaters carry ECP traffic too.
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key, required this.messaging});

  final MessagingService messaging;

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  static const _radio = NativeRadio();
  List<PairedDevice>? _paired;
  String? _selected, _message;
  final _key = TextEditingController();

  MeshCoreAppTransport? get _t => widget.messaging.transport<MeshCoreAppTransport>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.messaging.session.db;
    _selected = await db.setting(radioAddressKey);
    if (!await Permissions.bluetooth()) {
      setState(() => _message = context.l.noBtPermissionRadio);
      return;
    }
    final paired = await _radio.paired();
    if (mounted) setState(() => _paired = paired);
  }

  Future<void> _use(PairedDevice d) async {
    await widget.messaging.session.db.setSetting(radioAddressKey, d.address);
    await _radio.connect(d.address);
    setState(() => _selected = d.address);
  }

  Future<void> _forget() async {
    await widget.messaging.session.db.setSetting(radioAddressKey, null);
    await _radio.disconnect();
    setState(() => _selected = null);
  }

  Future<void> _setChannel(List<int>? key) async {
    final t = _t;
    if (t == null) return;
    final k = key ?? MeshCoreTransport.defaultChannelSecret;
    await widget.messaging.session.db
        .setSetting(radioChannelKey, key == null ? null : encodeChannelKey(k));
    try {
      await t.setChannelSecret(k);
      setState(() => _message = key == null ? context.l.commonEcpChannel : context.l.groupChannelSet);
    } catch (e) {
      setState(() => _message = context.l.radioRejectedChannel('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l.loraRadio)),
      body: ValueListenableBuilder<int>(
        valueListenable: widget.messaging.channelsChanged,
        builder: (context, _, _) => ListView(padding: const EdgeInsets.all(20), children: [
          _status(),
          const SizedBox(height: 20),
          Text(context.l.meshcoreRadioPaired, style: const TextStyle(color: L0ckColors.greenLight)),
          if (_paired == null && _message == null) const LinearProgressIndicator(),
          for (final d in _paired ?? const <PairedDevice>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(d.address == _selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: L0ckColors.green),
              onTap: () => _use(d),
              title: Text(d.name.isEmpty ? d.address : d.name),
              subtitle: Text(d.address, style: const TextStyle(color: L0ckColors.dim)),
            ),
          if (_paired != null && _paired!.isEmpty)
            Text(context.l.noPairedDevice, style: const TextStyle(color: L0ckColors.dim)),
          if (_selected != null)
            TextButton(onPressed: _forget, child: Text(context.l.forgetRadio)),
          const SizedBox(height: 20),
          ..._channel(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, style: const TextStyle(color: L0ckColors.orange)),
            ),
        ]),
      ),
    );
  }

  Widget _status() {
    final t = _t;
    final r = t?.radio, d = t?.device;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t?.status ?? context.l.loraUnavailable, key: const Key('lora-status'),
          style: const TextStyle(color: L0ckColors.text)),
      if (t?.isAvailable == true && r != null && d != null)
        Text(context.l.firmwareInfo(d.version, d.maxChannels) +
            (d.pathHashBytes == null ? '' : context.l.pathHash(d.pathHashBytes!)),
            style: const TextStyle(color: L0ckColors.dim)),
      if (t?.error != null) Text(t!.error!, style: const TextStyle(color: L0ckColors.red)),
    ]);
  }

  List<Widget> _channel() {
    final t = _t;
    if (t == null) return const [];
    return [
      Text(context.l.loraChannel, style: const TextStyle(color: L0ckColors.greenLight)),
      Text(
          t.isDefaultChannel
              ? context.l.commonChannelHelp
              : context.l.privateChannelHelp,
          style: const TextStyle(color: L0ckColors.dim)),
      if (!t.isDefaultChannel)
        SelectableText(encodeChannelKey(t.channelSecret),
            key: const Key('channel-key'), style: const TextStyle(color: L0ckColors.orange)),
      Wrap(spacing: 8, children: [
        OutlinedButton(
            onPressed: () => _setChannel(randomBytes(16)), child: Text(context.l.newGroupChannel)),
        if (!t.isDefaultChannel) ...[
          OutlinedButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: encodeChannelKey(t.channelSecret))),
            child: Text(context.l.copyKey),
          ),
          OutlinedButton(onPressed: () => _setChannel(null), child: Text(context.l.backToEcpChannel)),
        ],
      ]),
      TextField(
        controller: _key,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: context.l.groupKeyPaste),
        onSubmitted: (s) {
          final k = decodeChannelKey(s);
          if (k == null) {
            setState(() => _message = context.l.invalidChannelKey);
          } else {
            _key.clear();
            _setChannel(k);
          }
        },
      ),
    ];
  }
}
