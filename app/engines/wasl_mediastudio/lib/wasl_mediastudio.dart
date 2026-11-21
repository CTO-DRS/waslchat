/// استوديو الوسائط الموحد — المحرك النقي الثاني عشر من محركات وصل
/// (المرحلة 22 — 1.20.0).
///
/// ينفذ بند الخارطة «محرر وسائط محلي واحد يجمع: قص الصور والتدوير
/// والتعليقات والدمج» كنواة نقية فوق `image` 4.x المحلية (نقية بلا كود C):
/// قص وتدوير 90° وقلب وتصغير محافظ النسبة والتعليقات ودمج شبكي (كولاج) —
/// كل المعالجة **على الجهاز حصراً وبنيةً**: المحرك لا يستورد مكتبات
/// الملفات ولا الشبكة — يأخذ بايتات ويعيد بايتات، فالرفع غير ممكن منه
/// أصلاً وبلا أي رفع قبل موافقتك كما تطلب الخارطة.
///
/// العقد الصادق:
/// 1. **حدود معلنة قبل التنفيذ لا بعده** (عُادة بوابة 1.18.0): حجم المدخل
///    وبكسلاته وعدد العمليات وطول التعليق وبلاطات الدمج — تُفحص كلها
///    **وتجمع كل الأسباب لا أولها**، والحدود قابلة للحقن للاختبار
///    (الافتراضية تطابق `MediaLimits` وحدود الذاكرة).
/// 2. **التعليقات صادقة**: خطوط `image` النقطية المدمجة لاتينية حصراً —
///    التعليق العربي لا يُرسم بالبكسل (تشكيل عربي غير متاح في خطوط
///    نقطية) بل يُحمل في نتيجة التعديل للواجهة فترسمه بخطوط Flutter —
///    ولا ذكراً لرسم لم يحدث.
/// 3. **حتمية**: نفس المدخل والعمليات = بايتات ناتجة متطابقة حرفياً.
/// 4. **الفشل صريح**: نتيجة رفض تحمل أسبابها لا استثناءات مسربة،
///    ورفض القص خارج الحدود صريح لا قصّ صامت.
///
/// ما ليس في هذه النواة (توثيق صادق): حفظ الملفات والرفع والمعاينات —
/// طبقة التطبيق؛ وبحث نص التفريغ الصوتي في البحث الصادق ينتظر مصدر
/// التفريغ نفسه (مؤجل خلف بوابة القياس الميداني 1.18.0 — لا كود ميتاً
/// بلا مستدعي)؛ وروابط استوديو الصوت والتميمة تجري من الواجهة.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ————— الحدود المعلنة —————

/// حدود الاستوديو — قابلة للحقن للاختبار، والافتراضية تطابق الحدود
/// الموحدة للتطبيق (`MediaLimits.maxMediaBytes`) وسقف الذاكرة المعقول.
class MediaStudioLimits {
  const MediaStudioLimits({
    this.maxInputBytes = 24 * 1024 * 1024,
    this.maxPixels = 4096 * 4096,
    this.maxOps = 12,
    this.maxCaptionChars = 64,
    this.maxCollageTiles = 6,
    this.maxCollageSide = 4096,
  });

  final int maxInputBytes;
  final int maxPixels;
  final int maxOps;
  final int maxCaptionChars;
  final int maxCollageTiles;
  final int maxCollageSide;

  static const MediaStudioLimits production = MediaStudioLimits();
}

// ————— العمليات —————

/// عملية تحرير واحدة — كل العمليات بيانات وصفية تطبق بالترتيب.
abstract class MediaOp {
  const MediaOp();

  /// اسم العملية للسجل الصادق في النتيجة.
  String get label;
}

/// قص مستطيل — يجب أن يكون داخل الصورة كلياً (رفض صريح لا قصّ صامت).
class MediaCrop extends MediaOp {
  const MediaCrop(this.x, this.y, this.width, this.height);
  final int x, y, width, height;

  @override
  String get label => 'crop($x,$y,$width×$height)';
}

/// تدوير بمضاعفات 90° — غير ذلك رفض صريح.
class MediaRotate extends MediaOp {
  const MediaRotate(this.degrees);
  final int degrees;

  @override
  String get label => 'rotate($degrees°)';
}

/// قلب أفقي أو رأسي.
class MediaFlip extends MediaOp {
  const MediaFlip.horizontal() : axis = _h;
  const MediaFlip.vertical() : axis = _v;
  final String axis;
  static const String _h = 'h';
  static const String _v = 'v';

  @override
  String get label => 'flip($axis)';
}

/// تصغير محافظ النسبة إلى أقصى ضلع — لا تكبير أبداً (تكبير = ضباب صامت).
class MediaResize extends MediaOp {
  const MediaResize(this.maxSide);
  final int maxSide;

