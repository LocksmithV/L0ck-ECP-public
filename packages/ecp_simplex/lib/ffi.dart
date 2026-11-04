/// SimpleX Chat core (libsimplex.so, Haskell) over dart:ffi, for the phone. Every call into
/// the core blocks, so commands run one at a time on a helper isolate and a second isolate
/// waits for events. dart:ffi, so not exported by ecp_simplex.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'src/api.dart';

typedef _HsInitN = Void Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _HsInitD = void Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _InitN = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32, Pointer<Pointer<Void>>);
typedef _InitD = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<Pointer<Void>>);
typedef _SendN = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _RecvN = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _RecvD = Pointer<Utf8> Function(Pointer<Void>, int);
typedef _CloseN = Pointer<Utf8> Function(Pointer<Void>);
typedef _FreeN = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);

/// The core's C functions (simplex-chat src/Simplex/Chat/Mobile.hs). Opened per isolate.
class _Core {
  _Core(String path)
      : _lib = _open(path),
        _libc = DynamicLibrary.open('libc.so');

  /// The shim first (app/android/simplex/simplex_shim.c): the core resolves the symbols
  /// Android does not export against it — without it the 32-bit core does not load. Where
  /// there is no shim (desktop builds) the core alone.
  static DynamicLibrary _open(String path) {
    if (path == 'libsimplex.so') {
      try {
        return DynamicLibrary.open('libsimplexshim.so');
      } on ArgumentError {
        // no shim next to the core
      }
    }
    return DynamicLibrary.open(path);
  }

  final DynamicLibrary _lib, _libc;
  late final hsInit = _lib.lookupFunction<_HsInitN, _HsInitD>('hs_init');
  late final _init = _lib.lookupFunction<_InitN, _InitD>('chat_migrate_init_key');
  late final _send = _lib.lookupFunction<_SendN, _SendN>('chat_send_cmd');
  late final _recv = _lib.lookupFunction<_RecvN, _RecvD>('chat_recv_msg_wait');
  late final _close = _lib.lookupFunction<_CloseN, _CloseN>('chat_close_store');
  late final _free = _libc.lookupFunction<_FreeN, _FreeD>('free');

  String _take(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    try {
      return p.toDartString();
    } finally {
      _free(p.cast());
    }
  }

  /// Returns (reply JSON, controller address).
  (String, int) init(String dbPrefix, String key) => using((a) {
        final ctrl = a<Pointer<Void>>();
        // keepKey = 0, migrations "yesUp", background mode off
        final r = _take(_init(dbPrefix.toNativeUtf8(allocator: a), key.toNativeUtf8(allocator: a), 0,
            'yesUp'.toNativeUtf8(allocator: a), 0, ctrl));
        return (r, ctrl.value.address);
      });

  String send(int ctrl, String cmd) =>
      using((a) => _take(_send(Pointer.fromAddress(ctrl), cmd.toNativeUtf8(allocator: a))));

  String recv(int ctrl, Duration wait) => _take(_recv(Pointer.fromAddress(ctrl), wait.inMicroseconds));

  String close(int ctrl) => _take(_close(Pointer.fromAddress(ctrl)));
}

class FfiSimplex implements SimplexApi {
  FfiSimplex._(this._lib, this._ctrl);

  static bool _hsReady = false;

  /// Opens (creating or migrating) the encrypted databases `<dbPrefix>_chat.db` and
  /// `<dbPrefix>_agent.db` with [key], and starts listening for events.
  static Future<FfiSimplex> open({
    required String dbPrefix,
    required String key,
    String library = 'libsimplex.so',
  }) async {
    if (!_hsReady) {
      _Core(library).hsInit(nullptr, nullptr); // the Haskell runtime, once per process
      _hsReady = true;
    }
    final (reply, ctrl) = await _initIn(library, dbPrefix, key);
    final r = jsonDecode(reply) as Map<String, dynamic>;
    if (r['type'] != 'ok' || ctrl == 0) throw SimplexError('init', r);
    final s = FfiSimplex._(library, ctrl);
    await s._listen();
    return s;
  }

  final String _lib;
  final int _ctrl;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Future<void> _queue = Future.value();
  Isolate? _receiver;
  ReceivePort? _port;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> cmd(String command) {
    final lib = _lib, ctrl = _ctrl;
    final done = Completer<Map<String, dynamic>>();
    _queue = _queue.then((_) async {
      try {
        final raw = await _sendIn(lib, ctrl, command);
        done.complete(unwrapResult(command, jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        done.completeError(e);
      }
    });
    return done.future;
  }

  Future<void> _listen() async {
    final port = ReceivePort();
    _port = port;
    port.listen((raw) {
      if (raw is! String || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final r = m['result'];
      if (r is Map<String, dynamic>) _events.add(r);
    });
    _receiver = await Isolate.spawn(_receive, (port.sendPort, _lib, _ctrl));
  }

  // Isolate entry points take only plain values: a closure made inside an instance method
  // would capture its whole context (completers, streams), which cannot cross isolates.
  static Future<(String, int)> _initIn(String lib, String dbPrefix, String key) =>
      Isolate.run(() => _Core(lib).init(dbPrefix, key));

  static Future<String> _sendIn(String lib, int ctrl, String command) =>
      Isolate.run(() => _Core(lib).send(ctrl, command));

  static Future<String> _closeIn(String lib, int ctrl) =>
      Isolate.run(() => _Core(lib).close(ctrl));

  static void _receive((SendPort, String, int) args) {
    final (out, lib, ctrl) = args;
    final core = _Core(lib);
    while (true) {
      final s = core.recv(ctrl, const Duration(milliseconds: 500));
      if (s.isNotEmpty) out.send(s);
    }
  }

  @override
  Future<void> close() async {
    _receiver?.kill(priority: Isolate.immediate);
    _port?.close();
    final lib = _lib, ctrl = _ctrl;
    await _queue;
    try {
      await cmd('/_stop');
    } catch (_) {}
    await _closeIn(lib, ctrl);
    await _events.close();
  }
}
