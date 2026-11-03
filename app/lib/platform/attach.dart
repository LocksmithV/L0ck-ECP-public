import 'package:flutter/services.dart';

import 'lock_hold.dart';

/// Chat attachments (MainActivity, "cz.l0ck.ecp/files"): a photo from the camera app, a file
/// from the system picker, saving a received one. The camera and pickers are activities of
/// their own, so they hold off the lock (LockHold).
abstract final class Attach {
  static const _channel = MethodChannel('cz.l0ck.ecp/files');

  /// The photo as JPEG (≤ 1600 px, no EXIF); null when none was taken.
  static Future<Uint8List?> photo() => LockHold.during(() => _channel.invokeMethod<Uint8List>('photo'));

  /// The chosen file; [data] is null when it is larger than allowed ([size] then says how big).
  static Future<({String name, String mime, Uint8List? data, int size})?> pick() =>
      LockHold.during(() async {
        final m = await _channel.invokeMapMethod<String, Object?>('pick');
        if (m == null) return null;
        final data = m['data'] as Uint8List?;
        return (
          name: m['name'] as String? ?? 'soubor',
          mime: m['mime'] as String? ?? 'application/octet-stream',
          data: data,
          size: data?.length ?? (m['size'] as int? ?? 0),
        );
      });

  /// Saves [data] where the user chooses; true when written.
  static Future<bool> save(String name, String mime, Uint8List data) => LockHold.during(
      () async => await _channel.invokeMethod<bool>('save', {'name': name, 'mime': mime, 'data': data}) ?? false);
}
