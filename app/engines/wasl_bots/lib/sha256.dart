/// SHA-256 نقي بلا أي اعتماديات (FIPS 180-4) — محرك وصل النقية الثامن.
///
/// لماذا يدوياً وليس بحزمة؟ قرار «نقية بلا كود أصلي ولا اعتماديات» نفسه الذي
/// بنى به pqcrypto صفرَ اعتماديات: بصمة النموذج تحسب أثناء التنزيل على الطاير
/// وتتحقق قبل اعتماد الملف، والخوارزمية قياسية قابلة للتدقيق سطراً سطراً،
/// ومتجهات الاختبار محسوبة خارجياً بـpython hashlib (مستقلة عن هذا التنفيذ).
library;

import 'dart:typed_data';

/// مجرد تجميع SHA-256: update بتدفق (خاصةً أثناء التنزيل) ثم digest مرة واحدة.
class Sha256 {
  /// ثوابت الجولة الـ64 (K) — الجدول القياسي FIPS 180-4 §4.2.3
  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint32List _h = Uint32List.fromList(<int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);
  final Uint8List _buffer = Uint8List(64);
  final Uint32List _w = Uint32List(64);
  int _bufferLen = 0;
  int _totalBytes = 0;

  /// إضافة دفعة بايتات (chunk من دفق التنزيل) — بحجم أي شيء.
  void update(List<int> data) {
    int offset = 0;
    _totalBytes += data.length;
    if (_bufferLen > 0) {
      final take = data.length < 64 - _bufferLen ? data.length : 64 - _bufferLen;
      _buffer.setRange(_bufferLen, _bufferLen + take, data);
      _bufferLen += take;
      if (_bufferLen == 64) {
        _compress(_buffer);
        _bufferLen = 0;
      }
      offset = take;
    }
    while (offset + 64 <= data.length) {
      _compress(data, start: offset);
      offset += 64;
    }
    if (offset < data.length) {
      _buffer.setRange(0, data.length - offset, data, offset);
      _bufferLen = data.length - offset;
    }
  }

  /// إنهاء الحساب (padding قياسي) وإرجاع 32 بايتاً خاماً.
  Uint8List digestBytes() {
    final totalBitsLow32 = (_totalBytes << 3) & 0xFFFFFFFF;
    final totalBitsHigh32 = _totalBytes >> 29;
    // 0x80 ثم أصفار حتى طول ≡ 56 (mod 64) ثم طول الرسالة بـ64 بت big-endian
    final padding = <int>[0x80];
    final mod = (_totalBytes + 1) & 63;
    final zeros = mod <= 56 ? 56 - mod : 120 - mod;
    for (var i = 0; i < zeros; i++) {
      padding.add(0);
    }
    final lenBytes = <int>[
      (totalBitsHigh32 >> 24) & 0xFF, (totalBitsHigh32 >> 16) & 0xFF,
      (totalBitsHigh32 >> 8) & 0xFF, totalBitsHigh32 & 0xFF,
      (totalBitsLow32 >> 24) & 0xFF, (totalBitsLow32 >> 16) & 0xFF,
      (totalBitsLow32 >> 8) & 0xFF, totalBitsLow32 & 0xFF,
    ];
    update(padding);
    update(lenBytes);
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = _h[i] >>> 24 & 0xFF;
      out[i * 4 + 1] = _h[i] >>> 16 & 0xFF;
      out[i * 4 + 2] = _h[i] >>> 8 & 0xFF;
      out[i * 4 + 3] = _h[i] & 0xFF;
    }
    return out;
  }

  /// البصمة سداسية عشرية صغيرة (ما يقارن ببصمة الناشر المنشورة).
  String digestHex() {
    final b = digestBytes();
    final sb = StringBuffer();
    for (final v in b) {
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  void _compress(List<int> block, {int start = 0}) {
    for (var t = 0; t < 16; t++) {
      final i = start + t * 4;
      _w[t] = (block[i] << 24) | (block[i + 1] << 16) | (block[i + 2] << 8) | block[i + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 = _rotr(_w[t - 15], 7) ^ _rotr(_w[t - 15], 18) ^ (_w[t - 15] >>> 3);
      final s1 = _rotr(_w[t - 2], 17) ^ _rotr(_w[t - 2], 19) ^ (_w[t - 2] >>> 10);
      _w[t] = (_w[t - 16] + s0 + _w[t - 7] + s1) & 0xFFFFFFFF;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], hh = _h[7];
    for (var t = 0; t < 64; t++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final t1 = (hh + s1 + ch + _k[t] + _w[t]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    _h[0] = (_h[0] + a) & 0xFFFFFFFF;
    _h[1] = (_h[1] + b) & 0xFFFFFFFF;
    _h[2] = (_h[2] + c) & 0xFFFFFFFF;
    _h[3] = (_h[3] + d) & 0xFFFFFFFF;
    _h[4] = (_h[4] + e) & 0xFFFFFFFF;
    _h[5] = (_h[5] + f) & 0xFFFFFFFF;
    _h[6] = (_h[6] + g) & 0xFFFFFFFF;
    _h[7] = (_h[7] + hh) & 0xFFFFFFFF;
  }

  static int _rotr(int x, int n) =>
      ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;
}

/// بصمة سداسية لقائمة بايتات دفعة واحدة.
String sha256Hex(List<int> data) {
  final h = Sha256();
  h.update(data);
  return h.digestHex();
}
