/// خدمة التنزيل الموثق للنموذج اللغوي على الجهاز (المرحلة 18 أ — 1.16.0).
///
/// طبقة التطبيق فوق محرك `engines/wasl_model_fetch` النقي (نُسخ جوهره هنا
/// وفق عادة المحركات كما في wasl_model_gate/on_device_model_service): دفق
/// بايتات من HttpClient يُحقن في المحرك، والبصمة تتحقق قبل الاعتماد، والملف
/// الذري لا يترك نصف ملفات. مصادر النماذج هنا قيم موثقة من الناشر نفسه:
/// الرابط والبصمة كلاهما من HuggingFace API الرسمي (`lfs.oid` ببصمة SHA-256)
/// مفحوص يوم 2026-11-19 — لا بصمة مخترعة ولا رابط مهيأ.
///
/// الصدق التصميمي: التنزيل طوعي بموافقة نقر صريحة من الواجهة (تُربط عند
/// ربط المحرك في 1.17.0 بعد القياس الميداني) — لا تنزيل تلقائي ولا فرض،
/// وعلى الويب التنزيل الموثق هذا غير متاح بعد (يعود برسالة صادقة).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// ————— جوهر المحرك النقي (نسخة التطبيق من engines/wasl_model_fetch) —————

/// SHA-256 نقي بلا اعتماديات (FIPS 180-4) — بصمة النموذج على الطاير.
/// متجهات الاختبار محسوبة خارجياً بـpython hashlib (مستقلة عن التنفيذ).
class Sha256 {
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

