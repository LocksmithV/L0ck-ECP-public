import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../l10n/lang.dart';
import 'reports.dart';
import 'theme.dart';

/// "14:05", or "2. 11. 14:05" when not today.
String shortTime(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return t.year == now.year && t.month == now.month && t.day == now.day ? hm : '${t.day}. ${t.month}. $hm';
}

/// Channel ids as people say them.
String channelName(String? via) => switch (via) {
      null => '',
      'simplex' => 'SimpleX',
      'bramble' => 'Tor/Bramble',
      'meshcore' => 'LoRa',
      'sms' => 'SMS',
      'squad' => Lang.tr.squadNet,
      final v => v.split('+').map(channelName).join(' + '),
    };

/// One message: text you can select and copy, its time, and for own messages the delivery
/// state (✓ sent, ✓✓ delivered, green ✓✓ read) with the channel used.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.m, this.sender, this.onSms, this.team = false});

  final Message m;

  /// Team chats: who wrote it.
  final String? sender;

  /// Offered when the message waits for the user's OK to go by SMS.
  final VoidCallback? onSms;
  final bool team;

  @override
  Widget build(BuildContext context) {
    final isText = m.type == MessageType.text;
    final text = isText ? decodeText(m.payload) : reportText(m.type, m.payload);
    final (icon, color, label) = _state(context.l);
    return Align(
      alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        constraints: const BoxConstraints(maxWidth: 310),
        decoration: BoxDecoration(
          color: m.outgoing ? L0ckColors.widget : L0ckColors.panel,
          border: Border.all(color: m.outgoing ? L0ckColors.green : L0ckColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sender != null)
            Text(sender!, style: const TextStyle(color: L0ckColors.orange, fontSize: 12)),
          GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(context.l.textCopied)));
            },
            child: isText
                ? SelectableText(text, style: const TextStyle(color: L0ckColors.text, fontSize: 15))
                : ReportView(type: m.type, payload: m.payload),
          ),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(shortTime(m.at), style: const TextStyle(fontSize: 11, color: L0ckColors.dim)),
            if (icon != null) ...[
              const SizedBox(width: 6),
              Icon(icon, size: 14, color: color),
            ],
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(fontSize: 11, color: color), overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (onSms != null && m.status == 'confirm')
            TextButton(
              onPressed: onSms,
              child: Text(context.l.sendViaSms, style: const TextStyle(color: L0ckColors.orange)),
            ),
        ]),
      ),
    );
  }

  (IconData?, Color, String) _state(AppLocalizations l) {
    final via = channelName(m.via);
    final at = m.statusAt == null ? '' : ' ${shortTime(m.statusAt!)}';
    if (!m.outgoing) return (null, L0ckColors.dim, via.isEmpty ? '' : l.via(via));
    if (team) {
      return m.status == 'failed'
          ? (Icons.error_outline, L0ckColors.red, l.nobodyInRange)
          : (Icons.done, L0ckColors.dim, l.sentTeam(via));
    }
    return switch (m.status) {
      'sending' => (Icons.schedule, L0ckColors.dim, l.stSending),
      'sent' => (Icons.done, L0ckColors.dim, l.stSent(via)),
      'delivered' => (Icons.done_all, L0ckColors.greenLight, l.stDelivered(at, via)),
      'read' => (Icons.done_all, L0ckColors.ok, l.stRead(at)),
      'waiting' => (Icons.hourglass_empty, L0ckColors.amber, l.stWaiting),
      'confirm' => (Icons.sms_outlined, L0ckColors.orange, l.stConfirm),
      'failed' => (Icons.error_outline, L0ckColors.red, l.stFailed),
      final s => (null, L0ckColors.dim, s),
    };
  }
}
