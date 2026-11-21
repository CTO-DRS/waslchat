/// تنزيل موثق لنموذج على الجهاز — محرك وصل النقية الثامن.
///
/// العقد الصادق (خلاصة docs/ON_DEVICE_LLM.md وGRAND_PLAN_3 المرحلة 18):
/// لا يُنزَّل شيء تلقائياً ولا يُفرض على أحد — التدفق هنا يمكّن الواجهة
/// الصريحة: مصدر موثق (رابط + بصمة SHA-256 منشورة من ناشر النموذج) يحوَّل
/// إلى ملف مؤقت `.part` مع حساب البصمة على الطاير، ثم تحقق إلزامي قبل
/// إعادة التسمية الذرية إلى `.gguf`، وإلا يُمحى المؤقت ولا يُعتمد شيء.
/// بلا شبكة داخلية: دفق البايتات يُحقن من الخارج (الاختبارات تمرر ملفاً
/// محلياً، والتطبيق يمرر HttpClient) — فبقى المحرك نقياً بلا اعتماديات.
library;

import 'dart:async';
import 'dart:io';

import 'sha256.dart';

/// مصدر تنزيل موثق: كل قيمه من الناشر نفسه (HuggingFace API يوفر lfs.oid
/// ببصمة SHA-256 للملف) — لا بصمة مخترعة ولا رابط مهيأ.
class ModelSource {
  const ModelSource({
    required this.id,
    required this.label,
    required this.url,
    required this.sha256Hex,
    required this.sizeMb,
    required this.notes,
  });

  /// مُعرّف ثابت (يصير اسم الملف محفوظاً)
  final String id;

  /// اسم بشري للعرض في الواجهة
  final String label;

  /// رابط التنزيل المباشر من الناشر
  final Uri url;

  /// البصمة المنشورة — ملف بلا هذه البصمة لا يُعتمد أبداً
  final String sha256Hex;

  /// الحجم المعلن بالميغابايت (لعرضه بصراحة قبل التنزيل)
  final int sizeMb;

  /// ملاحظات صادقة عن قدرات النموذج وحدوده
  final String notes;

  /// البصمة بمقارنة صغيرة الأحرف الموحدة
  String get normalizedSha256 => sha256Hex.trim().toLowerCase();
}

/// حالات التنزيل المتتالية الصادقة.
enum FetchState { downloading, verifying, ready, failed }

/// لقطة تقدم تُبثّ للواجهة أثناء التنزيل.
class FetchProgress {
  const FetchProgress(this.state, this.receivedBytes, this.totalBytes, [this.error]);

  final FetchState state;
  final int receivedBytes;

  /// الحجم الكلي المعلن (قد يعجز عن المطابقة إن غيّر الناشر الملف —
  /// التحكم الحاسم هو البصمة لا الحجم)
  final int totalBytes;

  /// سبب الفشل إن كانت الحالة failed
  final String? error;

  /// نسبة 0..100 أو null إن كان الكلي صفراً
  double? get percent =>
      totalBytes <= 0 ? null : (receivedBytes * 100 / totalBytes).clamp(0, 100);
}

/// نتيجة نهائية لعملية تنزيل كاملة.
class FetchResult {
  const FetchResult({required this.ok, required this.state, required this.receivedBytes, this.error});

  final bool ok;
  final FetchState state;
  final int receivedBytes;
  final String? error;
}

/// مصنع دفق البايتات — حقنة الاختبار/التطبيق (بلا شبكة داخلية).
typedef ByteStreamFactory = Stream<List<int>> Function(Uri url);

/// المُنزّل: دفق → `.part` مع بصمة على الطاير → تحقق → إعادة تسمية ذرية.
class ModelFetcher {
  ModelFetcher({required this.modelsDir, this.streamFactory, this.totalBytesHint = true});

  /// مجلد تخزين النماذج (التطبيق يمرر مجلد المستندات/wasl_models)
  final Directory modelsDir;

  /// مصنع الدفق — إن غاب فالتدفق يمرر `byteStream` يدوياً في كل نداء
  final ByteStreamFactory? streamFactory;

  /// هل يُبَثّ totalBytes من طول المواصفة المعلن (لحساب النسبة)
  final bool totalBytesHint;

