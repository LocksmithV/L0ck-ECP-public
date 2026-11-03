import 'package:ecp_core/ecp_core.dart' show GroupBundleAssembler;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import '../platform/scanner.dart';
import 'contact_detail_screen.dart';
import 'conversation_screen.dart';
import 'group_import.dart';
import 'theme.dart';
import 'widgets.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key, required this.messaging});

  final MessagingService messaging;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l.contacts), actions: [
          IconButton(
            tooltip: context.l.groupLoad,
            icon: const Icon(Icons.qr_code_scanner, color: L0ckColors.greenLight),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GroupImportScreen(messaging: messaging))),
          ),
        ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: L0ckColors.green,
        foregroundColor: L0ckColors.bg,
        icon: const Icon(Icons.person_add_alt),
        label: Text(context.l.add),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AddContactScreen(messaging: messaging))),
      ),
      body: StreamBuilder<({Map<int, int> contacts, Map<String, int> teams})>(
        stream: messaging.session.db.watchUnread(),
        builder: (context, unread) => StreamBuilder<List<Contact>>(
        stream: messaging.session.db.watchContacts(),
        builder: (context, snap) {
          final list = snap.data ?? const [];
          final counts = unread.data?.contacts ?? const {};
          if (list.isEmpty) {
            return Center(
                child: Text(context.l.noContactsYet, style: const TextStyle(color: L0ckColors.dim)));
          }
          return ListView(
            children: [
              for (final c in list)
                ListTile(
                  title: Text(c.name, style: const TextStyle(color: L0ckColors.text)),
                  subtitle: Text(c.verified ? context.l.verifiedInPerson : context.l.notVerified,
                      style: TextStyle(
                          color: c.verified ? L0ckColors.greenLight : L0ckColors.orange)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if ((counts[c.id] ?? 0) > 0) UnreadBadge(count: counts[c.id]!),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ConversationScreen(messaging: messaging, contact: c))),
                  onLongPress: () => _menu(context, c),
                ),
            ],
          );
        },
      )),
    );
  }
}

extension on ContactsScreen {
  /// Long press on a contact.
  Future<void> _menu(BuildContext context, Contact c) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: L0ckColors.panel,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text(c.name, style: const TextStyle(color: L0ckColors.data))),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: Text(context.l.openConversation),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ConversationScreen(messaging: messaging, contact: c)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(context.l.contactDetailMenu),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ContactDetailScreen(messaging: messaging, contactId: c.id)));
              },
            ),
          ]),
        ),
      );
}

/// Adds a contact from its `l0ck://c/…` link. Camera QR scanning comes with F5; until then
/// the link is pasted (e.g. shared via LocalSend or read from the other phone's screen).
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key, required this.messaging});

  final MessagingService messaging;

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _link = TextEditingController();
  ContactAdded? _added;
  String? _error, _updated;
  bool _verified = false;

  /// [scanned]: read from the other phone's screen with the camera, i.e. in person — the
  /// key cannot have been swapped on the way, so the contact counts as verified.
  Future<void> _add({bool scanned = false}) async {
    final r = await widget.messaging.addContactFromUri(_link.text, verified: scanned);
    if (r is ContactAdded) _verified = scanned;
    final team = switch (r) {
      ContactAdded(:final team) || ContactUpdated(:final team) => team,
      _ => null,
    };
    if (team != null) await widget.messaging.useTeamLoRa(team); // the team's LoRa channel
    setState(() {
      switch (r) {
        case ContactAdded():
          _added = r;
          _error = null;
        case ContactRejected(:final reason):
          _error = reason;
        case ContactUpdated(:final contact, :final team):
          _error = null;
          _updated = team == null ? contact.name : context.l.contactAndTeam(contact.name, team.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final added = _added;
    return Scaffold(
      appBar: AppBar(title: Text(context.l.addContact)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (added == null) ...[
            TextField(
              controller: _link,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: context.l.contactLinkLabel),
            ),
            const SizedBox(height: 12),
            if (_updated != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(context.l.contactUpdated(_updated!),
                    style: const TextStyle(color: L0ckColors.greenLight)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: L0ckColors.red)),
              ),
            FilledButton(onPressed: _add, child: Text(context.l.load)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(context.l.scanQr),
              onPressed: () async {
                final code = await scanQr(prompt: context.l.scanPrompt);
                if (code == null || !mounted) return;
                if (GroupBundleAssembler.isPart(code)) {
                  // The base laptop's group bundle, not a contact: its own screen
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => GroupImportScreen(messaging: widget.messaging, first: code)));
                  return;
                }
                _link.text = code;
                await _add(scanned: true);
              },
            ),
          ] else ...[
            if (added.team != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(context.l.joinedTeam(added.team!.name),
                    style: const TextStyle(color: L0ckColors.greenLight)),
              ),
            Text(added.contact.name,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: L0ckColors.text)),
            const SizedBox(height: 16),
            Text(context.l.verificationNumber, style: const TextStyle(color: L0ckColors.greenLight)),
            Text(added.verification,
                key: const Key('verification'),
                style: const TextStyle(fontSize: 28, color: L0ckColors.orange)),
            const SizedBox(height: 8),
            Text(context.l.verificationExplain, style: const TextStyle(color: L0ckColors.dim)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _verified,
              onChanged: (v) => setState(() => _verified = v ?? false),
              title: Text(context.l.numbersMatch),
            ),
            FilledButton(
              onPressed: () async {
                await widget.messaging.setVerified(added.contact.id, _verified);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(context.l.done),
            ),
          ],
        ],
      ),
    );
  }
}
