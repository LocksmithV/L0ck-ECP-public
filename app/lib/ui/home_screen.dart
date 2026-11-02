import 'package:cryptography/cryptography.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import '../security/security_service.dart';
import 'contacts_screen.dart';
import 'conversation_screen.dart';
import 'radio_screen.dart';
import 'settings_screen.dart';
import 'teams_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home in the original L0ck-ECP look: brand bar, COMMS strip in PACE order, then panels
/// for identity, own contact card and channels. Map, reports and the panic bar come in F5.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.messaging,
    required this.security,
    required this.onLock,
  });

  final MessagingService messaging;
  final SecurityService security;
  final VoidCallback onLock;

  Session get session => messaging.session;

  Future<String> _fingerprint() async {
    final h = await Sha256().hash(session.identity.publicKey);
    final hex = toHex(h.bytes.sublist(0, 8)).toUpperCase();
    return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join(' ');
  }

  /// New messages first: which conversation (contact or team) and how many.
  Widget _unread(BuildContext context) => StreamBuilder<({Map<int, int> contacts, Map<String, int> teams})>(
        stream: session.db.watchUnread(),
        builder: (context, u) {
          final c = u.data?.contacts ?? const {}, t = u.data?.teams ?? const {};
          if (c.isEmpty && t.isEmpty) return const SizedBox();
          return StreamBuilder<List<Contact>>(
            stream: session.db.watchContacts(),
            builder: (context, cs) => StreamBuilder<List<Team>>(
              stream: session.db.watchTeams(),
              builder: (context, ts) => Panel(
                title: context.l.newMessages,
                child: Column(children: [
                  for (final contact in cs.data ?? const <Contact>[])
                    if (c.containsKey(contact.id))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person, color: L0ckColors.orange),
                        title: Text(contact.name, style: const TextStyle(color: L0ckColors.data)),
                        subtitle: Text(context.l.directMessage, style: const TextStyle(color: L0ckColors.dim)),
                        trailing: UnreadBadge(count: c[contact.id]!),
                        onTap: () =>
                            _open(context, ConversationScreen(messaging: messaging, contact: contact)),
                      ),
                  for (final team in ts.data ?? const <Team>[])
                    if (t.containsKey(team.id))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.groups, color: L0ckColors.orange),
                        title: Text(team.name, style: const TextStyle(color: L0ckColors.data)),
                        subtitle: Text(context.l.team, style: const TextStyle(color: L0ckColors.dim)),
                        trailing: UnreadBadge(count: t[team.id]!),
                        onTap: () => _open(context, TeamScreen(messaging: messaging, team: team)),
                      ),
                ]),
              ),
            ),
          );
        },
      );

  Widget _settings() => SettingsScreen(messaging: messaging, security: security, onLock: onLock);

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: messaging.channelsChanged,
      builder: (context, _, _) => _build(context, messaging.myContactUri()),
    );
  }

  Widget _build(BuildContext context, String link) {
    final layers = messaging.layers;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const FittedBox(fit: BoxFit.scaleDown, child: L0ckTitle()),
        actions: [
          IconButton(
            tooltip: context.l.contacts,
            icon: const Icon(Icons.people, size: 20, color: L0ckColors.greenLight),
            onPressed: () => _open(context, ContactsScreen(messaging: messaging)),
          ),
          IconButton(
            tooltip: context.l.teams,
            icon: const Icon(Icons.groups, size: 20, color: L0ckColors.greenLight),
            onPressed: () => _open(context, TeamsScreen(messaging: messaging)),
          ),
          IconButton(
            tooltip: context.l.loraRadio,
            icon: const Icon(Icons.settings_input_antenna, size: 20, color: L0ckColors.green),
            onPressed: () => _open(context, RadioScreen(messaging: messaging)),
          ),
          IconButton(
            tooltip: context.l.settings,
            icon: const Icon(Icons.settings, size: 22, color: L0ckColors.greenLight),
            onPressed: () => _open(context, _settings()),
          ),
        ],
      ),
      body: Column(children: [
        CommsStrip(states: {
          for (final l in PaceLayer.values)
            l: switch (layers[l]) {
              true => LayerState.active,
              false => LayerState.standby,
              null => LayerState.absent,
            },
        }),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            _unread(context),
            Panel(
              title: context.l.identity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.nickname,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: L0ckColors.data)),
                const SizedBox(height: 4),
                FutureBuilder<String>(
                  future: _fingerprint(),
                  builder: (_, s) => Text(context.l.fingerprint(s.data ?? '…'),
                      key: const Key('fingerprint'),
                      style: const TextStyle(color: L0ckColors.greenLight)),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _open(context, _settings()),
                  child: Row(children: [
                    Expanded(
                      child: Text(context.l.smsNumber(messaging.ownPhone ?? context.l.notSet),
                          style: const TextStyle(color: L0ckColors.text)),
                    ),
                    const Icon(Icons.edit, size: 16, color: L0ckColors.dim),
                  ]),
                ),
              ]),
            ),
            Panel(
              title: context.l.channels,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final line in messaging.channelStatus)
                  Text(line, key: const Key('channel'), style: const TextStyle(color: L0ckColors.text)),
                if (messaging.channelStatus.isEmpty)
                  Text(context.l.noChannel, style: const TextStyle(color: L0ckColors.dim)),
              ]),
            ),
            Panel(
              title: context.l.myContact,
              trailing: IconButton(
                tooltip: context.l.copyMyLink,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 18, color: L0ckColors.greenLight),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.linkCopied)));
                  }
                },
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
                  child: QrImageView(data: link, size: 220),
                ),
                const SizedBox(height: 8),
                Text(context.l.showInPersonOnly, style: const TextStyle(color: L0ckColors.dim)),
                const SizedBox(height: 6),
                SelectableText(link,
                    key: const Key('my-link'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: L0ckColors.dim)),
              ]),
            ),
            StreamBuilder<List<Contact>>(
              stream: session.db.watchContacts(),
              builder: (_, s) => FilledButton.icon(
                icon: const Icon(Icons.people_outline),
                label: Text(context.l.contactsButton('${s.data?.length ?? '…'}')),
                onPressed: () => _open(context, ContactsScreen(messaging: messaging)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
