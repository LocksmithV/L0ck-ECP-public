import 'package:flutter/material.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import 'theme.dart';
import 'widgets.dart';

typedef Recipients = ({Set<String> teams, Set<int> contacts});

/// Who gets a report sent from the home screen: any teams and contacts, picked together.
/// Pops with the choice, or with nothing when left by the back button.
class RecipientPicker extends StatefulWidget {
  const RecipientPicker({super.key, required this.messaging});

  final MessagingService messaging;

  @override
  State<RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<RecipientPicker> {
  final Set<String> _teams = {};
  final Set<int> _contacts = {};

  int get _count => _teams.length + _contacts.length;

  Widget _tile(IconData icon, String name, bool on, ValueChanged<bool> set, {Key? key}) => CheckboxListTile(
        key: key,
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: L0ckColors.greenLight),
        title: Text(name, style: const TextStyle(color: L0ckColors.data)),
        value: on,
        onChanged: (v) => setState(() => set(v ?? false)),
      );

  @override
  Widget build(BuildContext context) {
    final db = widget.messaging.session.db;
    final l = context.l;
    return StreamBuilder<List<Team>>(
      stream: db.watchTeams(),
      builder: (context, ts) => StreamBuilder<List<Contact>>(
        stream: db.watchContacts(),
        builder: (context, cs) {
          final teams = ts.data ?? const <Team>[], contacts = cs.data ?? const <Contact>[];
          final all = _teams.length == teams.length && _contacts.length == contacts.length;
          return Scaffold(
            appBar: AppBar(
              title: Text(l.sendTo),
              actions: [
                if (teams.isNotEmpty || contacts.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      if (all) {
                        _teams.clear();
                        _contacts.clear();
                      } else {
                        _teams.addAll(teams.map((t) => t.id));
                        _contacts.addAll(contacts.map((c) => c.id));
                      }
                    }),
                    child: Text(l.selectAll),
                  ),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              if (teams.isEmpty && contacts.isEmpty && ts.hasData && cs.hasData)
                Text(l.noRecipients, style: const TextStyle(color: L0ckColors.dim)),
              if (teams.isNotEmpty)
                Panel(
                  title: l.teams,
                  child: Column(children: [
                    for (final t in teams)
                      _tile(Icons.groups, t.name, _teams.contains(t.id),
                          (on) => on ? _teams.add(t.id) : _teams.remove(t.id),
                          key: Key('team-${t.id}')),
                  ]),
                ),
              if (contacts.isNotEmpty)
                Panel(
                  title: l.contacts,
                  child: Column(children: [
                    for (final c in contacts)
                      _tile(Icons.person, c.name, _contacts.contains(c.id),
                          (on) => on ? _contacts.add(c.id) : _contacts.remove(c.id),
                          key: Key('contact-${c.id}')),
                  ]),
                ),
            ]),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  key: const Key('send-to'),
                  icon: const Icon(Icons.send),
                  label: Text(l.sendToN(_count)),
                  onPressed: _count == 0
                      ? null
                      : () => Navigator.of(context).pop<Recipients>((teams: {..._teams}, contacts: {..._contacts})),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
