import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compressor_plus/video_compressor_plus.dart';

/// ضغط الفيديو ومصغّراته على الجهاز (0.4.8 — بند المرحلة 1).
///
/// التصميم الصادق:
/// - الضغط بمُرمّزات المنصة نفسها (MediaCodec على أندرويد، AVAssetExportSession
///   على iOS) — بلا ffmpeg وبلا مكتبات C، احتراماً لقيد المشروع «بلا كود
///   C أصلي لتسهيل البناء».
/// - المصغّرة (إطار JPEG صغير) تُدرج داخل meta الرسالة المشفّرة — فلا يرى
///   الخادم بيكسلاتها إطلاقاً، ولا ترحيل أعمدة جديدة.
/// - الضغط والمصغّرة «أفضل جهد»: أي فشل لا يمنع الإرسال — يُرسل الأصل
///   كما هو بلا مصغّرة، ولا يقفز سلوك الإرسال.
class VideoService {
  VideoService._();

  /// فوق هذا الحجم يُضغط الفيديو قبل الإرسال (تحت ما تبقى سريعاً)
  static const int compressThresholdBytes = 8 * 1024 * 1024; // 8 م.ب

  /// فوق هذا الحجم تُختار جودة أدقّ قسماً لضمان النزول تحت حد الرفع
  static const int bigFileBytes = 16 * 1024 * 1024; // 16 م.ب

  /// سقف المصغّرة بالبايت (JPEG) — base64 يضيف ثلثا الحجم، لذا
  /// 18000 بايت ≈ 24000 حرف، ضمن سقف محتوى الفيديو 30000 (ترحيل 026)
  /// مع هامش لاسم الملف والأرقام.
  static const int maxThumbBytes = 18000;

  /// جودة JPEG للمصغّرة (من 100)
  static const int thumbQuality = 60;

  /// سقف آمن لطول meta المشفّرة — تحت حد 026 بمقدار هامش
  static const int maxMetaChars = 29000;

  /// هل يحتاج هذا الحجم ضغطاً قبل الإرسال؟
  static bool shouldCompress(int bytes) => bytes > compressThresholdBytes;

  /// الجودة المناسبة حسب الحجم (دالة صافية مُختبرة):
  /// الأصغر من 16 م.ب → 720p، والأكبر → 540p لضمان النزول تحت 24 م.ب
  static VideoQuality qualityFor(int bytes) => bytes > bigFileBytes
      ? VideoQuality.Res960x540Quality
      : VideoQuality.Res1280x720Quality;

  /// ضغط فيديو على الجهاز — يعيد null عند أي فشل (أفضل جهد).
  /// الأصل لا يُحذف (deleteOrigin: false) حتى لا يفقد المستخدم ملفه.
  static Future<File?> compress(String path, {required int sizeBytes}) async {
    try {
      final info = await VideoCompress.compressVideo(
        path,
        quality: qualityFor(sizeBytes),
        deleteOrigin: false,
        includeAudio: true,
      );
      final outPath = info?.path;
      if (outPath == null) return null;
      final f = File(outPath);
      if (!await f.exists()) return null;
      // الضغط الذي لا يصغّر لا يفيد — نفضّل الأصل
      final outSize = await f.length();
      if (outSize >= sizeBytes) return null;
      return f;
    } catch (_) {
      return null;
    }
  }

  /// مصغّرة الجهاز (إطار أول) — null عند الفشل أو تجاوز السقف
  static Future<Uint8List?> thumbnail(String path) async {
    try {
      final bytes = await VideoCompress.getByteThumbnail(
        path,
        quality: thumbQuality,
        position: 0,
      );
      if (bytes == null || bytes.isEmpty) return null;
      if (bytes.length > maxThumbBytes) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// بناء meta الفيديو المشفّرة: الاسم والحجم وحجم الأصل عند الضغط
  /// والمصغّرة (base64). ترمي عند تجاوز السقف — المستدعي يزيل المصغّرة
  /// ويعيد المحاولة بدل إفشال الإرسال.
  static String metaJson({
    required String name,
    required int size,
    int? originalSize,
    String? thumbBase64,
  }) {
    final m = <String, dynamic>{
      'name': name,
      'size': size,
      if (originalSize != null && originalSize != size) 'orig': originalSize,
      if (thumbBase64 != null && thumbBase64.isNotEmpty) 'thumb': thumbBase64,
    };
    final json = jsonEncode(m);
    if (json.length > maxMetaChars) {
      throw StateError('meta الفيديو يتجاوز السقف ($maxMetaChars)');
    }
    return json;
  }

  /// meta بلا مصغّرة (طريق العودة عند تجاوز السقف)
  static String metaJsonWithoutThumb({
    required String name,
    required int size,
    int? originalSize,
  }) =>
      metaJson(name: name, size: size, originalSize: originalSize);

  /// حجم مصغّرة base64 بعد فكّها — للتحقق قبل فك فعلي في الفقاعة
  /// (base64 طوله 4×n: الحجم الفعلي ≈ الطول × 3/4)
  static int? thumbBytesFromBase64Length(String b64) {
    if (b64.isEmpty || b64.length > 40000) return null;
    final len = b64.length;
    // إزالة الحشو
    var padding = 0;
    if (len >= 1 && b64.endsWith('==')) {
      padding = 2;
    } else if (len >= 1 && b64.endsWith('=')) {
      padding = 1;
    }
    return len ~/ 4 * 3 - padding;
  }
}