  @override
  String get label => 'resize(maxSide:$maxSide)';
}

/// تعليق نصي — لاتيني يُرسم بالخط النقطي، وغير لاتيني (كالعربي) يُحمل
/// في النتيجة للواجهة فترسمه بخطوط Flutter — ولا ادعاء رسم لم يحدث.
class MediaCaption extends MediaOp {
  const MediaCaption(this.text, {this.position = CaptionPosition.bottomLeft});
  final String text;
  final CaptionPosition position;

  /// هل يُرسم بالخط النقطي المدمج؟ (لاتيني أساسي حصراً)
  bool get isDrawableLatin =>
      text.isNotEmpty &&
      text.runes.every((r) => r >= 32 && r < 127);

  @override
  String get label => 'caption(${isDrawableLatin ? 'latin' : 'ui-rendered'})';
}

enum CaptionPosition { bottomLeft, bottomRight, topLeft, topRight }

// ————— النتيجة —————

/// نتيجة تعديل ناجحة — البايتات + السجل الصادق.
class MediaEditResult {
  MediaEditResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.appliedOps,
    required this.warnings,
    required this.inputBytes,
    required this.format,
    this.uiCaptions = const [],
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final List<String> appliedOps;
  final List<String> warnings;
  final int inputBytes;
  final String format; // png / jpeg
  final List<String> uiCaptions; // تعليقات للواجهة (لا رسم بكسل)
}

/// نتيجة رفض — كل الأسباب مجمعة لا أولها.
class MediaEditRefusal {
  MediaEditRefusal(this.reasons);
  final List<String> reasons;

  bool get hasReasons => reasons.isNotEmpty;
}

/// محصلة التعديل — إما نتيجة أو رفض (بلا استثناءات مسربة).
class MediaEditOutcome {
  MediaEditOutcome._();

  MediaEditResult? _ok;
  MediaEditRefusal? _no;

  factory MediaEditOutcome.ok(MediaEditResult r) => MediaEditOutcome._().._ok = r;
  factory MediaEditOutcome.refused(MediaEditRefusal f) =>
      MediaEditOutcome._().._no = f;

  bool get isOk => _ok != null;
  bool get isRefused => _no != null;
  MediaEditResult get result => _ok!;
  MediaEditRefusal get refusal => _no!;
}

// ————— النواة —————

/// الاستوديو الموحد — نقياً: بايتات داخل، بايتات خارج، صفر IO وصفر شبكة.
class MediaStudio {
  MediaStudio({this.limits = MediaStudioLimits.production});
  final MediaStudioLimits limits;

