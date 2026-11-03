import 'package:flutter/services.dart';

import 'lock_hold.dart';

/// QR scanning with ZXing (MainActivity / ScanActivity). Returns the code's text, or null
/// when the user backed out.
/// The scanner is an activity of its own: it must not lock the app (LockHold).
Future<String?> scanQr({String prompt = ''}) => LockHold.during(
    () => const MethodChannel('cz.l0ck.ecp/scan').invokeMethod<String>('scan', {'prompt': prompt}));
