import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'ecp_meshcore.dart';

/// Linux/desktop only (dart:io), hence not exported by ecp_meshcore.dart.
/// A MeshCore companion on a Linux serial port (USB CDC/CP210x), 115200 8N1 raw.
class SerialLink implements FrameLink {
  SerialLink._(this._raf, this._frames);

  static Future<SerialLink> open(String device) async {
    final stty = await Process.run('stty', ['-F', device, '115200', 'raw', '-echo', '-hupcl']);
    if (stty.exitCode != 0) throw StateError('stty: ${stty.stderr}');
    final raf = await File(device).open(mode: FileMode.writeOnly); // append would seek, a tty cannot
    final frames = StreamController<Uint8List>.broadcast();
    final framing = SerialFraming();
    // Reading a tty as a file stream blocks a thread per read, so read from its own handle
    File(device).openRead().listen((bytes) => framing.feed(bytes).forEach(frames.add));
    return SerialLink._(raf, frames);
  }

  final RandomAccessFile _raf;
  final StreamController<Uint8List> _frames;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> send(Uint8List frame) async {
    await _raf.writeFrom(SerialFraming.wrap(frame)); // no flush(): fsync on a tty fails
  }
}
