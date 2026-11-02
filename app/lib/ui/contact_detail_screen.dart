import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/bramble_transport.dart';
import '../messaging/messaging_service.dart';
import '../messaging/simplex_app_transport.dart';
import '../platform/radio.dart';
import 'theme.dart';
import 'widgets.dart';

/// Everything about one contact: verification, channels, the first Bluetooth link, their
/// card as QR, rename and delete.
class ContactDetailScreen extends StatefulWidget {
  const ContactDetailScreen({super.key, required this.messaging, required this.contactId});

  final MessagingService messaging;
  final int contactId;

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  String? _bt;

  MessagingService get m => widget.messaging;

  void _say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _rename(Contact c) async {
    final name = TextEditingController(text: c.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(context.l.renameContact),
        content: TextField(controller: name, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l.save)),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) await m.renameContact(c.id, name.text.trim());
  }

  Future<void> _delete(Contact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(context.l.deleteContactQ(c.name)),
        content: Text(context.l.deleteContactText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l.cancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: L0ckColors.red.withValues(alpha: 0.3)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await m.deleteContact(c.id);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _bluetooth() async {
    final t = m.transport<BrambleTransport>();
    if (t == null) return _say(context.l.brambleNotRunning);
    if (!await Permissions.bluetooth()) return _say(context.l.needNearbyPermission);
    setState(() => _bt = context.l.makingVisible);
    if (!await requestDiscoverable()) {
      setState(() => _bt = null);
      return _say(context.l.noVisibility);
    }
    setState(() => _bt = context.l.searchingBt);
    final r = await t.connectBluetooth('${widget.contactId}');
    if (!mounted) return;
    setState(() => _bt = switch (r) {
          'connected' => context.l.btConnected,
          'no-uuid' => context.l.btNoUuid,
          'not-found' => context.l.btNotFound,
          null => context.l.btNotBramble,
          final s when s.startsWith('unavailable') =>
            context.l.btUnavailable(s),
          final s => context.l.unexpectedResult(s),
        });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Contact?>(
        stream: m.session.db.watchContact(widget.contactId),
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) return const Scaffold(body: SizedBox());
          final id = '${c.id}';
          final bramble = m.transport<BrambleTransport>();
          final links = bramble?.linksTo(id) ?? const <String>{};
          final card = ContactCard(
            name: c.name,
            ecpKey: c.ecpKey,
            briarLink: c.briarLink,
            simplexLink: c.simplexLink,
            phone: c.phone,
          ).toUri();
          return Scaffold(
            appBar: AppBar(title: Text(c.name), actions: [
              IconButton(tooltip: context.l.rename, icon: const Icon(Icons.edit), onPressed: () => _rename(c)),
            ]),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              Panel(
                title: context.l.verification,
                child: FutureBuilder<String>(
                  future: m.verificationFor(c),
                  builder: (_, v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.data ?? '…', style: const TextStyle(fontSize: 24, color: L0ckColors.orange)),
                    Text(
                        c.verified
                            ? context.l.verifiedInPersonDot
                            : context.l.notVerifiedExplain,
                        style: TextStyle(color: c.verified ? L0ckColors.ok : L0ckColors.dim)),
                    TextButton(
                      onPressed: () => m.setVerified(c.id, !c.verified),
                      child: Text(c.verified ? context.l.unverify : context.l.markVerified),
                    ),
                  ]),
                ),
              ),
              Panel(
                title: context.l.channels,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _row('SimpleX', c.simplexLink == null
                      ? context.l.missingOnCard
                      : (m.transport<SimplexAppTransport>()?.canReach(id) ?? false) ? context.l.connected : context.l.connecting),
                  _row('Tor/Bramble', c.briarLink == null
                      ? context.l.missingOnCard
                      : !(bramble?.canReach(id) ?? false)
                          ? context.l.connecting
                          : links.isEmpty
                              ? context.l.contactNoLink
                              : context.l.linksNow(links.join(', '))),
                  _row('SMS', c.phone ?? context.l.noPhone),
                  _row('LoRa', context.l.loraEveryone),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(context.l.connectBluetooth),
                    onPressed: _bt != null && _bt!.endsWith('…') ? null : _bluetooth,
                  ),
                  Text(context.l.connectBluetoothHelp,
                      style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
                  if (_bt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_bt!, style: const TextStyle(color: L0ckColors.greenLight)),
                    ),
                ]),
              ),
              Panel(
                title: context.l.contactCard,
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.white,
                    child: QrImageView(data: card, size: 200),
                  ),
                  const SizedBox(height: 6),
                  Text(context.l.theirCard, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
                  SelectableText(card, style: const TextStyle(color: L0ckColors.dim, fontSize: 9)),
                ]),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: L0ckColors.red, side: const BorderSide(color: L0ckColors.red)),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.l.deleteContact),
                onPressed: () => _delete(c),
              ),
            ]),
          );
        },
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: L0ckColors.greenLight))),
          Expanded(child: Text(v, style: const TextStyle(color: L0ckColors.text))),
        ]),
      );
}
