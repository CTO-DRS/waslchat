import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// خدمة تحويل صورة المُحرِّر (المرحلة 8 — 0.20.0): تُحوِّل بايتات PNG
/// الناتجة من التقاط لوحة التعديل إلى JPEG مضغوط يصلح للإرسال بحجم معقول.
///
/// منطق نقي بلا واجهة — يُختبَر في `image_edit_service_test.dart`.
/// الفشل يعيد المدخل كما هو (PNG) — «الفشل يهبط للسلوك السابق».
class ImageEditService {
  /// أقصى بُعد للصورة الناتجة (يطابق ضغط image_picker في الإرسال العادي)
  static const int maxSide = 1600;
  static const int quality = 85;

  /// نوع الصورة من توقيع البايتات (نقي — قابل للاختبار): jpeg/png/غير معروف
  static (String, String) contentTypeOf(Uint8List bytes) {
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return ('jpeg', 'image/jpeg');
    }
    if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return ('png', 'image/png');
    }
    return ('jpeg', 'image/jpeg');
  }

  static Future<Uint8List> pngToJpeg(Uint8List pngBytes, {int quality = quality}) async {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return pngBytes;
    var im = decoded;
    if (im.width > maxSide || im.height > maxSide) {
      final ratio = maxSide / (im.width > im.height ? im.width : im.height);
      im = img.copyResize(
          im,
          width: (im.width * ratio).round(),
          height: (im.height * ratio).round());
    }
    final jpg = img.encodeJpg(im, quality: quality.clamp(50, 95));
    // إن صار الناتج أكبر من الأصل (نادر مع PNG الرسومات البسيطة) نعيد الأصل
    return jpg.lengthInBytes < pngBytes.lengthInBytes ? jpg : pngBytes;
  }
}
