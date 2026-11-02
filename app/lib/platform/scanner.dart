import 'package:flutter/services.dart';

/// QR scanning with ZXing (MainActivity / ScanActivity). Returns the code's text, or null
/// when the user backed out.
Future<String?> scanQr({String prompt = ''}) =>
    const MethodChannel('cz.l0ck.ecp/scan').invokeMethod<String>('scan', {'prompt': prompt});