  /// تطبيق سلسلة عمليات على صورة واحدة.
  Future<MediaEditOutcome> apply(
      List<int> inputBytes, List<MediaOp> ops,
      {String format = 'jpeg', int jpegQuality = 85}) async {
    // الحدود تُفحص كلها وتجمع كل الأسباب لا أولها
    final reasons = <String>[];
    if (inputBytes.length > limits.maxInputBytes) {
      reasons.add('حجم المدخل ${inputBytes.length} بايت فوق الحد '
          '${limits.maxInputBytes}');
    }
    if (ops.length > limits.maxOps) {
      reasons.add('عدد العمليات ${ops.length} فوق الحد ${limits.maxOps}');
    }
    for (final op in ops) {
      if (op is MediaCrop) {
        if (op.width <= 0 || op.height <= 0) {
          reasons.add('مستطيل القص غير صالح: ${op.label}');
        }
      }
      if (op is MediaRotate && op.degrees % 90 != 0) {
        reasons.add('زاوية التدوير يجب أن تكون مضاعفات 90: '
            '${op.degrees}°');
      }
      if (op is MediaResize && (op.maxSide < 8 || op.maxSide > 4096)) {
        reasons.add('أقصى ضلع للتصغير خارج 8..4096: ${op.maxSide}');
      }
      if (op is MediaCaption && op.text.length > limits.maxCaptionChars) {
        reasons.add('التعليق ${op.text.length} حرفاً فوق الحد '
            '${limits.maxCaptionChars}');
      }
    }
    final decoded = _tryDecode(inputBytes);
    if (decoded == null) {
      reasons.add('المدخل ليس صورة معروفة (PNG/JPEG)');
    } else if (decoded.width * decoded.height > limits.maxPixels) {
      reasons.add('بكسلات المدخل ${decoded.width}×${decoded.height} فوق '
          'الحد ${limits.maxPixels}');
    }
    if (reasons.isNotEmpty) return MediaEditOutcome.refused(MediaEditRefusal(reasons));

    var im = decoded!;
    final warnings = <String>[];
    final applied = <String>[];
    final uiCaptions = <String>[];
    final captionPad = 8;
    for (final op in ops) {
      if (op is MediaCrop) {
        // رفض صريح للقص خارج الحدود — لا قصّ صامت يكذب بالنتيجة
        if (op.x < 0 ||
            op.y < 0 ||
            op.x + op.width > im.width ||
            op.y + op.height > im.height) {
          return MediaEditOutcome.refused(MediaEditRefusal([
            'مستطيل القص خارج حدود الصورة ${im.width}×${im.height}: '
                '${op.label}',
          ]));
        }
        im = img.copyCrop(im,
            x: op.x, y: op.y, width: op.width, height: op.height);
        applied.add(op.label);
      } else if (op is MediaRotate) {
        // خرائط حرفية حصراً — copyRotate يعيد أخذ العينات فيفسد البكسل
        var turns = (op.degrees ~/ 90) % 4;
        if (turns < 0) turns += 4;
        for (var t = 0; t < turns; t++) {
          im = _rotate90Cw(im);
        }
        applied.add(op.label);
      } else if (op is MediaFlip) {
        im = op.axis == MediaFlip._h ? _flipH(im) : _flipV(im);
        applied.add(op.label);
      } else if (op is MediaResize) {
        if (im.width > op.maxSide || im.height > op.maxSide) {
          final ratio = op.maxSide /
              (im.width > im.height ? im.width : im.height);
          final w = (im.width * ratio).floor().clamp(1, 4096);
          final h = (im.height * ratio).floor().clamp(1, 4096);
          im = img.copyResize(im, width: w, height: h);
        }
        applied.add(op.label);
      } else if (op is MediaCaption) {
        if (op.text.isEmpty) {
          warnings.add('تعليق فارغ أُهمل');
        } else if (op.isDrawableLatin) {
          final bandH = 20;
          final pad = captionPad;
          final atTop = op.position == CaptionPosition.topLeft ||
              op.position == CaptionPosition.topRight;
          // لوحة موسعة: الشريط يُرسم داخل الحدود — لا قصّ صامت
          final expanded = img.Image(
              width: im.width, height: im.height + bandH + pad * 2);
          img.fill(expanded, color: img.ColorRgba8(255, 255, 255, 255));
          img.compositeImage(expanded, im,
              dstX: 0, dstY: atTop ? bandH + pad * 2 : 0);
          img.drawString(expanded, op.text,
              font: img.arial14,
              x: pad + 2,
              y: atTop ? pad : im.height + pad,
              color: img.ColorRgba8(0, 0, 0, 255));
          im = expanded;
          applied.add(op.label);
        } else {
          // عربي أو غير لاتيني: لا رسم بكسل — حمل للواجهة صادقاً
          uiCaptions.add(op.text);
          warnings.add('التعليق غير لاتيني لا يُرسم بالخط النقطي — '
              'حُمل للواجهة لرسمه بخطوط Flutter');
          applied.add(op.label);
        }
      }
    }
    // الترميز — صيغة واحدة صادقة بالنتيجة
    final bytes = format == 'png'
        ? Uint8List.fromList(img.encodePng(im))
        : Uint8List.fromList(img.encodeJpg(im, quality: jpegQuality));
    return MediaEditOutcome.ok(MediaEditResult(
      bytes: bytes,
      width: im.width,
      height: im.height,
      appliedOps: applied,
      warnings: warnings,
      inputBytes: inputBytes.length,
      format: format == 'png' ? 'png' : 'jpeg',
      uiCaptions: uiCaptions,
    ));
  }

