// Dev helper: times production Argon2id key slots. Run: dart run tool/kdf_bench.dart
import 'package:ecp_core/ecp_core.dart';
Future<void> main() async {
  final sw = Stopwatch()..start();
  final c = await KeySlots.create(pin: '482913', duressPin: '115577');
  final create = sw.elapsedMilliseconds; sw.reset();
  await KeySlots.unlock(c.file, '482913');
  print('production KDF (64 MiB, t=3): create(2 slots)=${create}ms unlock=${sw.elapsedMilliseconds}ms');
}
