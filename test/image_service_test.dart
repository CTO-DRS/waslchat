import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wasl_chat/services/image_service.dart';

Uint8List _b(List<int> l) => Uint8List.fromList(l);

/// ضجيج حقيقي غير قابل للضغط (Random لا LCG — الأنماط المتكررة تنضغط)
Uint8List _noiseJpeg(int w, int h, {int quality = 95}) {
  final im = img.Image(width: w, height: h);
  final r = Random();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(x, y, r.nextInt(256), r.nextInt(256), r.nextInt(256), 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: quality));
}

Uint8List _noisePng(int w, int h) {
  final im = img.Image(width: w, height: h);
  final r = Random();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(x, y, r.nextInt(256), r.nextInt(256), r.nextInt(256), 255);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  group('detectKind — الكشف من التوقيع لا الامتداد', () {
    test('JPEG: FF D8 FF', () {
      expect(
          ImageService.detectKind(_b([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6, 7, 8])),
          ImageKind.jpeg);
    });
    test('PNG: 89 50 4E 47 …', () {
      expect(
          ImageService.detectKind(
              _b([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 1])),
          ImageKind.png);
    });
    test('GIF87a و GIF89a', () {
      expect(ImageService.detectKind(_b('GIF87a'.codeUnits + [0, 0, 0, 0, 0, 0])),
          ImageKind.gif);
      expect(ImageService.detectKind(_b('GIF89a'.codeUnits + [0, 0, 0, 0, 0, 0])),
          ImageKind.gif);
    });
    test('webp: RIFF....WEBP', () {
      expect(
          ImageService.detectKind(
              _b('RIFF'.codeUnits + [24, 0, 0, 0] + 'WEBP'.codeUnits + [0, 0, 0, 0])),
          ImageKind.webp);
    });
    test('heic: ftyp + brand heic', () {
      expect(
          ImageService.detectKind(_b([0, 0, 0, 24] + 'ftyp'.codeUnits +
              'heic'.codeUnits + [0, 0, 0, 0])),
          ImageKind.heic);
      expect(
          ImageService.detectKind(_b([0, 0, 0, 24] + 'ftyp'.codeUnits +
              'avif'.codeUnits + [0, 0, 0, 0])),
          ImageKind.heic);
    });
    test('ftyp غير صورة (mp4) = unknown', () {
      expect(
          ImageService.detectKind(_b([0, 0, 0, 24] + 'ftyp'.codeUnits +
              'isom'.codeUnits + [0, 0, 0, 0])),
          ImageKind.unknown);
    });
    test('أقصر من 12 بايت أو أصفار = unknown', () {
      expect(ImageService.detectKind(_b([0xFF, 0xD8])), ImageKind.unknown);
      expect(ImageService.detectKind(_b([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
          ImageKind.unknown);
    });
    test('صور حقيقية مولّدة: jpeg/png من الترميز الفعلي', () {
      final jpg = _noiseJpeg(50, 50);
      final png = _noisePng(50, 50);
      expect(ImageService.detectKind(jpg), ImageKind.jpeg);
      expect(ImageService.detectKind(png), ImageKind.png);
    });
  });

  group('isAnimatedWebp — مشي القطع لا البحث الأعمى', () {
    Uint8List webp(List<int> chunks) =>
        _b('RIFF'.codeUnits + [0, 0, 0, 0] + 'WEBP'.codeUnits + chunks);
    test('قطعة ANMF = متحركة', () {
      final chunks = 'ANMF'.codeUnits + [4, 0, 0, 0] + [1, 2, 3, 4];
      expect(ImageService.isAnimatedWebp(webp(chunks)), isTrue);
    });
    test('قطعة ANIM وحدها = متحركة', () {
      final chunks = 'ANIM'.codeUnits + [2, 0, 0, 0] + [1, 0];
      expect(ImageService.isAnimatedWebp(webp(chunks)), isTrue);
    });
    test('VP8 ساكن = غير متحركة', () {
      final chunks = 'VP8 '.codeUnits + [2, 0, 0, 0] + [1, 2];
      expect(ImageService.isAnimatedWebp(webp(chunks)), isFalse);
    });
    test('النص ANMF داخل حمولة VP8 لا يكذب', () {
      // نص مزيّف داخل بيانات الضغط — المشي على القطع لن يراه قطعة مستقلة
      final chunks = 'VP8 '.codeUnits + [4, 0, 0, 0] + 'ANMF'.codeUnits;
      expect(ImageService.isAnimatedWebp(webp(chunks)), isFalse);
    });
    test('غير webp أصلاً = false', () {
      expect(ImageService.isAnimatedWebp(_b([0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
          isFalse);
    });
  });

  group('looksAnimatedGif', () {
    test('NETSCAPE2.0 = متحرك', () {
      final b = _b('GIF89a'.codeUnits +
          [0, 0, 0, 0, 0, 0, 0] +
          [0x21, 0xFF, 0x0B] +
          'NETSCAPE2.0'.codeUnits +
          [3, 1, 0, 0, 0]);
      expect(ImageService.looksAnimatedGif(b), isTrue);
    });
    test('كتلتا تحكم جرافيكي 21 F9 = متحرك', () {
      final gce = [0x21, 0xF9, 0x04, 1, 2, 3, 4, 0];
      final b = _b('GIF89a'.codeUnits + [0, 0, 0, 0, 0, 0, 0] + gce + gce);
      expect(ImageService.looksAnimatedGif(b), isTrue);
    });
    test('GIF ساكن بلا امتدادات = false', () {
      final b = _b('GIF89a'.codeUnits + [0, 0, 0, 0, 0, 0, 0, 0x2C]);
      expect(ImageService.looksAnimatedGif(b), isFalse);
    });
    test('غير gif أصلاً = false', () {
      expect(ImageService.looksAnimatedGif(_noisePng(10, 10)), isFalse);
    });
  });

  group('isAnimated', () {
    test('gif دائماً متحرك (حتى الساكن يُرَسَل كما هو)', () {
      expect(ImageService.isAnimated(ImageKind.gif, Uint8List(0)), isTrue);
    });
    test('webp متحركة فقط عبر فحص القطع', () {
      final staticWebp = _b('RIFF'.codeUnits +
          [0, 0, 0, 0] + 'WEBP'.codeUnits + 'VP8 '.codeUnits + [2, 0, 0, 0] + [1, 2]);
      final animWebp = _b('RIFF'.codeUnits +
          [0, 0, 0, 0] + 'WEBP'.codeUnits + 'ANMF'.codeUnits + [1, 0, 0, 0] + [9]);
      expect(ImageService.isAnimated(ImageKind.webp, staticWebp), isFalse);
      expect(ImageService.isAnimated(ImageKind.webp, animWebp), isTrue);
    });
  });

  group('decide — القرار الصادق', () {
    test('heic يُرفض برسالة واضحة', () {
      final (reject, ds) = ImageService.decide(ImageKind.heic, 1000);
      expect(reject, isNotNull);
      expect(reject, contains('HEIC'));
      expect(ds, isFalse);
    });
    test('gif/webp فوق 12 م.ب يُرفض، وتحته يُمرَّر كما هو', () {
      final (r1, d1) = ImageService.decide(ImageKind.gif, 13 * 1024 * 1024);
      expect(r1, isNotNull);
      expect(d1, isFalse);
      final (r2, d2) = ImageService.decide(ImageKind.gif, 11 * 1024 * 1024);
      expect(r2, isNull);
      expect(d2, isFalse);
      final (r3, d3) = ImageService.decide(ImageKind.webp, 5 * 1024 * 1024);
      expect(r3, isNull);
      expect(d3, isFalse);
    });
    test('jpeg/png فوق 3 م.ب يُصغَّر، وتحته يمر كما هو', () {
      final (r1, d1) = ImageService.decide(ImageKind.jpeg, 4 * 1024 * 1024);
      expect(r1, isNull);
      expect(d1, isTrue);
      final (r2, d2) = ImageService.decide(ImageKind.png, 2 * 1024 * 1024);
      expect(r2, isNull);
      expect(d2, isFalse);
    });
    test('unknown يمر كما هو بلا لمس', () {
      final (r, d) = ImageService.decide(ImageKind.unknown, 20 * 1024 * 1024);
      expect(r, isNull);
      expect(d, isFalse);
    });
  });

  group('downscale — تصغير ساكن بلا فقدان الشفافية', () {
    test('أصغر من الحد = null (لا تغيير)', () {
      expect(ImageService.downscale(_noiseJpeg(100, 100)), isNull);
    });
    test('jpeg كبير يُصغَّر إلى 1600 مع حفظ النسبة', () {
      final big = _noiseJpeg(2000, 1000);
      final out = ImageService.downscale(big);
      expect(out, isNotNull);
      expect(out!.lengthInBytes, lessThan(big.lengthInBytes));
      final dec = img.decodeImage(out)!;
      expect(dec.width, 1600);
      expect(dec.height, 800);
    });
    test('png يبقى png (الشفافية محفوظة)', () {
      final big = _noisePng(2000, 800);
      final out = ImageService.downscale(big, keepPng: true);
      expect(out, isNotNull);
      expect(ImageService.detectKind(out!), ImageKind.png);
      final dec = img.decodeImage(out)!;
      expect(dec.width, 1600);
      expect(dec.height, 640);
    });
    test('ناتج أكبر من الأصل يُهمل ويعيد null', () {
      // صورة رمادية موحدة تصغّرها ينتج png ضخم نسبياً مقابل jpeg أصلي صغير
      final tinyJpeg = _noiseJpeg(1700, 1700, quality: 10);
      // نجبر المسار: نسبة صغيرة فقط — إذا كان الناتج أكبر يُهمل
      final out = ImageService.downscale(tinyJpeg, quality: 10);
      // قد يكون null أو أصغر — لا يجوز أن يكون أكبر من الأصل
      if (out != null) {
        expect(out.lengthInBytes, lessThan(tinyJpeg.lengthInBytes));
      }
    });
    test('بايتات غير قابلة للفك = null', () {
      expect(ImageService.downscale(_b([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])),
          isNull);
    });
    test('downscaleAsync يعمل خارج الخيط الرئيسي ويعيد النتيجة نفسها', () async {
      final big = _noiseJpeg(2000, 1000);
      final out = await ImageService.downscaleAsync(big);
      expect(out, isNotNull);
      expect(out!.lengthInBytes, lessThan(big.lengthInBytes));
    });
  });
}
