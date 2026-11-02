import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import 'message_bubble.dart';
import 'reports.dart';
import 'theme.dart';
import 'widgets.dart';

/// Teams: messages to everyone in the team at once, over the squad net (Bluetooth/LAN,
/// relayed member to member) and the team's LoRa channel. Joining = scanning a member's
/// team QR in person ("Přidat kontakt").
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key, required this.messaging});

  final MessagingService messaging;

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(context.l.newTeam),
        content: TextField(
            controller: name,
            autofocus: true,
            decoration: InputDecoration(labelText: context.l.teamNameLocal)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l.found)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final t = await messaging.createTeam(name.text.trim().isEmpty ? context.l.teamDefaultName : name.text.trim());
    await messaging.useTeamLoRa(t);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeamScreen(messaging: messaging, team: t, showQr: true)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.l.teams)),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: L0ckColors.greenDark,
          foregroundColor: L0ckColors.text,
          icon: const Icon(Icons.group_add),
          label: Text(context.l.newTeam),
          onPressed: () => _create(context),
        ),
        body: StreamBuilder<({Map<int, int> contacts, Map<String, int> teams})>(
          stream: messaging.session.db.watchUnread(),
          builder: (context, unread) => StreamBuilder<List<Team>>(
          stream: messaging.session.db.watchTeams(),
          builder: (context, snap) {
            final teams = snap.data ?? const [];
            final counts = unread.data?.teams ?? const {};
            if (teams.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.l.noTeams, style: const TextStyle(color: L0ckColors.dim)),
              );
            }
            return ListView(children: [
              for (final t in teams)
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(t.name, style: const TextStyle(color: L0ckColors.text)),
                  subtitle: Text(context.l.teamId(t.id.substring(0, 8)), style: const TextStyle(color: L0ckColors.dim)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if ((counts[t.id] ?? 0) > 0) UnreadBadge(count: counts[t.id]!),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TeamScreen(messaging: messaging, team: t))),
                ),
            ]);
          },
        )),
      );
}

/// One team: its conversation, plus the team QR on demand.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.messaging, required this.team, this.showQr = false});

  final MessagingService messaging;
  final Team team;
  final bool showQr;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.showQr) WidgetsBinding.instance.addPostFrameCallback((_) => _qr());
  }

  void _qr() {
    final link = widget.messaging.teamCardUri(widget.team);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(context.l.teamQrTitle(widget.team.name)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: SizedBox(width: 220, height: 220, child: QrImageView(data: link)),
            ),
            const SizedBox(height: 10),
            Text(context.l.teamQrWarning, style: const TextStyle(color: L0ckColors.orange)),
            const SizedBox(height: 6),
            SelectableText(link,
                key: const Key('team-link'), style: const TextStyle(fontSize: 9, color: L0ckColors.dim)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l.close))],
      ),
    );
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await widget.messaging.sendTeamText(widget.team.id, t);
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(context.l.leaveTeamQ(widget.team.name)),
        content: Text(context.l.leaveTeamText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l.cancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: L0ckColors.red.withValues(alpha: 0.3)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l.leave)),
        ],
      ),
    );
    if (ok != true) return;
    await widget.messaging.leaveTeam(widget.team.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Who gets team messages over SimpleX/Bramble too. Filled in by itself (the member whose
  /// QR you scanned, members who joined through yours, anyone who writes to the team), and
  /// by hand here.
  Future<void> _members() async {
    final db = widget.messaging.session.db;
    final all = await db.select(db.contacts).get();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: L0ckColors.panel,
      builder: (ctx) => StreamBuilder<List<Contact>>(
        stream: db.watchTeamMembers(widget.team.id),
        builder: (ctx, snap) {
          final members = {for (final c in snap.data ?? const <Contact>[]) c.id};
          return SafeArea(
            child: ListView(shrinkWrap: true, children: [
              ListTile(
                title: Text(context.l.teamMembers, style: const TextStyle(color: L0ckColors.data)),
                subtitle: Text(context.l.teamMembersHelp,
                    style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
              ),
              for (final c in all)
                CheckboxListTile(
                  value: members.contains(c.id),
                  title: Text(c.name),
                  onChanged: (on) => on == true
                      ? widget.messaging.addTeamMember(widget.team.id, c.id)
                      : widget.messaging.removeTeamMember(widget.team.id, c.id),
                ),
              if (all.isEmpty)
                ListTile(title: Text(context.l.noContactsYet, style: const TextStyle(color: L0ckColors.dim))),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.team.name), actions: [
          IconButton(tooltip: context.l.members, icon: const Icon(Icons.group), onPressed: _members),
          IconButton(tooltip: context.l.teamQr, icon: const Icon(Icons.qr_code), onPressed: _qr),
          PopupMenuButton<String>(
            color: L0ckColors.panel,
            onSelected: (_) => _leave(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'leave', child: Text(context.l.leaveTeamMenu)),
            ],
          ),
        ]),
        body: Column(children: [
          ValueListenableBuilder<int>(
            valueListenable: widget.messaging.channelsChanged,
            builder: (_, _, _) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                  widget.messaging.teamChannelStatus.join(' · '),
                  style: const TextStyle(color: L0ckColors.dim, fontSize: 11)),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: widget.messaging.session.db.watchTeamConversation(widget.team.id),
              builder: (context, snap) {
                final msgs = snap.data ?? const [];
                if (msgs.any((m) => !m.outgoing && m.status == 'received')) {
                  widget.messaging.markTeamRead(widget.team.id);
                }
                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final m in msgs.reversed)
                      MessageBubble(
                        m: m,
                        team: true,
                        sender: m.outgoing
                            ? null
                            : widget.messaging.senderNames[m.sender] ?? context.l.unknownSender(m.sender ?? '').trim(),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton(
                  tooltip: context.l.reportsAndPosition,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => showReportMenu(context,
                      (type, payload) => widget.messaging.sendTeamPayload(widget.team.id, type, payload)),
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: InputDecoration(labelText: context.l.teamMessage),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(tooltip: context.l.send, icon: const Icon(Icons.send), onPressed: _send),
              ]),
            ),
          ),
        ]),
      );
}
