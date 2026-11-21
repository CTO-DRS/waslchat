import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wasl_chat/services/image_edit_service.dart';

/// توليد PNG متدرج الألوان بالحجم المطلوب (مكتبة image نقية داخل الاختبار)
Uint8List _makePng(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      p.r = (x * 4) % 256;
      p.g = (y * 4) % 256;
      p.b = 128;
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

/// توليد PNG شبيه بصورة فوتوغرافية (تدرج + تشويش حتمي) — JPEG يربح فيها عادة
Uint8List _makePhotoPng(int w, int h) {
  final im = img.Image(width: w, height: h);
  var seed = 987654321;
  int rnd() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return (seed >> 16) & 0x1f;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      p.r = (x * 2 + rnd()).clamp(0, 255);
      p.g = (y * 2 + rnd()).clamp(0, 255);
      p.b = ((x + y) + rnd()).clamp(0, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

bool _isJpeg(List<int> b) => b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;

void main() {
  group('نوع الصورة من التوقيع', () {
    test('توقيع JPEG يرجع jpeg', () {
      final (ext, mime) = ImageEditService.contentTypeOf(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]));
      expect(ext, 'jpeg');
      expect(mime, 'image/jpeg');
    });

    test('توقيع PNG يرجع png', () {
      final (ext, mime) = ImageEditService.contentTypeOf(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D]));
      expect(ext, 'png');
      expect(mime, 'image/png');
    });

    test('بلا توقيع معروف يهبط لـjpeg كالإرسال العادي', () {
      final (ext, mime) = ImageEditService.contentTypeOf(
          Uint8List.fromList([0x00, 0x01, 0x02]));
      expect(ext, 'jpeg');
      expect(mime, 'image/jpeg');
    });

    test('بالتات قصيرة لا تنفجر', () {
      expect(ImageEditService.contentTypeOf(Uint8List(0)).$1, 'jpeg');
      expect(
          ImageEditService.contentTypeOf(Uint8List.fromList([0xFF])).$1,
          'jpeg');
    });
  });

  group('تحويل PNG إلى JPEG', () {
    test('صورة شبيهة فوتوغرافياً تتحول إلى JPEG سليم التوقيع وأصغر حجماً', () async {
      final png = _makePhotoPng(160, 160);
      final jpg = await ImageEditService.pngToJpeg(png, quality: 85);
      expect(_isJpeg(jpg), isTrue, reason: 'الناتج JPEG سليم التوقيع');
      expect(jpg.length, lessThan(png.length),
          reason: 'JPEG أصغر من PNG للصور الواقعية');
    });

    test('عقد التحويل: JPEG أصغر أو المدخل نفسه — لا استثناء ولا خسارة', () async {
      // تدرج ناعم: PNG يضغطه أفضل من JPEG عند 64×64 — الخدمة تهبط للمدخل
      final png = _makePng(64, 64);
      final out = await ImageEditService.pngToJpeg(png, quality: 85);
      expect(
        out,
        anyOf(
          equals(png),
          predicate(_isJpeg, 'JPEG سليم التوقيع'),
        ),
      );
    });

    test('حد الأقصى للبعد هو 1600 مطابق لضغط الإرسال العادي', () {
      expect(ImageEditService.maxSide, 1600);
      expect(ImageEditService.quality, inInclusiveRange(50, 95));
    });

    test('بايتات تالفة غير قابلة للفك تعيد المدخل كما هو (PNG)', () async {
      final junk = Uint8List.fromList([1, 2, 3, 4, 5]);
      final out = await ImageEditService.pngToJpeg(junk);
      expect(out, equals(junk));
    });
  });
}
