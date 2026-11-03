import 'package:flutter/material.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import '../messaging/messaging_service.dart';
import '../messaging/call_service.dart';
import 'attachments.dart';
import 'call_screen.dart';
import 'contact_detail_screen.dart';
import 'message_bubble.dart';
import 'reports.dart';
import 'theme.dart';
import 'voice.dart';
import '../platform/voice.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.messaging, required this.contact});

  final MessagingService messaging;
  final Contact contact;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _text = TextEditingController();
  bool _voice = false;

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await widget.messaging.sendText(widget.contact.id, t);
  }

  /// Asks first; then the chat is empty on this phone.
  Future<void> _clearChat() async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: L0ckColors.panel,
        title: Text(l.clearChatAsk),
        content: Text(l.clearChatText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
            key: const Key('clear-chat-confirm'),
            style: FilledButton.styleFrom(backgroundColor: L0ckColors.red.withValues(alpha: 0.3)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.clearChat),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await VoiceAudio.stopPlaying().catchError((_) {});
    await widget.messaging.clearChat(contactId: widget.contact.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.chatCleared)));
  }

  /// A call when SimpleX/Bramble reaches the contact and the audio has a path (internet or
  /// the same Wi-Fi); else it only says why not.
  Widget _callButton() => ValueListenableBuilder<int>(
        valueListenable: widget.messaging.channelsChanged,
        builder: (context, _, _) {
          final ok = widget.messaging.canCall(widget.contact.id);
          return IconButton(
            key: const Key('call'),
            tooltip: ok ? context.l.callAction : context.l.callNoChannel,
            icon: Icon(Icons.call, color: ok ? L0ckColors.greenLight : L0ckColors.dim),
            onPressed: () => _call(ok),
          );
        },
      );

  Future<void> _call(bool ok) async {
    final l = context.l;
    final calls = CallService.instance;
    final messenger = ScaffoldMessenger.of(context);
    if (!ok || calls == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.callNoChannel)));
      return;
    }
    // The call screen at once: gathering the network paths takes a few seconds
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(builder: (_) => CallScreen(calls: calls));
    navigator.push(route);
    final error = await calls.call(widget.contact, noChannel: l.callNoChannel, noMic: l.voiceMicDenied);
    if (error != null) {
      if (route.isActive) navigator.removeRoute(route);
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// The microphone: a voice message when SimpleX or Bramble reaches the contact now,
  /// else it only says why not.
  Widget _mic() => ValueListenableBuilder<int>(
        valueListenable: widget.messaging.channelsChanged,
        builder: (context, _, _) {
          final ok = widget.messaging.canSendVoice(widget.contact.id);
          return IconButton(
            key: const Key('mic'),
            tooltip: ok ? context.l.voiceRecord : context.l.voiceNoChannel,
            icon: Icon(Icons.mic_none, color: ok ? L0ckColors.greenLight : L0ckColors.dim),
            onPressed: ok
                ? () => setState(() => _voice = true)
                : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.voiceNoChannel))),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.contact.name), actions: [
        _callButton(),
        PopupMenuButton<String>(
          key: const Key('chat-menu'),
          tooltip: context.l.contact,
          icon: const Icon(Icons.info_outline),
          color: L0ckColors.panel,
          onSelected: (v) => v == 'info'
              ? Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ContactDetailScreen(messaging: widget.messaging, contactId: widget.contact.id)))
              : _clearChat(),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'info', child: Text(context.l.contactInfo)),
            PopupMenuItem(value: 'clear', child: Text(context.l.clearChat)),
          ],
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
              child: _voice
                  ? VoiceRecorder(
                      onSend: (codec, ms, data) => widget.messaging.sendVoice(widget.contact.id, codec, ms, data),
                      onClose: () => setState(() => _voice = false),
                    )
                  : Row(
                children: [
                  IconButton(
                    tooltip: context.l.reportsAndPosition,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => showReportMenu(
                      context,
                      (type, payload) => widget.messaging.sendPayload(widget.contact.id, type, payload),
                      attach: AttachActions(
                        available: () => widget.messaging.canSendVoice(widget.contact.id),
                        send: (a) => widget.messaging.sendAttachment(widget.contact.id, a),
                      ),
                    ),
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
                  _mic(),
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
