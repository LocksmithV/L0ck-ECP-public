import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone has a network with internet at all (NetHost.java). Without one, PACE
/// skips SimpleX and Tor at once instead of waiting out their ACK timeouts.
abstract final class Net {
  static const _events = EventChannel('cz.l0ck.ecp/net');

  /// Until Android has answered (and in tests): online, as before this check existed.
  static final ValueNotifier<bool> online = ValueNotifier(true);

  static StreamSubscription<Object?>? _sub;

  static void watch() => _sub ??= _events.receiveBroadcastStream().listen(
        (v) => online.value = v == true,
        onError: (_) {}, // no answer: stay as we are
      );
}
