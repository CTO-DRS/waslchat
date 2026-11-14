/// معرض وسائط المحادثة (المرحلة 8 ب — 0.21.0)
///
/// يجمع رسائل الوسائط (صور/فيديو/ملفات/صوتيات) من رسائل المحادثة المفكوكة
/// محلياً ويصنفها للشبكة المعروضة، مع فلترة حسب النوع. كل شيء فوق بيانات
/// موجودة أصلاً على الجهاز — لا استعلام إضافي ولا إرسال.
///
/// المحذوفة تستبعد دائماً، وعرض-مرة-واحدة تستبعد أيضاً (لن تظهر وسط
/// تتكرر فتفتح بلا قصد — هذا سلوك قسوة لا فضل).
class MediaItem {
  const MediaItem({
    required this.messageId,
    required this.type,
    required this.mediaUrl,
    required this.createdAtIso,
    required this.mine,
    this.name,
    this.caption,
  });

  final String messageId;
  final String type; // image | video | file | voice
  final String mediaUrl;
  final String createdAtIso;
  final bool mine;
  final String? name;
  final String? caption;

  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isVoice => type == 'voice';
  bool get isFile => type == 'file';
}

class MediaGalleryService {
  MediaGalleryService._();

  /// تبويبات المعرض بأسمائها العربية
  static const List<String> tabs = ['الكل', 'صور', 'فيديو', 'ملفات', 'صوت'];

  /// يجمع وسائط المحادثة من رسائلها الخام.
  /// [textOf]: يعيد النص المفكوك لرسالة (نفس دالة الشاشة) — لقراءة ميتا
  /// الملف/الفيديو المشفرة ({name,size}) والتعليق النصي إن وجد.
  /// [myId]: معرّفي — لتمييز رسائلي في العرض.
  static List<MediaItem> collect(
    List<Map<String, dynamic>> msgs,
    String? Function(Map<String, dynamic> m) textOf, {
    required String myId,
  }) {
    final out = <MediaItem>[];
    for (final m in msgs) {
      if (m['deleted_at'] != null) continue;
      final t = m['type'] as String? ?? 'text';
      if (t != 'image' && t != 'video' && t != 'file' && t != 'voice') continue;
      if (m['view_once'] == true) continue;
      final url = m['media_url'] as String?;
      if (url == null || url.isEmpty) continue;
      String? captionOf(String? t, String type) {
        if (t == null || t.isEmpty) return null;
        if (t.startsWith('{')) return null; // ميتا ملف/فيديو
        if (RegExp(r'^v[123]\.').hasMatch(t)) return null; // ما زال مشفراً
        return type == 'image' ? t : null;
      }

      String? name;
      String? caption;
      final decoded = textOf(m);
      if (decoded != null && decoded.startsWith('{')) {
        try {
          name = RegExp(r'"name"\s*:\s*"([^"]*)"').firstMatch(decoded)?.group(1);
        } catch (_) {}
      } else {
        caption = captionOf(decoded, t);
      }
      out.add(MediaItem(
        messageId: m['id'] as String,
        type: t,
        mediaUrl: url,
        createdAtIso: m['created_at'] as String? ?? '',
        mine: m['sender_id'] == myId,
        name: name,
        caption: caption,
      ));
    }
    // الأحدث أولاً
    out.sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
    return out;
  }

  /// فلترة التبويب: 'الكل' يعيد كما هو، وإلا النوع المطابق حصراً
  static List<MediaItem> filter(List<MediaItem> items, String tab) {
    switch (tab) {
      case 'صور':
        return items.where((i) => i.isImage).toList();
      case 'فيديو':
        return items.where((i) => i.isVideo).toList();
      case 'ملفات':
        return items.where((i) => i.isFile || i.isVoice).toList();
      case 'صوت':
        return items.where((i) => i.isVoice).toList();
      default:
        return items;
    }
  }

  /// عدد عناصر كل تبويب (لعرضه على الشرائح)
  static Map<String, int> counts(List<MediaItem> items) {
    return {
      for (final t in tabs) t: filter(items, t).length,
    };
  }
}
