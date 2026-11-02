import 'dart:typed_data';

/// Big-endian writer for the compact wire formats (envelope, messages, contact card).
class ByteWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u8(int v) {
    _check(v, 0, 0xff);
    _b.addByte(v);
  }

  void u16(int v) {
    _check(v, 0, 0xffff);
    _b.add([v >> 8, v & 0xff]);
  }

  void u32(int v) {
    _check(v, 0, 0xffffffff);
    _b.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  }

  void i16(int v) {
    _check(v, -0x8000, 0x7fff);
    u16(v & 0xffff);
  }

  void i32(int v) {
    _check(v, -0x80000000, 0x7fffffff);
    u32(v & 0xffffffff);
  }

  void bytes(List<int> v) => _b.add(v);

  int get length => _b.length;

  Uint8List toBytes() => _b.toBytes();

  static void _check(int v, int min, int max) {
    if (v < min || v > max) {
      throw RangeError.range(v, min, max);
    }
  }
}

/// Big-endian reader; every underflow is a [FormatException], never a crash.
class ByteReader {
  ByteReader(List<int> data) : _d = Uint8List.fromList(data);

  final Uint8List _d;
  int _pos = 0;

  int get remaining => _d.length - _pos;

  int u8() => _take(1)[0];

  int u16() {
    final b = _take(2);
    return (b[0] << 8) | b[1];
  }

  int u32() {
    final b = _take(4);
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  int i16() {
    final v = u16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int i32() {
    final v = u32();
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  Uint8List take(int n) => Uint8List.fromList(_take(n));

  Uint8List rest() => take(remaining);

  Uint8List _take(int n) {
    if (n < 0 || n > remaining) {
      throw FormatException('truncated: need $n bytes, have $remaining');
    }
    final out = Uint8List.sublistView(_d, _pos, _pos + n);
    _pos += n;
    return out;
  }
}

/// Constant-time comparison for secrets and authentication tags.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String s) {
  final clean = s.replaceAll(RegExp(r'[\s:]'), '');
  if (clean.length.isOdd) throw FormatException('odd hex length');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
