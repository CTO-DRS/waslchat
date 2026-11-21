/// اختبارات استوديو الوسائط الموحد (المرحلة 22 — 1.20.0): رياضيات البكسل
/// الفعلية (قص/تدوير/قلب بأبعاد وبكسلات معروفة)، حدود معلنة تجمع كل
/// الأسباب، رفض صريح للقص خارج الحدود، تعليقات صادقة (لاتيني يُرسم،
/// عربي يُحمل للواجهة بلا ادعاء)، دمج شبكي صادق الأبعاد، وحتمية كاملة.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:wasl_mediastudio/wasl_mediastudio.dart';

/// صورة اختبار 20×12: كل بكسل بترميز فريد من إحداثيه — قابلة للتتبع
/// بعد أي تحويل (بكسل (x,y) = (x*7 % 256, y*5 % 256, x+y)).
img.Image _patternImage({int w = 20, int h = 12}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(x, y, (x * 7) % 256, (y * 5) % 256, (x + y) % 256, 255);
    }
  }
  return im;
}

Uint8List _bytes(img.Image im, {bool png = false}) => Uint8List.fromList(
    png ? img.encodePng(im) : img.encodeJpg(im, quality: 95));

bool _pxEq(img.Image im, int x, int y, img.Color c) {
  final p = im.getPixel(x, y);
  return p.r == c.r && p.g == c.g && p.b == c.b;
}