  File _partFile(String id) => File('${_path}/${_safe(id)}.part');
  File _doneFile(String id) => File('${_path}/${_safe(id)}.gguf');
  File _digestFile(String id) => File('${_path}/${_safe(id)}.sha256');

  String get _path => modelsDir.path;

  /// أسماء الملفات من المعرّف فقط — منع أي خروج عن مجلد النماذج (لا شرطة
  /// لا نقطتين لا صعود مسار)
  String _safe(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  /// التدفق الرئيسي: تنزيل موثق كامل بتحقق إلزامي قبل الاعتماد.
  ///
  /// [byteStream] يتجاوز المصنع المحقون (لاختبار دفعة معينة مباشرة).
  Future<FetchResult> fetch(
    ModelSource source, {
    void Function(FetchProgress p)? onProgress,
    Stream<List<int>>? byteStream,
  }) async {
    try {
      await modelsDir.create(recursive: true);
    } catch (e) {
      onProgress?.call(FetchProgress(FetchState.failed, 0, 0, 'تعذر تجهيز مجلد النماذج: $e'));
      return FetchResult(ok: false, state: FetchState.failed, receivedBytes: 0, error: 'mkdir: $e');
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
            FetchState.downloading, received, totalBytesHint ? source.sizeMb * 1048576 : 0));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress?.call(FetchProgress(FetchState.verifying, received, received));
      final digest = hasher.digestHex();
      if (digest != source.normalizedSha256) {
        // البصمة لا تطابق — المؤقت يُمحى ولا يُعتمد شيء أبداً
        if (await partFile.exists()) await partFile.delete();
        const msg = 'بصمة الملف المحوَّل لا تطابق بصمة الناشر — أُلغي الاعتماد وحُذف المؤقت';
        onProgress?.call(FetchProgress(FetchState.failed, received, received, msg));
        return FetchResult(ok: false, state: FetchState.failed, receivedBytes: received, error: msg);
      }
      await partFile.rename(_doneFile(source.id).path);
      await _digestFile(source.id).writeAsString(digest);
      onProgress?.call(FetchProgress(FetchState.ready, received, received));
      return FetchResult(ok: true, state: FetchState.ready, receivedBytes: received);
    } catch (e) {
      // أي فشل شبكة/قراءة: أغلق وأمسح المؤقت فلا يبقى نصف ملف يوهم المستخدم
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      onProgress?.call(FetchProgress(FetchState.failed, received, received, '$e'));
      return FetchResult(ok: false, state: FetchState.failed, receivedBytes: received, error: '$e');
    }
  }

  Stream<List<int>> _requireStream(Uri url) {
    final f = streamFactory;
    if (f == null) {
      throw StateError('لا مصنع دفق محقون — مرر streamFactory أو byteStream');
    }
    return f(url);
  }

  /// جاهزية رخيصة: الملف النهائي موجود والبصمة المدونة عند اكتمال التنزيل
  /// تطابق بصمة المصدر المعلنة (إن أعطيت) — بلا إعادة حساب كاملة.
  /// الإثبات الصارم لحظة الاعتماد يمر عبر [verifyFull].
  Future<bool> isReady(String id, {String? expectedSha256Hex}) async {
    final done = _doneFile(id);
    final digest = _digestFile(id);
    if (!await done.exists() || !await digest.exists()) return false;
    if (expectedSha256Hex == null) return true;
    final recorded = (await digest.readAsString()).trim().toLowerCase();
    return recorded == expectedSha256Hex.trim().toLowerCase();
  }

  /// الإثبات الكامل: إعادة حساب البصمة من الملف النهائي نفسه — تعيد البصمة
  /// إن كان الملف سليماً مطابقاً للمعلن، وتعيد null مع حذف الملف إن خالف.
  Future<String?> verifyFull(ModelSource source) async {
    final done = _doneFile(source.id);
    if (!await done.exists()) return null;
    final hasher = Sha256();
    await for (final chunk in done.openRead()) {
      hasher.update(chunk);
    }
    final digest = hasher.digestHex();
    if (digest != source.normalizedSha256) {
      // تلف بعد الاعتماد — الصدق: نمحي ولا أدّعي الجاهزية
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

  /// حذف كامل: النهائي والمؤقت والبصمة المدونة — بلا أثر.
  Future<void> delete(String id) async {
    for (final f in [_doneFile(id), _partFile(id), _digestFile(id)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
