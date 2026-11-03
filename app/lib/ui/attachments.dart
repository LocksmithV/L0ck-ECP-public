import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../platform/attach.dart';
import '../platform/radio.dart' show Permissions;
import 'theme.dart';

/// "380 kB".
String sizeLabel(int bytes) =>
    bytes < 1024 ? '$bytes B' : bytes < 1024 * 1024 ? '${(bytes / 1024).round()} kB' : '${(bytes / 1048576).toStringAsFixed(1)} MB';

/// What a chat's "+" menu needs for photos and files.
class AttachActions {
  const AttachActions({required this.available, required this.send});

  /// A channel fit for them reaches the conversation now (SimpleX, Bramble by Tor/LAN).
  final bool Function() available;
  final Future<void> Function(Attachment a) send;
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// The camera app takes it; it comes back reduced and without EXIF (MainActivity).
Future<void> attachPhoto(BuildContext context, AttachActions a) async {
  final l = context.l;
  if (!a.available()) return _say(context, l.attachNoChannel);
  if (!await Permissions.request(const ['android.permission.CAMERA'])) {
    if (context.mounted) _say(context, l.attachCamDenied);
    return;
  }
  try {
    final jpeg = await Attach.photo();
    if (jpeg == null || !context.mounted) return;
    final now = DateTime.now();
    final name = 'foto-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.jpg';
    _say(context, l.attachSending(sizeLabel(jpeg.length)));
    await a.send(Attachment(kind: Attachment.photo, name: name, mime: 'image/jpeg', bytes: jpeg));
  } catch (_) {
    if (context.mounted) _say(context, l.attachFailed);
  }
}

/// The system picker: one file, no storage permission needed.
Future<void> attachFile(BuildContext context, AttachActions a) async {
  final l = context.l;
  if (!a.available()) return _say(context, l.attachNoChannel);
  try {
    final f = await Attach.pick();
    if (f == null || !context.mounted) return;
    final data = f.data;
    if (data == null) return _say(context, l.attachTooBig(sizeLabel(f.size)));
    _say(context, l.attachSending(sizeLabel(data.length)));
    final kind = f.mime.startsWith('image/') ? Attachment.photo : Attachment.file;
    await a.send(Attachment(kind: kind, name: f.name, mime: f.mime, bytes: data));
  } catch (_) {
    if (context.mounted) _say(context, l.attachFailed);
  }
}

Future<void> _save(BuildContext context, Attachment a) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await Attach.save(a.name, a.mime, a.bytes).catchError((_) => false);
  messenger.showSnackBar(SnackBar(content: Text(ok ? l.fileSaved : l.fileSaveFailed)));
}

/// A photo or file inside a chat bubble: a photo as a picture (tap: full screen), a file as
/// its name and size; both can be saved.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.payload});

  final List<int> payload;

  @override
  Widget build(BuildContext context) {
    final Attachment a;
    try {
      a = Attachment.decode(payload);
    } on FormatException {
      return Text(context.l.attachFailed, style: const TextStyle(color: L0ckColors.red));
    }
    if (a.kind == Attachment.photo && a.mime.startsWith('image/')) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PhotoScreen(a))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
            child: Image.memory(a.bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Text(a.name, style: const TextStyle(color: L0ckColors.text))),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.insert_drive_file_outlined, size: 30, color: L0ckColors.greenLight),
      const SizedBox(width: 8),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(a.name, style: const TextStyle(color: L0ckColors.data, fontSize: 15), overflow: TextOverflow.ellipsis),
          Text(sizeLabel(a.bytes.length), style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
        ]),
      ),
      IconButton(
        tooltip: context.l.save,
        icon: const Icon(Icons.download, color: L0ckColors.greenLight),
        onPressed: () => _save(context, a),
      ),
    ]);
  }
}

class _PhotoScreen extends StatelessWidget {
  const _PhotoScreen(this.a);

  final Attachment a;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(a.name), actions: [
          IconButton(
            tooltip: context.l.save,
            icon: const Icon(Icons.download),
            onPressed: () => _save(context, a),
          ),
        ]),
        body: InteractiveViewer(
          maxScale: 6,
          child: Center(child: Image.memory(a.bytes, fit: BoxFit.contain)),
        ),
      );
}