void main() {
  group('القص — رياضيات بكسل معروفة', () {
    test('قص مستطيل داخلي: الأبعاد والبكسلات من المواضع الصحيحة', () async {
      final src = _patternImage();
      final studio = MediaStudio();
      final out = await studio.apply(
          _bytes(src, png: true), [const MediaCrop(4, 2, 8, 6)],
          format: 'png');
      expect(out.isOk, isTrue, reason: out.isRefused ? out.refusal.reasons.toString() : '');
      final r = out.result;
      expect(r.width, 8);
      expect(r.height, 6);
      final decoded = img.decodeImage(r.bytes)!;
      // الزاوية العلوية اليسرى للقص = بكسل المصدر (4,2)
      expect(
          _pxEq(decoded, 0, 0,
              src.getPixel(4, 2)),
          isTrue);
      // الزاوية السفلية اليمنى للقص = بكسل المصدر (11,7)
      expect(
          _pxEq(decoded, 7, 5, src.getPixel(11, 7)),
          isTrue);
    });

    test('القص خارج الحدود رفض صريح — لا قصّ صامت يكذب بالنتيجة', () async {
      final studio = MediaStudio();
      final out = await studio.apply(
          _bytes(_patternImage()), [const MediaCrop(15, 0, 10, 6)]);
      expect(out.isRefused, isTrue);
      expect(out.refusal.reasons.first, contains('خارج حدود'));
    });
  });

  group('التدوير والقلب', () {
    test('تدوير 90°: الأبعاد تنعكس والبكسلات على الخريطة المعروفة', () async {
      final src = _patternImage(); // 20×12
      final studio = MediaStudio();
      final out = await studio.apply(_bytes(src, png: true),
          [const MediaRotate(90)], format: 'png');
      expect(out.isOk, isTrue, reason: out.isRefused ? out.refusal.reasons.toString() : '');
      expect(out.result.width, 12);
      expect(out.result.height, 20);
      final rotated = img.decodeImage(out.result.bytes)!;
      // تدوير 90° مع عقارب الساعة: dst(x,y) = src(y, W-1-x)
      // نتحقق بالبكسل الفريد: src(4,2) يظهر في dst(2, 20-1-4)
      final marker = src.getPixel(4, 2);
      int? foundX;
      int? foundY;
      for (var y = 0; y < rotated.height; y++) {
        for (var x = 0; x < rotated.width; x++) {
          if (_pxEq(rotated, x, y, marker)) {
            foundX = x;
            foundY = y;
          }
        }
      }
      // توقيع البكسل فريد كفاية (شبكة منتظمة) — وجوده مضمون بموضع واحد
      expect(foundX, isNotNull);
      expect(foundY, isNotNull);
      // والخريطة المعروفة لتدوير 90° مع عقارب الساعة تطابق الموضع الموجود
      expect(foundX, 2, reason: 'dst.x = src.y');
      expect(foundY, 20 - 1 - 4, reason: 'dst.y = W-1-src.x (W=20 قبل الدوران)');
    });

    test('زاوية غير مضاعفة 90 رفض صريح', () async {
      final studio = MediaStudio();
      final out = await studio.apply(
          _bytes(_patternImage()), [const MediaRotate(45)]);
      expect(out.isRefused, isTrue);
      expect(out.refusal.reasons.first, contains('مضاعفات 90'));
    });

    test('قلب أفقي: العمود الأول يصير الأخير', () async {
      final src = _patternImage();
      final studio = MediaStudio();
      final out = await studio.apply(
          _bytes(src, png: true), [const MediaFlip.horizontal()],
          format: 'png');
      expect(out.isOk, isTrue);
      final flipped = img.decodeImage(out.result.bytes)!;
      expect(_pxEq(flipped, 0, 0, src.getPixel(19, 0)), isTrue);
      expect(_pxEq(flipped, 19, 0, src.getPixel(0, 0)), isTrue);
    });

    test('ترتيب السلسلة يغير النتيجة: قص-ثم-تدوير ≠ تدوير-ثم-قص', () async {
      final src = _patternImage();
      final studio = MediaStudio();
      final a = await studio.apply(
          _bytes(src, png: true),
          [const MediaCrop(0, 0, 10, 10), const MediaRotate(90)],
          format: 'png');
      final b = await studio.apply(
          _bytes(src, png: true),
          [const MediaRotate(90), const MediaCrop(0, 0, 10, 10)],
          format: 'png');
      expect(a.isOk && b.isOk, isTrue);
      // (أ) ناتجه 10×10 مقلوبة الأبعاد، و(ب) قصّ من صورة مختلفة الأبعاد
      expect(a.result.width, 10);
      expect(a.result.height, 10);
      expect(b.result.width, 10);
      expect(b.result.height, 10);
      // والبكسلات مختلفة (مصادر مختلفة بعد الدوران)
      final da = img.decodeImage(a.result.bytes)!;
      final db = img.decodeImage(b.result.bytes)!;
      var equal = true;
      for (var y = 0; y < 10 && equal; y++) {
        for (var x = 0; x < 10 && equal; x++) {
          if (!_pxEq(da, x, y, db.getPixel(x, y))) equal = false;
        }
      }
      expect(equal, isFalse, reason: 'الترتيب جزء من العقد');
    });
  });

  group('التصغير والترميز', () {
    test('تصغير محافظ النسبة ولا تكبير أبداً', () async {
      final src = _patternImage(); // 20×12
      final studio = MediaStudio();
      final small = await studio.apply(
          _bytes(src, png: true), [const MediaResize(10)], format: 'png');
      expect(small.isOk, isTrue);
      expect(small.result.width, 10);
      expect(small.result.height, 6);
      // طلب تكبير صورة صغيرة: لا تكبير — تُعاد كما هي
      final tiny = await studio.apply(
          _bytes(_patternImage(w: 8, h: 8), png: true),
          [const MediaResize(100)],
          format: 'png');
      expect(tiny.isOk, isTrue);
      expect(tiny.result.width, 8);
      expect(tiny.result.height, 8);
    });

    test('ترميز PNG وJPEG بصيغة صادقة بالنتيجة', () async {
      final studio = MediaStudio();
      final pngOut = await studio.apply(_bytes(_patternImage(), png: true),
          [], format: 'png');
      final jpgOut = await studio.apply(
          _bytes(_patternImage()), [], format: 'jpeg');
      expect(pngOut.isOk && jpgOut.isOk, isTrue);
      expect(pngOut.result.format, 'png');
      expect(jpgOut.result.format, 'jpeg');
      expect(mediaContentTypeOf(pngOut.result.bytes).$2, 'image/png');
      expect(mediaContentTypeOf(jpgOut.result.bytes).$2, 'image/jpeg');
    });
  });

  group('التعليقات — الصدق قبل الجمال', () {
    test('تعليق لاتيني يرسم بكسلات سوداء في شريط أبيض أسفل الصورة', () async {
      final src = _patternImage(w: 120, h: 40); // أعرض من النص المرسوم
      final studio = MediaStudio();
      final out = await studio.apply(
          _bytes(src, png: true), [const MediaCaption('WASL 2026')],
          format: 'png');
      expect(out.isOk, isTrue, reason: out.isRefused ? out.refusal.reasons.toString() : '');
      expect(out.result.warnings, isEmpty);
      expect(out.result.uiCaptions, isEmpty);
      expect(out.result.height, greaterThan(40), reason: 'شريط التعليق أضاف ارتفاعاً');
      final drawn = img.decodeImage(out.result.bytes)!;
      // أسفل الصورة فيه بكسلات داكنة (النص المرسوم — الخطوط المدمجة
      // مضادة للتعرج فالعتبة ظلام لا سواد حرفي)
      var black = 0;
      for (var y = drawn.height - 36; y < drawn.height; y++) {
        for (var x = 0; x < drawn.width; x++) {
          final p = drawn.getPixel(x, y);
          if (p.r < 100 && p.g < 100 && p.b < 100) black++;
        }
      }
      expect(black, greaterThan(20), reason: 'حروف WASL مرسومة فعلاً');
    });

    test('تعليق عربي لا يُرسم بكسلاً — يُحمل للواجهة صادقاً بلا ادعاء', () async {
      final src = _patternImage(w: 120, h: 40);
      final studio = MediaStudio();
      final out = await studio.apply(
          _bytes(src, png: true), [const MediaCaption('وصل شات')],
          format: 'png');
      expect(out.isOk, isTrue);
      expect(out.result.uiCaptions, ['وصل شات'],
          reason: 'الخط النقطي لاتيني — العربي للواجهة بخطوط Flutter');
      expect(out.result.warnings, isNotEmpty);
      // ولم يتغير الارتفاع — لا رسم حصل
      expect(out.result.height, 40);
      expect(captionForUi('وصل شات'), 'وصل شات');
    });

    test('تعليق أطول من الحد رفض ضمن الأسباب المجمعة', () async {
      final studio = MediaStudio();
      final out = await studio.apply(_bytes(_patternImage()),
          [MediaCaption('a' * 100)]);
      expect(out.isRefused, isTrue);
      expect(out.refusal.reasons.first, contains('فوق الحد'));
    });
  });

  group('الدمج الشبكي (الكولاج)', () {
    test('صورتان مصمتتان أفقياً: أبعاد صادقة وفجوة وخلفية بارزة', () async {
      final red = img.Image(width: 10, height: 10);
      img.fill(red, color: img.ColorRgba8(200, 0, 0, 255));
      final blue = img.Image(width: 10, height: 10);
      img.fill(blue, color: img.ColorRgba8(0, 0, 200, 255));
      final studio = MediaStudio();
      final out = await studio.collage(
          [_bytes(red), _bytes(blue)],
          columns: 2, gap: 2, format: 'png');
      expect(out.isOk, isTrue, reason: out.isRefused ? out.refusal.reasons.toString() : '');
      expect(out.result.width, 22, reason: '10+2+10');
      expect(out.result.height, 10);
      final c = img.decodeImage(out.result.bytes)!;
      expect(_pxEq(c, 0, 0, img.ColorRgba8(200, 0, 0, 255)), isTrue);
      // الفجوة خلفية بيضاء
      expect(_pxEq(c, 11, 0, img.ColorRgba8(255, 255, 255, 255)), isTrue);
      expect(_pxEq(c, 12, 0, img.ColorRgba8(0, 0, 200, 255)), isTrue);
    });

    test('بلاطات مختلفة الأبعاد محافظة النسبة داخل البلاطة بلا تشويه', () async {
      final red = img.Image(width: 10, height: 6);
      img.fill(red, color: img.ColorRgba8(200, 0, 0, 255));
      final blue = img.Image(width: 6, height: 10);
      img.fill(blue, color: img.ColorRgba8(0, 0, 200, 255));
      final studio = MediaStudio();
      final out = await studio.collage(
          [_bytes(red), _bytes(blue)], columns: 2, format: 'png');
      expect(out.isOk, isTrue, reason: out.isRefused ? out.refusal.reasons.toString() : '');
      // أقصى ضلع بين البلاطتين = 10 فالبلاطة 10×10 واللوحة 22×10
      expect(out.result.width, 22);
      expect(out.result.height, 10);
      final c = img.decodeImage(out.result.bytes)!;
      // الأحمر 10×6 توسّط رأسياً: صفان خلفية ثم أحمر من الصف 2
      expect(_pxEq(c, 0, 0, img.ColorRgba8(255, 255, 255, 255)), isTrue);
      expect(_pxEq(c, 0, 2, img.ColorRgba8(200, 0, 0, 255)), isTrue);
    });

    test('رفض الدمج: بلاطات فوق الحد وأعمدة غير صالحة — أسباب مجمعة', () async {
      final red = img.Image(width: 4, height: 4);
      img.fill(red, color: img.ColorRgba8(200, 0, 0, 255));
      final tinyLimits = const MediaStudioLimits(maxCollageTiles: 2);
      final studio = MediaStudio(limits: tinyLimits);
      final out = await studio.collage(
          [_bytes(red), _bytes(red), _bytes(red)], columns: 4);
      expect(out.isRefused, isTrue);
      expect(out.refusal.reasons.length, 2,
          reason: 'الحد والأعمدة يجمعان معاً لا أولهما');
      expect(out.refusal.reasons.any((r) => r.contains('البلاطات')), isTrue);
      expect(out.refusal.reasons.any((r) => r.contains('الأعمدة')), isTrue);
    });
  });

  group('الحدود المعلنة — كل الأسباب لا أولها', () {
    test('حجم + بكسلات + عدد عمليات تُجمع معاً في رفض واحد', () async {
      final tiny = const MediaStudioLimits(
          maxInputBytes: 10, maxPixels: 100, maxOps: 1);
      final studio = MediaStudio(limits: tiny);
      final bytes16 = _bytes(_patternImage(w: 16, h: 16)); // 256 بكسل
      final out = await studio.apply(bytes16, [
        const MediaCrop(0, 0, 2, 2),
        const MediaRotate(90),
      ]);
      expect(out.isRefused, isTrue);
      expect(out.refusal.reasons.length, greaterThanOrEqualTo(3),
          reason: 'الحجم والبكسلات والعدد — الثلاثة معاً');
      expect(out.refusal.reasons.any((r) => r.contains('حجم المدخل')), isTrue);
      expect(out.refusal.reasons.any((r) => r.contains('بكسلات المدخل')),
          isTrue);
      expect(out.refusal.reasons.any((r) => r.contains('عدد العمليات')),
          isTrue);
    });

    test('مدخل ليس صورة رفض صريح', () async {
      final studio = MediaStudio();
      final out = await studio.apply(
          Uint8List.fromList([1, 2, 3, 4, 5]), []);
      expect(out.isRefused, isTrue);
      expect(out.refusal.reasons.first, contains('صورة معروفة'));
    });

    test('لا عمليات = إعادة ترميز صادقة بنفس الأبعاد', () async {
      final studio = MediaStudio();
      final out = await studio.apply(_bytes(_patternImage()), []);
      expect(out.isOk, isTrue);
      expect(out.result.width, 20);
      expect(out.result.height, 12);
      expect(out.result.appliedOps, isEmpty);
    });
  });

  group('البنية — صفر رفع وصفر شبكة والحتمية', () {
    test('حتمية كاملة: نفس المدخل والعمليات = بايتات متطابقة حرفياً',
        () async {
      final src = _bytes(_patternImage(), png: true);
      final studio = MediaStudio();
      final a = await studio.apply(src,
          [const MediaCrop(2, 2, 8, 8), const MediaRotate(180)],
          format: 'png');
      final b = await studio.apply(src,
          [const MediaCrop(2, 2, 8, 8), const MediaRotate(180)],
          format: 'png');
      expect(a.isOk && b.isOk, isTrue);
      expect(a.result.bytes.length, b.result.bytes.length);
      var identical = true;
      for (var i = 0; i < a.result.bytes.length; i++) {
        if (a.result.bytes[i] != b.result.bytes[i]) {
          identical = false;
          break;
        }
      }
      expect(identical, isTrue,
          reason: 'النواة حتمية — لا طوابع زمن ولا عشوائية في الإخراج');
    });

    test('صفر IO وصفر شبكة بنيةً: لا استيراد dart:io ولا شبكة في النواة',
        () async {
      // فحص بنائي مباشر: مصدر النواة لا يحتوي استيرادات IO أو شبكة إطلاقاً —
      // المحرك لا يستطيع الرفع مهما أراد مستدعيه (الاختبار يحق له قراءة الملف)
      final source = io.File('lib/wasl_mediastudio.dart').readAsStringSync();
      final imports = RegExp(r"^import\s+[^;]+;", multiLine: true)
          .allMatches(source)
          .map((m) => m.group(0)!)
          .toList();
      expect(imports.any((i) => i.contains('dart:io')), isFalse,
          reason: 'لا ملفات ولا شبكة — البايتات داخل وبايتات خارج');
      expect(imports.any((i) => i.contains('dart:http')), isFalse);
      expect(imports.any((i) => i.contains('socket')), isFalse);
      // والاستيرادات المحصورة بالمكتبات المتوقعة حصراً
      final allowed = ['dart:convert', 'dart:typed_data', 'package:image'];
      for (final imp in imports) {
        expect(
            allowed.any((a) => imp.contains(a)),
            isTrue,
            reason: 'استيراد غير متوقع في نواة نقية: $imp');
      }
    });
  });
}
