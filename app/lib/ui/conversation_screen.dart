import 'package:flutter/material.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import 'contact_detail_screen.dart';
import 'message_bubble.dart';
import 'reports.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.messaging, required this.contact});

  final MessagingService messaging;
  final Contact contact;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _text = TextEditingController();

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await widget.messaging.sendText(widget.contact.id, t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.contact.name), actions: [
        IconButton(
          tooltip: context.l.contact,
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ContactDetailScreen(messaging: widget.messaging, contactId: widget.contact.id))),
        ),
      ]),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: widget.messaging.session.db.watchConversation(widget.contact.id),
              builder: (context, snap) {
                final msgs = snap.data ?? const [];
                // Whatever is on screen counts as read; the sender gets a read receipt
                if (msgs.any((m) => !m.outgoing && m.status == 'received')) {
                  widget.messaging.markRead(widget.contact.id);
                }
                // Anchored at the bottom: the newest message is always in view
                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final m in msgs.reversed)
                      MessageBubble(m: m, onSms: () => widget.messaging.approveSms(m.id)),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.l.reportsAndPosition,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => showReportMenu(context,
                        (type, payload) => widget.messaging.sendPayload(widget.contact.id, type, payload)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(labelText: context.l.message),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(tooltip: context.l.send, icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
