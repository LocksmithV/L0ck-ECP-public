import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Emergency lock: four quick taps anywhere (within 1.5 s) lock the app and send it to the
/// background. Sits above every screen (MaterialApp.builder), so it works on any of them.
class QuickLock extends StatefulWidget {
  const QuickLock({super.key, required this.child});

  final Widget child;

  static const taps = 4;
  static const window = Duration(milliseconds: 1500);

  /// Set by the app shell while a profile is unlocked.
  static VoidCallback? onTrigger;

  /// Hides the app (Activity.moveTaskToBack), as if the home button was pressed.
  static Future<void> minimize() =>
      const MethodChannel('cz.l0ck.ecp/activity').invokeMethod('minimize');

  @override
  State<QuickLock> createState() => _QuickLockState();
}

class _QuickLockState extends State<QuickLock> {
  final List<DateTime> _downs = [];

  void _down(PointerDownEvent _) {
    final now = DateTime.now();
    _downs
      ..add(now)
      ..removeWhere((t) => now.difference(t) > QuickLock.window);
    if (_downs.length >= QuickLock.taps) {
      _downs.clear();
      QuickLock.onTrigger?.call();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Listener(behavior: HitTestBehavior.translucent, onPointerDown: _down, child: widget.child);
}
