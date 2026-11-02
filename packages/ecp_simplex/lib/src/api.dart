/// The SimpleX Chat API as ECP uses it: text commands in, JSON results and events out
/// (bots/api/COMMANDS.md and EVENTS.md of simplex-chat v7). Implemented over the core
/// library's FFI on the phone and over the CLI's WebSocket server on a laptop.
abstract class SimplexApi {
  /// Runs one command; returns its result object (with a `type` field), or throws
  /// [SimplexError] when the core answers with an error.
  Future<Map<String, dynamic>> cmd(String command);

  /// Results nobody asked for: new messages, contacts connecting, network status.
  Stream<Map<String, dynamic>> get events;

  Future<void> close();
}

class SimplexError implements Exception {
  SimplexError(this.command, this.error);

  final String command;
  final Object? error;

  @override
  String toString() => 'SimplexError(${command.split(' ').first}: $error)';
}

/// Unwraps the core's `{"result": …}` / `{"error": …}` reply (Mobile.hs `APIResult`).
Map<String, dynamic> unwrapResult(String command, Map<String, dynamic> reply) {
  final r = reply['result'] ?? reply['resp'];
  if (reply['error'] != null || r is! Map<String, dynamic>) {
    throw SimplexError(command, reply['error'] ?? reply);
  }
  if (r['type'] == 'chatCmdError' || r['type'] == 'chatError') {
    throw SimplexError(command, r['chatError'] ?? r);
  }
  return r;
}