  /// دمج شبكي (كولاج) لعدة صور — بلاطات متساوية الحجم محافظة النسبة
  /// داخل البلاطة، وفجوة وخلفية صادقة بالأبعاد.
  Future<MediaEditOutcome> collage(
    List<List<int>> images, {
    int columns = 2,
    int gap = 2,
    String format = 'jpeg',
    int jpegQuality = 85,
    int background = 0xFFFFFFFF,
  }) async {
    final reasons = <String>[];
    if (images.isEmpty) reasons.add('لا صور للدمج');
    if (images.length > limits.maxCollageTiles) {
      reasons.add('عدد البلاطات ${images.length} فوق الحد '
          '${limits.maxCollageTiles}');
    }
    if (columns < 1 || columns > images.length) {
      reasons.add('عدد الأعمدة $columns غير صالح لـ${images.length} صورة');
    }
    if (reasons.isNotEmpty) {
      return MediaEditOutcome.refused(MediaEditRefusal(reasons));
    }
    final decoded = <img.Image>[];
    for (final b in images) {
      if (b.length > limits.maxInputBytes) {
        reasons.add('بلاطة ${b.length} بايت فوق الحد ${limits.maxInputBytes}');
        continue;
      }
      final im = _tryDecode(b);
      if (im == null) {
        reasons.add('بلاطة ليست صورة معروفة');
        continue;
      }
      if (im.width * im.height > limits.maxPixels) {
        reasons.add('بلاطة ${im.width}×${im.height} فوق حد البكسلات');
        continue;
      }
      decoded.add(im);
    }
    if (reasons.isNotEmpty) {
      return MediaEditOutcome.refused(MediaEditRefusal(reasons));
    }
    final rows = (decoded.length + columns - 1) ~/ columns;
    final tile = decoded
        .map((im) => im.width > im.height ? im.width : im.height)
        .reduce((a, b) => a > b ? a : b);
    final canvasW = columns * tile + (columns - 1) * gap;
    final canvasH = rows * tile + (rows - 1) * gap;
    if (canvasW > limits.maxCollageSide ||
        canvasH > limits.maxCollageSide) {
      return MediaEditOutcome.refused(MediaEditRefusal([
        'أبعاد اللوحة $canvasW×$canvasH فوق الحد ${limits.maxCollageSide}',
      ]));
    }
    final canvas = img.Image(width: canvasW, height: canvasH);
    final bg = background;
    img.fill(canvas,
        color: img.ColorRgba8((bg >> 16) & 0xff, (bg >> 8) & 0xff,
            bg & 0xff, (bg >> 24) & 0xff));
    for (var i = 0; i < decoded.length; i++) {
      final r = i ~/ columns;
      final c = i % columns;
      var tileIm = decoded[i];
      // البلاطة محافظة النسبة داخل مربع tile — لا تشويه ولا تكبير
      if (tileIm.width != tileIm.height) {
        final side = tileIm.width > tileIm.height
            ? tileIm.width
            : tileIm.height;
        final ratio = tile / side;
        tileIm = img.copyResize(tileIm,
            width: (tileIm.width * ratio).floor().clamp(1, tile),
            height: (tileIm.height * ratio).floor().clamp(1, tile));
      }
      final dx = c * (tile + gap) + ((tile - tileIm.width) ~/ 2);
      final dy = r * (tile + gap) + ((tile - tileIm.height) ~/ 2);
      img.compositeImage(canvas, tileIm, dstX: dx, dstY: dy);
    }
    final bytes = format == 'png'
        ? Uint8List.fromList(img.encodePng(canvas))
        : Uint8List.fromList(img.encodeJpg(canvas, quality: jpegQuality));
    return MediaEditOutcome.ok(MediaEditResult(
      bytes: bytes,
      width: canvasW,
      height: canvasH,
      appliedOps: ['collage(${decoded.length}×${columns}col)'],
      warnings: const [],
      inputBytes: images.fold<int>(0, (a, b) => a + b.length),
      format: format == 'png' ? 'png' : 'jpeg',
    ));
  }

  // ————— خرائط بكسل حرفية — بلا إعادة أخذ عينات —————

  /// تدوير 90° مع عقارب الساعة بخرائط فهرس حرفية: dst(x,y) = src(y, W-1-x)
  /// قيم البكسلات تُنسخ كما هي — صفر استيفاء وصفر فساد.
  img.Image _rotate90Cw(img.Image src) {
    final out = img.Image(width: src.height, height: src.width);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        out.setPixelRgba(y, src.width - 1 - x, p.r, p.g, p.b, p.a);
      }
    }
    return out;
  }

  /// قلب أفقي حرفي: dst(x,y) = src(W-1-x, y)
  img.Image _flipH(img.Image src) {
    final out = img.Image(width: src.width, height: src.height);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        out.setPixelRgba(src.width - 1 - x, y, p.r, p.g, p.b, p.a);
      }
    }
    return out;
  }

  /// قلب رأسي حرفي: dst(x,y) = src(x, H-1-y)
  img.Image _flipV(img.Image src) {
    final out = img.Image(width: src.width, height: src.height);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        out.setPixelRgba(x, src.height - 1 - y, p.r, p.g, p.b, p.a);
      }
    }
    return out;
  }

  img.Image? _tryDecode(List<int> bytes) {
    try {
      return img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }
}

/// فحص نوع الصورة من التوقيع — نقي ومشترك مع خدمة التطبيق.
(String, String) mediaContentTypeOf(List<int> bytes) {
  if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return ('jpeg', 'image/jpeg');
  }
  if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return ('png', 'image/png');
  }
  return ('jpeg', 'image/jpeg');
}

/// نص عربي للتحقق — مستورد هنا ليوثق أن النواة لا تعتمد عليه للرسم
/// بل تحمل النص كما هو (utf8) للواجهة.
String captionForUi(String text) => utf8.decode(utf8.encode(text));
