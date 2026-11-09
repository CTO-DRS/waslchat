import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// كشف نوع الصورة من توقيع البايتات (لا من الامتداد — الامتداد يكذب)
/// والقرارات الصادقة لإرسال الصور من المعرض دون أن يضغطها المنتقي:
/// المعرض يُرسل الأصل كما هو حفاظاً على GIF/webp المتحركة، والتصغير
/// الساكن للكبير يقع علينا هنا بمكتبة pure-Dart (بلا كود C أصلي).
enum ImageKind { jpeg, png, gif, webp, heic, unknown }

class ImageService {
  ImageService._();

  /// حدّ التصغير: الصور الساكنة فوقه تُصغَّر على الجهاز قبل الرفع (3 ميغابايت)
  static const int downscaleThreshold = 3 * 1024 * 1024;

  /// حدّ الإرسال للصور التي لا يُمكن تصغيرها (المتحركة): 12 ميغابايت
  static const int animatedMaxBytes = 12 * 1024 * 1024;

  /// أقصى ضلع بعد التصغير — مطابق لسلوك المنتقي السابق (1600)
  static const int maxSide = 1600;

  /// كشف النوع من التوقيع. امتداد الملف لا يُعتد به إطلاقاً هنا.
  static ImageKind detectKind(Uint8List b) {
    if (b.length < 12) return ImageKind.unknown;
    // GIF87a / GIF89a
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return ImageKind.gif;
    // JPEG: FF D8 FF
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return ImageKind.jpeg;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    var isPng = true;
    for (var i = 0; i < 8; i++) {
      if (b[i] != png[i]) {
        isPng = false;
        break;
      }
    }
    if (isPng) return ImageKind.png;
    // RIFF....WEBP
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return ImageKind.webp;
    }
    // ISO-BMFF (ftyp عند 4..8) — العلامات المعروفة للصور عالية الكفاءة
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      final brand = String.fromCharCodes(b.sublist(8, 12));
      const heifBrands = {'heic', 'heix', 'mhe1', 'heif', 'hevc', 'hevx', 'avif'};
      if (heifBrands.contains(brand)) return ImageKind.heic;
    }
    return ImageKind.unknown;
  }

  /// webp متحركة: تمشي على كل القطع (fourcc + حجم + حمولة + حشوة لِزوجية)
  /// وتتقصى وجود ANMF — البحث الأعمى عن النص قد يكذب داخل بيانات الضغط.
  static bool isAnimatedWebp(Uint8List b) {
    if (detectKind(b) != ImageKind.webp) return false;
    var off = 12;
    while (off + 8 <= b.length) {
      final cc = String.fromCharCodes(b.sublist(off, off + 4));
      final size = (b[off + 4] |
              (b[off + 5] << 8) |
              (b[off + 6] << 16) |
              (b[off + 7] << 24)) &
          0xFFFFFFFF;
      if (cc == 'ANMF' || cc == 'ANIM') return true;
      off += 8 + size + (size.isOdd ? 1 : 0);
    }
    return false;
  }

  /// GIF متحرك: امتداد NETSCAPE2.0 (حلقة التكرار) أو أكثر من كتلة
  /// تحكم جرافيكية (21 F9) — فحصا تسلسل بايتات بسيطان وصادقان.
  static bool looksAnimatedGif(Uint8List b) {
    if (detectKind(b) != ImageKind.gif) return false;
    var netscape = false;
    var gce = 0;
    for (var i = 0; i + 3 <= b.length; i++) {
      if (!netscape &&
          b[i] == 0x21 &&
          b[i + 1] == 0xFF &&
          i + 14 <= b.length &&
          b[i + 2] == 0x0B &&
          _asciiAt(b, i + 3, 'NETSCAPE2.0')) {
        netscape = true;
      }
      if (b[i] == 0x21 && b[i + 1] == 0xF9 && b[i + 2] == 0x04) gce++;
    }
    return netscape || gce >= 2;
  }

  static bool _asciiAt(Uint8List b, int off, String s) {
    if (off + s.length > b.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[off + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// هل هذا النوع يُرسل كما هو بلا تصغير؟ (المتحركة لا تُمَس)
  static bool isAnimated(ImageKind k, Uint8List b) =>
      k == ImageKind.gif || (k == ImageKind.webp && isAnimatedWebp(b));

  /// قرار الإرسال: سبب رفض أو هل تحتاج تصغيراً — بلا أي عملية خفية
  static (String? reject, bool downscale) decide(ImageKind k, int sizeBytes) {
    switch (k) {
      case ImageKind.heic:
        return ('صيغة HEIC غير مدعومة للإرسال المباشر', false);
      case ImageKind.gif:
      case ImageKind.webp:
        return (sizeBytes > animatedMaxBytes
            ? 'الصورة المتحركة أكبر من 12 ميغابايت'
            : null, false);
      case ImageKind.jpeg:
      case ImageKind.png:
        return (null, sizeBytes > downscaleThreshold);
      case ImageKind.unknown:
        return (null, false); // تُرسل كما هي — لا نلمس ما لا نعرفه
    }
  }

  /// تصغير ساكن: يفكّ ويصغّر ويعيد الترميز بنفس الصيغة، ويعيد null
  /// إذا لم يكن التصغير مجدياً (الصورة صغيرة أصلاً أو الناتج أكبر من الأصل).
  static Uint8List? downscale(Uint8List bytes,
      {bool keepPng = false, int maxSide = ImageService.maxSide, int quality = 85}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final w = decoded.width, h = decoded.height;
    if (w <= maxSide && h <= maxSide) return null;
    final ratio = maxSide / (w > h ? w : h);
    final nw = (w * ratio).round(), nh = (h * ratio).round();
    final small = img.copyResize(decoded, width: nw, height: nh);
    final out = keepPng
        ? Uint8List.fromList(img.encodePng(small))
        : Uint8List.fromList(img.encodeJpg(small, quality: quality));
    if (out.lengthInBytes >= bytes.lengthInBytes) return null;
    return out;
  }

  /// نفس العملية خارج الخيط الرئيسي — فكّ صورة 12 م.ب قد يستغرق ثوانٍ
  static Future<Uint8List?> downscaleAsync(Uint8List bytes,
          {bool keepPng = false}) =>
      compute(_downscaleIsolate, (bytes, keepPng));

  static Uint8List? _downscaleIsolate((Uint8List, bool) args) =>
      downscale(args.$1, keepPng: args.$2);
}