  void update(List<int> data) {
    int offset = 0;
    _totalBytes += data.length;
    if (_bufferLen > 0) {
      final take =
          data.length < 64 - _bufferLen ? data.length : 64 - _bufferLen;
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

  Uint8List digestBytes() {
    final totalBitsLow32 = (_totalBytes << 3) & 0xFFFFFFFF;
    final totalBitsHigh32 = _totalBytes >> 29;
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
      _w[t] =
          (block[i] << 24) | (block[i + 1] << 16) | (block[i + 2] << 8) | block[i + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 =
          _rotr(_w[t - 15], 7) ^ _rotr(_w[t - 15], 18) ^ (_w[t - 15] >>> 3);
      final s1 =
          _rotr(_w[t - 2], 17) ^ _rotr(_w[t - 2], 19) ^ (_w[t - 2] >>> 10);
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

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;
}

/// مصدر تنزيل موثق: الرابط والبصمة من الناشر نفسه.
class ModelSource {
  const ModelSource({
    required this.id,
    required this.label,
    required this.url,
    required this.sha256Hex,
    required this.sizeMb,
    required this.notes,
  });

  final String id;
  final String label;
  final Uri url;
  final String sha256Hex;
  final int sizeMb;
  final String notes;

  String get normalizedSha256 => sha256Hex.trim().toLowerCase();
}

enum FetchState { downloading, verifying, ready, failed }

class FetchProgress {
  const FetchProgress(this.state, this.receivedBytes, this.totalBytes,
      [this.error]);

  final FetchState state;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  double? get percent =>
      totalBytes <= 0 ? null : (receivedBytes * 100 / totalBytes).clamp(0, 100);
}

class FetchResult {
  const FetchResult(
      {required this.ok, required this.state, required this.receivedBytes, this.error});

  final bool ok;
  final FetchState state;
  final int receivedBytes;
  final String? error;
}

typedef ByteStreamFactory = Stream<List<int>> Function(Uri url);

/// المُنزّل الذري: دفق → `.part` مع بصمة على الطاير → تحقق → اعتماد.
class ModelFetcher {
  ModelFetcher({required this.modelsDir, this.streamFactory});

  final Directory modelsDir;
  final ByteStreamFactory? streamFactory;

  File _partFile(String id) => File('${modelsDir.path}/${_safe(id)}.part');
  File _doneFile(String id) => File('${modelsDir.path}/${_safe(id)}.gguf');
  File _digestFile(String id) =>
      File('${modelsDir.path}/${_safe(id)}.sha256');

  /// أسماء الملفات من المعرّف فقط — منع أي خروج عن مجلد النماذج
  String _safe(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  Future<FetchResult> fetch(
    ModelSource source, {
    void Function(FetchProgress p)? onProgress,
    Stream<List<int>>? byteStream,
  }) async {
    try {
      await modelsDir.create(recursive: true);
    } catch (e) {
      onProgress?.call(FetchProgress(
          FetchState.failed, 0, 0, 'تعذر تجهيز مجلد النماذج: $e'));
      return FetchResult(
          ok: false, state: FetchState.failed, receivedBytes: 0, error: 'mkdir: $e');
    }
    final partFile = _partFile(source.id);
    final hasher = Sha256();
    var received = 0;
    IOSink? sink;
    try {
      final stream = byteStream ?? _requireStream(source.url);
      sink = partFile.openWrite();
      await for (final chunk in stream) {
        if (chunk.isEmpty) continue;
        sink.add(chunk);
        hasher.update(chunk);
        received += chunk.length;
        onProgress?.call(FetchProgress(
            FetchState.downloading, received, source.sizeMb * 1048576));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress?.call(FetchProgress(FetchState.verifying, received, received));
      final digest = hasher.digestHex();
      if (digest != source.normalizedSha256) {
        if (await partFile.exists()) await partFile.delete();
        const msg =
            'بصمة الملف المحوَّل لا تطابق بصمة الناشر — أُلغي الاعتماد وحُذف المؤقت';
        onProgress?.call(
            FetchProgress(FetchState.failed, received, received, msg));
        return FetchResult(
            ok: false, state: FetchState.failed, receivedBytes: received, error: msg);
      }
      await partFile.rename(_doneFile(source.id).path);
      await _digestFile(source.id).writeAsString(digest);
      onProgress?.call(FetchProgress(FetchState.ready, received, received));
      return FetchResult(ok: true, state: FetchState.ready, receivedBytes: received);
    } catch (e) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      onProgress
          ?.call(FetchProgress(FetchState.failed, received, received, '$e'));
      return FetchResult(
          ok: false, state: FetchState.failed, receivedBytes: received, error: '$e');
    }
  }

  Stream<List<int>> _requireStream(Uri url) {
    final f = streamFactory;
    if (f == null) {
      throw StateError('لا مصنع دفق محقون — مرر streamFactory أو byteStream');
    }
    return f(url);
  }

  /// جاهزية رخيصة: الملف النهائي موجود والبصمة المدونة عند الاكتمال مطابقة.
  Future<bool> isReady(String id, {String? expectedSha256Hex}) async {
    final done = _doneFile(id);
    final digest = _digestFile(id);
    if (!await done.exists() || !await digest.exists()) return false;
    if (expectedSha256Hex == null) return true;
    final recorded = (await digest.readAsString()).trim().toLowerCase();
    return recorded == expectedSha256Hex.trim().toLowerCase();
  }

  /// الإثبات الكامل: إعادة حساب البصمة من الملف النهائي — وإن خالف يُمحى.
  Future<String?> verifyFull(ModelSource source) async {
    final done = _doneFile(source.id);
    if (!await done.exists()) return null;
    final hasher = Sha256();
    await for (final chunk in done.openRead()) {
      hasher.update(chunk);
    }
    final digest = hasher.digestHex();
    if (digest != source.normalizedSha256) {
      try {
        await done.delete();
      } catch (_) {}
      try {
        await _digestFile(source.id).delete();
      } catch (_) {}
      return null;
    }
    return digest;
  }

  Future<void> delete(String id) async {
    for (final f in [_doneFile(id), _partFile(id), _digestFile(id)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

// ————— طبقة خدمة التطبيق: المصادر الموثقة + دفق الشبكة + مجلد التخزين —————

class ModelFetchService {
  ModelFetchService._();

  /// كتالوج المصادر الموثقة — كل قيمة من الناشر (HuggingFace API `lfs.oid`
  /// ببصمة SHA-256) مفحوص يوم 2026-11-19. مرشحو كتالوج ON_DEVICE_LLM الفعليون:
  static final List<ModelSource> sources = List.unmodifiable(<ModelSource>[
    ModelSource(
      id: 'qwen3-0.6b-q4km',
      label: 'Qwen3 0.6B — Q4_K_M (462 م.ب)',
      url: Uri.parse(
          'https://huggingface.co/bartowski/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf'),
      sha256Hex:
          '9acfc1e001311f34b4252001b626f2e466d592a42065f66571bff3790d4e1b14',
      sizeMb: 462,
      notes:
          'أقوى مرشح عملي عربياً في وزن 0.6B — جودة Q4_K_M القياسية للمحادثة',
    ),
    ModelSource(
      id: 'qwen3-0.6b-iq3xxs',
      label: 'Qwen3 0.6B — IQ3_XXS (330 م.ب)',
      url: Uri.parse(
          'https://huggingface.co/bartowski/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-IQ3_XXS.gguf'),
      sha256Hex:
          '4553e20544d2667785db4e48b5556d02e70989234be5853b8bf200d65381d701',
      sizeMb: 330,
      notes:
          'أخف مرشح للأجهزة الاقتصادية — جودة أقل من Q4_K_M ويُفصح عن ذلك',
    ),
  ]);

  static final HttpClient _client = HttpClient();

  /// حقنة اختبار: مجلد النماذج بدل مجلد المستندات الفعلي
  @visibleForTesting
  static Directory? debugModelsDirOverride;

  /// حقنة اختبار: مصنع دفق بدل HttpClient (بلا شبكة في الاختبارات)
  @visibleForTesting
  static ByteStreamFactory? debugStreamFactory;

  /// مجلد النماذج داخل مساحة التطبيق الخاصة
  static Future<Directory> _modelsDir() async {
    final override = debugModelsDirOverride;
    if (override != null) return override;
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/wasl_models');
  }

  static ModelFetcher _fetcher(Directory dir) => ModelFetcher(
      modelsDir: dir,
      streamFactory: debugStreamFactory ?? _httpStream);

  /// دفق التنزيل الحقيقي من الناشر (تتبع إعادة التوجيه افتراضي في HttpClient)
  static Stream<List<int>> _httpStream(Uri url) async* {
    final request = await _client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode} من الناشر');
    }
    yield* response;
  }

  /// التنزيل الموثق الكامل لمصدر من الكتالوج — طوعي بموافقة الواجهة حصراً.
  /// على الويب غير متاح بعد (dart:io HttpClient) — يعود برسالة صادقة.
  static Future<FetchResult> fetch(
    ModelSource source, {
    void Function(FetchProgress p)? onProgress,
  }) async {
    if (kIsWeb) {
      const msg = 'التنزيل الموثق على الويب غير متاح بعد — يعمل على الجوال وسطح المكتب';
      onProgress?.call(FetchProgress(FetchState.failed, 0, 0, msg));
      return const FetchResult(
          ok: false, state: FetchState.failed, receivedBytes: 0, error: msg);
    }
    final fetcher = _fetcher(await _modelsDir());
    return fetcher.fetch(source, onProgress: onProgress);
  }

  /// جاهزية نموذج (الملف والبصمة المدونة مطابقان للمصدر)
  static Future<bool> isReady(ModelSource source) async {
    if (kIsWeb) return false;
    return _fetcher(await _modelsDir())
        .isReady(source.id, expectedSha256Hex: source.sha256Hex);
  }

  /// الإثبات الصارم: إعادة حساب البصمة من الملف نفسه — وإن خالف يُمحى.
  static Future<String?> verifyFull(ModelSource source) async {
    if (kIsWeb) return null;
    return _fetcher(await _modelsDir()).verifyFull(source);
  }

  /// حذف كامل بلا أثر (طوعي من الواجهة)
  static Future<void> delete(String id) async {
    if (kIsWeb) return;
    return _fetcher(await _modelsDir()).delete(id);
  }
}
