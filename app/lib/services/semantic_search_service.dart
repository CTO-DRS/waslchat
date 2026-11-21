/// البحث الدلالي المتجهي المحلي (المرحلة 9 أ — 0.22.0)
///
/// يمثّل كل رسالة مفكوكة على جهازك **متجهة كيس كلمات معايرة** (وزن كل كلمة
/// بتكرارها المتدرج ثم تطبيع L2) ومتجهة الاستعلام بتوسيع مرادفات المحرك الذكي،
/// ثم يقيس **تشابه جيب التمام (cosine)** بين الاستعلام ومتجهة كل محادثة
/// (مجموع متجهات رسائلها معايراً) — فيظهر «المحادثات ذات الصلة» حتى من دون
/// مطابقة معجمية حرفية: بحث «موعد الاجتماع» يجد «متى اللقاء؟».
///
/// الصدق التصميمي: هذا تمثيل إحصائي خفيف وليس شبكة عصبية ولا تدويناً —
/// يفهم القرب المعجمي والمرادفات المعروفة فقط. كل الحساب يجري على الجهاز
/// حصراً: لا يُرسل الاستعلام ولا أي حرف من رسائلك لأي مكان.
import 'dart:math' as math;

import 'smart_search_service.dart';

/// مستند رسالة مفكوكة يدخل محرك الدلالة (نفس شكل UnifiedDoc لعدم التكرار).
class SemanticDoc {
  const SemanticDoc({
    required this.conversationId,
    required this.text,
    required this.createdAtIso,
  });

  final String conversationId;
  final String text;
  final String createdAtIso;
}

/// محادثة ذات صلة: معرّفها ونقاط التشابه وأفضل رسالة فيها (للمعاينة).
class SemanticHit {
  const SemanticHit({
    required this.conversationId,
    required this.score,
    required this.bestText,
    required this.bestAtIso,
  });

  final String conversationId;
  final double score;
  final String bestText;
  final String bestAtIso;
}

class SemanticSearchService {
  SemanticSearchService._();

  /// كلمات وظيفية تُهمَل في المتجهات (بنصها المطبَّع — فـ«على» هنا «علي»).
  static const _stopwords = <String>{
    'في', 'من', 'على', 'الى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'التي', 'الذي',
    'الذين', 'و', 'او', 'ثم', 'لكن', 'ان', 'انا', 'انت', 'هو', 'هي', 'نحن',
    'هم', 'كان', 'كانت', 'يكون', 'قد', 'لقد', 'ما', 'لا', 'لم', 'لن', 'كل',
    'بعض', 'غير', 'حتى', 'اذا', 'كما', 'بين', 'عند', 'عندما', 'الان', 'فقط',
    'جدا', 'ايضا', 'لي', 'لك', 'له', 'لها', 'به', 'بها', 'هل', 'اي', 'يا',
    'علي', 'شوي', 'بالنسبه', 'يعني', 'هيك', 'كده',
    'the', 'is', 'a', 'an', 'and', 'or', 'to', 'of', 'in', 'on', 'at', 'for',
    'it', 'i', 'you', 'we', 'they',
  };

  /// كلمات المتجهة: تطبيع عربي، حذف «ال» التعريف من الكلمات الطويلة
  /// (فـ«الاجتماع» و«اجتماع» متجهة واحدة — أساس القرب الدلالي العربي)،
  /// طول 3+، بلا كلمات وظيفية.
  static List<String> tokens(String text) {
    return SmartSearchService.normalize(text)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .map((w) => w.length >= 5 && w.startsWith('ال') ? w.substring(2) : w)
        .where((w) => w.length >= 3 && !_stopwords.contains(w))
        .toList();
  }

