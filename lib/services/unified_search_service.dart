/// البحث الموحد فوق كل المحادثات (المرحلة 8 ب — 0.21.0)
///
/// نفس المحرك الذكي المستخدم داخل المحادثة (تطبيع عربي + تسامح أخطاء +
/// مرادفات) فوق «مستندات» تُجلب مشفرة كما هي من الخادم وتُفك **على جهازك**
/// ثم يُبحث فيها محلياً — لا يُرسل الاستعلام ولا أي حرف لأي مكان.
///
/// الترتيب: نقاط المحرك > حداثة الرسالة (دفع بسيط للرسائل الأحدث عند
/// تعادل النقاط)، وحد أقصى 3 نتائج لكل محادثة حتى لا تبتلع محادثة واحدة
/// القائمة كلها، والقائمة النهائية بحد 60 نتيجة.
import '../services/smart_search_service.dart';

class UnifiedDoc {
  const UnifiedDoc({
    required this.conversationId,
    required this.title,
    required this.messageId,
    required this.text,
    required this.createdAtIso,
    required this.senderName,
    required this.mine,
    required this.isGroup,
  });

  final String conversationId;
  final String title;
  final String messageId;
  final String text;
  final String createdAtIso;
  final String senderName;
  final bool mine;
  final bool isGroup;
}

class UnifiedHit {
  const UnifiedHit({required this.doc, required this.score});

  final UnifiedDoc doc;
  final double score;
}

class UnifiedSearchService {
  UnifiedSearchService._();

  /// رتب المستندات على الاستعلام — أعلى 3 لكل محادثة ثم أول [maxResults] عالمياً.
  /// استعلام فارغ أو بلا كلمات مفيدة يعيد قائمة فارغة.
  static List<UnifiedHit> rank(List<UnifiedDoc> docs, String query,
      {int perConversation = 3, int maxResults = 60}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final hits = <UnifiedHit>[];
    for (final d in docs) {
      final s = SmartSearchService.score(d.text, q);
      if (s > 0) {
        hits.add(UnifiedHit(doc: d, score: s));
      }
    }
    // أحدث أولاً عند التعادل، ثم النقاط
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.doc.createdAtIso.compareTo(a.doc.createdAtIso);
    });
    // حد لكل محادثة
    final counts = <String, int>{};
    final capped = <UnifiedHit>[];
    for (final h in hits) {
      final c = counts[h.doc.conversationId] ?? 0;
      if (c >= perConversation) continue;
      counts[h.doc.conversationId] = c + 1;
      capped.add(h);
      if (capped.length >= maxResults) break;
    }
    return capped;
  }

  /// تجميع النتائج حسب المحادثة (لعرضها بعناوين قسمية إن رغبت الواجهة)
  static Map<String, List<UnifiedHit>> groupByConversation(
      List<UnifiedHit> hits) {
    final m = <String, List<UnifiedHit>>{};
    for (final h in hits) {
      m.putIfAbsent(h.doc.conversationId, () => []).add(h);
    }
    return m;
  }

  /// نص إفصاح الشاشة (يُعرض أسفل نتائج البحث حرفياً)
  static const String disclosure =
      'البحث يجري على جهازك حصراً: الرسائل تُفك تشفيرها محلياً ولا يُرسل استعلامك لأي مكان';
}
