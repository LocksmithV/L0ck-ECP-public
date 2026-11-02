/// The simplex-chat CLI's WebSocket server (`simplex-chat -p PORT`) as a [SimplexApi], for
/// the laptop test node. dart:io, so not exported by ecp_simplex.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'src/api.dart';

class WsSimplex implements SimplexApi {
  WsSimplex._(this._ws) {
    _ws.listen((raw) {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = m['corrId'];
      final p = id == null ? null : _pending.remove(id);
      if (p != null) {
        p.complete(m);
      } else {
        final r = m['resp'];
        if (r is Map<String, dynamic>) _events.add((r['result'] ?? r) as Map<String, dynamic>);
      }
    });
  }

  static Future<WsSimplex> connect(int port) async => WsSimplex._(await WebSocket.connect(
      'ws://127.0.0.1:$port',
      customClient: HttpClient()..findProxy = (_) => 'DIRECT')); // never via an env proxy

  final WebSocket _ws;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  var _next = 0;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> cmd(String command) async {
    final id = '${++_next}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws.add(jsonEncode({'corrId': id, 'cmd': command}));
    final reply = await c.future.timeout(const Duration(seconds: 60));
    final r = reply['resp'];
    return unwrapResult(command, r is Map<String, dynamic> && r.containsKey('result') ? r : {'result': r});
  }

  @override
  Future<void> close() async {
    await _ws.close();
    await _events.close();
  }
}
