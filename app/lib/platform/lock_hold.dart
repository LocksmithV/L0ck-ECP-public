/// The app's own screens outside Flutter — the QR scanner, the system's "visible for
/// Bluetooth" dialog — put the app in the background as if it was left. While one is up the
/// shell does not lock at once (see AppShell.didChangeAppLifecycleState), only after
/// [limit] at the earliest, should it stay up.
abstract final class LockHold {
  static const limit = Duration(minutes: 2);
  static int _n = 0;

  static bool get active => _n > 0;

  static Future<T> during<T>(Future<T> Function() f) async {
    _n++;
    try {
      return await f();
    } finally {
      _n--;
    }
  }
}