  /// متجهة كيس كلمات معايرة: وزن الكلمة 1 + ln(التكرار) — التكرار الخام
  /// يطغى على الرسائل القصيرة، والتدرج اللوغاريتمي يعطي الكلمات المتكررة
  /// أفضلية معتدلة — ثم تطبيع L2 حتى تكون كل المتجهات على المقياس نفسه.
  static Map<String, double> vector(String text) {
    final counts = <String, int>{};
    for (final w in tokens(text)) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    if (counts.isEmpty) return const {};
    final v = <String, double>{};
    for (final e in counts.entries) {
      v[e.key] = 1.0 + math.log(e.value);
    }
    var norm = 0.0;
    for (final w in v.values) {
      norm += w * w;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return const {};
    return v.map((k, w) => MapEntry(k, w / norm));
  }

  /// تشابه جيب التمام بين متجهتين — 0 إن إحداهما فارغة.
  static double cosine(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final (small, big) = a.length <= b.length ? (a, b) : (b, a);
    var dot = 0.0;
    for (final e in small.entries) {
      final other = big[e.key];
      if (other != null) dot += e.value * other;
    }
    return dot; // المتجهات معايرة L2 فالضرب النقطي هو الجيب تمام
  }

  /// متجهة الاستعلام بتوسيع المرادفات: كلمات الاستعلام (بنفس معالجة الرموز:
  /// تطبيع وحذف «ال» التعريف) تُوسَّع بمرادفاتها المعروفة بوزن أخف (0.6) —
  /// فـ«ميعاد» تصل إلى «اجتماع» و«الاجتماع» على السواء.
  static Map<String, double> queryVector(String query) {
    final v = <String, double>{};
    void add(String w, double weight) {
      if (w.length < 3 || _stopwords.contains(w)) return;
      v[w] = (v[w] ?? 0) + weight;
    }

    for (final w in tokens(query)) {
      add(w, 1.0);
      for (final syn in SmartSearchService.expansionsFor(w)) {
        add(syn, 0.6);
      }
    }
    if (v.isEmpty) return const {};
    var norm = 0.0;
    for (final w in v.values) {
      norm += w * w;
    }
    norm = math.sqrt(norm);
    return v.map((k, w) => MapEntry(k, w / norm));
  }

  /// ترتيب المحادثات ذات الصلة بالاستعلام — متجهة المحادثة هي مجموع متجهات
  /// رسائلها (يُعاد تطبيع L2 عند القياس)، وأفضل رسالة فيها هي أعلى تشابه
  /// فردي للمعاينة. عتبة [minScore] تمنع ظهور محادثات بلا قربة حقيقية،
  /// والتعادل يُحسم بأحدث رسالة.
  static List<SemanticHit> rankConversations(
    List<SemanticDoc> docs,
    String query, {
    int top = 4,
    double minScore = 0.12,
  }) {
    final q = queryVector(query);
    if (q.isEmpty) return const [];
    final sums = <String, Map<String, double>>{};
    final best = <String, SemanticDoc>{};
    final bestScore = <String, double>{};
    for (final d in docs) {
      final v = vector(d.text);
      if (v.isEmpty) continue;
      final acc = sums.putIfAbsent(d.conversationId, () => {});
      for (final e in v.entries) {
        acc[e.key] = (acc[e.key] ?? 0) + e.value;
      }
      final s = cosine(q, v);
      final prev = bestScore[d.conversationId] ?? -1;
      if (s > prev) {
        bestScore[d.conversationId] = s;
        best[d.conversationId] = d;
      }
    }
    final hits = <SemanticHit>[];
    for (final cid in sums.keys) {
      final conv = sums[cid]!;
      var norm = 0.0;
      for (final w in conv.values) {
        norm += w * w;
      }
      norm = math.sqrt(norm);
      if (norm == 0) continue;
      var dot = 0.0;
      for (final e in q.entries) {
        final w = conv[e.key];
        if (w != null) dot += e.value * w;
      }
      final score = dot / norm;
      if (score < minScore) continue;
      final b = best[cid]!;
      hits.add(SemanticHit(
        conversationId: cid,
        score: score,
        bestText: b.text,
        bestAtIso: b.createdAtIso,
      ));
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.bestAtIso.compareTo(a.bestAtIso);
    });
    return hits.take(top).toList();
  }

  /// نص إفصاح قسم الدلالة في واجهة البحث (يُعرض حرفياً).
  static const String disclosure =
      'الصلة الدلالية تحسب على جهازك حصراً: تطابق بالمعنى القريب والمرادفات — '
      'بلا شبكة ولا نموذج خارجي، ولا يغادر أي حرف من رسائلك';
}
