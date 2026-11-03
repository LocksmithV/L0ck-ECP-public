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
import 'recipients.dart';
import 'reports.dart';
import 'settings_screen.dart';
import 'teams_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home in the original L0ck-ECP look: brand bar, COMMS strip in PACE order, new messages,
/// identity, each channel with its state, and buttons for reports, the own contact card,
/// contacts and teams.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.messaging, required this.security});

  final MessagingService messaging;
  final SecurityService security;

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

  Widget _settings() => SettingsScreen(messaging: messaging, security: security);

  /// A report to anyone: the form first, then the recipients (teams and contacts together).
  void _report(BuildContext context) => showReportMenu(context, (type, payload) async {
        final to = await Navigator.of(context)
            .push<Recipients>(MaterialPageRoute(builder: (_) => RecipientPicker(messaging: messaging)));
        if (to == null) throw const SendCancelled();
        for (final id in to.teams) {
          await messaging.sendTeamPayload(id, type, payload);
        }
        for (final id in to.contacts) {
          await messaging.sendPayload(id, type, payload);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.l.sentToN(to.teams.length + to.contacts.length))));
        }
      });

  Widget _channel(BuildContext context, ({String status, bool up}) c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Dot(c.up ? L0ckColors.ok : L0ckColors.amber, size: 9),
          const SizedBox(width: 10),
          Expanded(
            child: Text(c.status,
                key: const Key('channel'), style: TextStyle(color: c.up ? L0ckColors.text : L0ckColors.dim)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: c.up ? L0ckColors.ok : L0ckColors.amber, width: 0.8),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(c.up ? context.l.chConnected : context.l.chNoLink,
                style: TextStyle(
                    color: c.up ? L0ckColors.ok : L0ckColors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
        ]),
      );

  Widget _button(IconData icon, String label, VoidCallback onTap, {Key? key, bool main = false}) =>
      main
          ? FilledButton.icon(
              key: key,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: Icon(icon),
              label: Text(label),
              onPressed: onTap,
            )
          : OutlinedButton.icon(
              key: key,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: Icon(icon),
              label: FittedBox(child: Text(label)),
              onPressed: onTap,
            );

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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final c in messaging.channelStates) _channel(context, c),
                if (messaging.channelStates.isEmpty)
                  Text(context.l.noChannel, style: const TextStyle(color: L0ckColors.dim)),
              ]),
            ),
            _button(Icons.assignment_outlined, context.l.reportButton, () => _report(context),
                key: const Key('home-reports'), main: true),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _button(Icons.qr_code_2, context.l.myContact,
                    () => _open(context, _MyContactScreen(link: link)),
                    key: const Key('home-my-contact')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StreamBuilder<List<Contact>>(
                  stream: session.db.watchContacts(),
                  builder: (_, s) => _button(Icons.people_outline,
                      context.l.contactsButton('${s.data?.length ?? '…'}'),
                      () => _open(context, ContactsScreen(messaging: messaging))),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _button(Icons.groups_outlined, context.l.teams, () => _open(context, TeamsScreen(messaging: messaging))),
          ]),
        ),
      ]),
    );
  }
}

/// The own contact card: QR code and link, shown in person only.
class _MyContactScreen extends StatelessWidget {
  const _MyContactScreen({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.l.myContact),
          actions: [
            IconButton(
              tooltip: context.l.copyMyLink,
              icon: const Icon(Icons.copy, color: L0ckColors.greenLight),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.linkCopied)));
                }
              },
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(data: link, size: 260),
            ),
          ),
          const SizedBox(height: 12),
          Text(context.l.showInPersonOnly, textAlign: TextAlign.center, style: const TextStyle(color: L0ckColors.dim)),
          const SizedBox(height: 8),
          SelectableText(link,
              key: const Key('my-link'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: L0ckColors.dim)),
        ]),
      );
}
