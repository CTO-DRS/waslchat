/// «اسأل وصل» — أرشيفك يجيبك محلياً (المرحلة 14 أ — 1.3.0)
///
/// طبقة استجابة فوق البحث الدلالي المتجهي القائم (0.22.0): سؤالك يُمثَّل
/// متجهة بتوسيع المرادفات نفسه، وتُقاس قربة كل رسالة مفكوكة على جهازك معه،
/// فتُنتقى أعلى المقاطع صلةً ويُبنى منها جواب استخلاصي يعلن مصدر كل سطر
/// (المحادثة والتاريخ) — **صفر حرف يغادر الجهاز**: لا الاستعلام ولا نصوصك.
///
/// الصدق التصميمي: هذا استخلاص من رسائلك لا توليد — إن لم توجد رسائل قريبة
/// بما يكفي (تحت العتبة المعلنة) يعيد null فتقول الواجهة «لا أجد ما يكفي»
/// بلا ادعاء معرفة، والسحابي الأعمق يبقى بديلاً اختيارياً بموافقة صريحة.
import 'dart:math' as math;

import 'hijri_service.dart';
import 'semantic_search_service.dart';

/// مقطع رسالة مفكوكة يدخل محرك الأسئلة (نفس شكل SemanticDoc لعدم التكرار).
class AskPassage {
  const AskPassage({
    required this.conversationId,
    required this.text,
    required this.createdAtIso,
  });

  final String conversationId;
  final String text;
  final String createdAtIso;
}

/// سطر إجابة مع مصدره ونقاط صلته.
class AskLine {
  const AskLine({
    required this.text,
    required this.conversationId,
    required this.atIso,
    required this.score,
  });

  final String text;
  final String conversationId;
  final String atIso;
  final double score;
}

/// إجابة كاملة: السؤال وأسطره المنتقاة بالصلة ثم مرتبة زمنياً للعرض.
class AskAnswer {
  const AskAnswer({required this.question, required this.lines});

  final String question;
  final List<AskLine> lines;
}

class AskWaslService {
  AskWaslService._();

  /// عتبة الصلة المعلنة: مقطع تحت 0.15 لا يدخل الإجابة — بلا ادعاء قربة زائفة
  /// (أعلى قليلاً من عتبة البحث الدلالي 0.12 لأن السؤال يطلب إجابة لا اقتراحاً).
  static const double minScore = 0.15;

  /// أقصى عدد أسطر في الإجابة — أقوى ثلاثة مقاطع صلةً.
  static const int maxLines = 3;

  /// بناء الإجابة من المقاطع المفكوكة على الجهاز — null إن لم يوجد ما يكفي.
  ///
  /// الانتقاء بنقاط تشابه جيب التمام (متجهة الاستعلام بتوسيع المرادفات نفسها)،
  /// مع **مواءمة المرادفات**: مفاتيح المتجهة القادمة بصيغة «الساعه» تُضاف
  /// بصيغتها المجردة «ساعه» بوزنها نفسه — لأن تمثيل المقاطع يحذف «ال»
  /// التعريف من الكلمات الطويلة، فبلا المواءمة تفقد المرادفات وصولها إلى
  /// مقاطع تحمل الكلمة المجردة. والتكرار الحرفي يُقصى، والعرض زمني تصاعدي
  /// بعد الانتقاء بالصلة كي يُقرأ السياق كما جرى فعلاً.
  static AskAnswer? answer(
    List<AskPassage> passages,
    String question, {
    int maxLines = AskWaslService.maxLines,
    double minScore = AskWaslService.minScore,
  }) {
    final q = question.trim();
    if (q.isEmpty) return null;
    final raw = SemanticSearchService.queryVector(q);
    if (raw.isEmpty) return null;
    // مواءمة المرادفات مع مفاتيح المقاطع (بلا «ال») ثم إعادة التطبيع
    final aligned = Map<String, double>.of(raw);
    raw.forEach((k, w) {
      if (k.length >= 5 && k.startsWith('ال')) {
        final bare = k.substring(2);
        if (bare.length >= 3) aligned[bare] = (aligned[bare] ?? 0) + w;
      }
    });
    var qnorm = 0.0;
    for (final w in aligned.values) {
      qnorm += w * w;
    }
    qnorm = math.sqrt(qnorm);
    if (qnorm == 0) return null;
    final qv = aligned.map((k, w) => MapEntry(k, w / qnorm));

    final picked = <AskLine>[];
    final seen = <String>{};
    for (final p in passages) {
      final text = p.text.trim();
      if (text.isEmpty || seen.contains(text)) continue;
      final v = SemanticSearchService.vector(text);
      final s = SemanticSearchService.cosine(qv, v);
      if (s < minScore) continue;
      seen.add(text);
      picked.add(AskLine(
          text: text,
          conversationId: p.conversationId,
          atIso: p.createdAtIso,
          score: s));
    }
    if (picked.isEmpty) return null;
    picked.sort((a, b) => b.score.compareTo(a.score));
    final top = picked.take(maxLines.clamp(1, 5)).toList()
      ..sort((a, b) => a.atIso.compareTo(b.atIso));
    return AskAnswer(question: q, lines: top);
  }

  /// نص الإجابة الجاهز للعرض: كل سطر بمصدره (اسم المحادثة والتاريخ الهجري
  /// والميلادي معاً). [nameOf] يحوّل معرف المحادثة إلى اسمها المعروض.
  static String format(AskAnswer a,
      {String Function(String conversationId)? nameOf}) {
    final buf = StringBuffer('بناءً على أرشيفك (على جهازك حصراً):');
    for (final l in a.lines) {
      final who = nameOf?.call(l.conversationId) ?? 'محادثة';
      final when = DateTime.tryParse(l.atIso) == null
          ? ''
          : HijriService.formatBoth(DateTime.parse(l.atIso).toLocal());
      buf.write('\n• «${_short(l.text)}» — $who${when.isEmpty ? '' : '، $when'}');
    }
    return buf.toString();
  }

  static String _short(String t) =>
      t.length > 120 ? '${t.substring(0, 120)}…' : t;

  /// نص الإفصاح المعلن في الواجهة (يُعرض حرفياً).
  static const String disclosure =
      'اسأل وصل يجيب من رسائلك المفكوكة على جهازك حصراً: استخلاص من رسائلك لا '
      'توليد — ولا يغادر أي حرف (سؤالك ورسائلك) لأي مكان';
}
