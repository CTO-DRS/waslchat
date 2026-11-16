/// بحث الوسائط الصادق (المرحلة 14 ب — 1.4.0): بحث داخل ميتاداتا الوسائط
/// التي نملكها محلياً حصراً — النوع والحجم والتاريخ والاسم من ميتا الملف
/// والتعليق النصي للصورة — **بلا ادعاء رؤية محتوى الصورة إطلاقاً**: ما
/// يظهر داخل الصورة لا يُعرف ولا يُبحث، وهذا الصدق مكتوب في الواجهة.
///
/// المحرك نقي فوق `MediaItem` من معرض 0.21.0 (collect) — صفر شبكة وصفر
/// طرف ثالث، والمطابقة النصية بمحرك التطبيع العربي القائم (تشكيل وهمزات
/// لا تكسر المطابقة). المصادر متعددة البنية (عنوان المحادثة + وسائطها)
/// فالنتيجة تحمل «المحادثة المصدر» دائماً — والاستخدام الحالي داخل معرض
/// محادثة واحدة بعرض مصدرها.
import 'local_ai_service.dart';
import 'media_gallery_service.dart';

/// استعلام البحث — كل الحقول اختيارية وتُجمع بـ«و».
class MediaSearchQuery {
  const MediaSearchQuery({
    this.text,
    this.types = const {},
    this.from,
    this.to,
    this.minSizeBytes,
    this.maxSizeBytes,
  });

  /// نص يُطابق الاسم (ميتا الملف/الفيديو) والتعليق (الصورة) بعد التطبيع.
  final String? text;

  /// أنواع مسموحة (image/video/file/voice) — الفارغة تعني الكل.
  final Set<String> types;

  /// نطاق التاريخ (على تاريخ إنشاء الوسيط كما يعود من الخادم).
  final DateTime? from;
  final DateTime? to;

  /// نطاق الحجم بالبايت (معروف للملفات والفيديو من ميتاها حصراً —
  /// الصور والصوتيات بلا حجم موثق فتُستبعد من فلاتر الحجم بصدق).
  final int? minSizeBytes;
  final int? maxSizeBytes;

  /// هل الاستعلام فارغ كلياً (لا فلترة — يعيد كل شيء).
  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) &&
      types.isEmpty &&
      from == null &&
      to == null &&
      minSizeBytes == null &&
      maxSizeBytes == null;
}

/// نتيجة واحدة — تحمل عنوان المحادثة المصدر حصراً فوق الوسيط.
class MediaSearchHit {
  const MediaSearchHit({required this.sourceTitle, required this.item});

  final String sourceTitle;
  final MediaItem item;

  /// الحجم بالكيلوبايت للعرض — null حين لا نعرف الحجم (صدق لا تخمين).
  double? get sizeKb =>
      item.sizeBytes == null ? null : item.sizeBytes! / 1024.0;
}

class MediaSearchService {
  MediaSearchService._();

  /// البحث: فلترة بكل الشروط المطلوبة «و» بينها، بترتيب المصدر الأصلي
  /// (الأحدث أولاً كما يجمعه collect) — لا ترتيب جديد ولا ادعاء صلة.
  static List<MediaSearchHit> search({
    required List<(String, List<MediaItem>)> sources,
    required MediaSearchQuery query,
  }) {
    final raw = query.text?.trim() ?? '';
    final nq = raw.isEmpty ? null : LocalAiService.normalize(raw);
    final out = <MediaSearchHit>[];
    for (final (title, items) in sources) {
      for (final it in items) {
        // النوع
        if (query.types.isNotEmpty && !query.types.contains(it.type)) continue;
        // التاريخ
        final dt = DateTime.tryParse(it.createdAtIso);
        if (query.from != null && (dt == null || dt.isBefore(query.from!))) {
          continue;
        }
        if (query.to != null && (dt == null || dt.isAfter(query.to!))) continue;
        // الحجم — بلا حجم موثق يعني لا يمر فلتر حجم (بصدق)
        final size = it.sizeBytes;
        if (query.minSizeBytes != null &&
            (size == null || size < query.minSizeBytes!)) {
          continue;
        }
        if (query.maxSizeBytes != null &&
            (size == null || size > query.maxSizeBytes!)) {
          continue;
        }
        // النص — في الاسم والتعليق حصراً (ميتاداتا نملكها) بعد التطبيع
        if (nq != null) {
          final hay =
              LocalAiService.normalize('${it.name ?? ''} ${it.caption ?? ''}');
          if (!hay.contains(nq)) continue;
        }
        out.add(MediaSearchHit(sourceTitle: title, item: it));
      }
    }
    return out;
  }
}
