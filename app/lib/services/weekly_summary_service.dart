/// الملخص الأسبوعي المحلي لكل محادثة (المرحلة 14 أ — 1.3.0)
///
/// بنمط الملخص اليومي المُختبَر نفسه (0.22.0) بنافذة أسبوع متدحرجة — آخر
/// 7 أيام — لكل محادثة (خاصة ومجموعة وقناة وغرف المجتمعات): يُبنى من الرسائل
/// المفكوكة على جهازك ويُخزَّن في المخزن الآمن محلياً، ولا يغادر أي حرف
/// الجهاز: صفر شبكة في البناء والقراءة والخزن.
///
/// البناء استخلاصي خالص: إحصاءات الأسبوع (الرسائل والوسائط وأيام النشاط
/// وأبرز المتحدثين) + المواضيع المتكررة (كلمات معنوية تكررت 3 مرات فأكثر
/// عبر الأسبوع — عتبة أعلى من اليومية لأن النافذة أوسع) + أهم 5 أسطر بمحرك
/// الاستخلاص نفسه المستخدم في الملخص اليومي (LocalAiService).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'daily_summary_service.dart';
import 'hijri_service.dart';
import 'local_ai_service.dart';
import 'semantic_search_service.dart';

/// سطر مشاركة خلال الأسبوع يدخل بناء الملخص (مع وقتها لحساب أيام النشاط).
class WeeklyLine {
  const WeeklyLine({
    required this.who,
    required this.text,
    required this.createdAt,
    this.isMedia = false,
  });

  final String who;
  final String text;
  final DateTime createdAt;
  final bool isMedia;
}

class WeeklySummaryService {
  WeeklySummaryService._();

  /// عرض النافذة المتدحرجة: 7 أيام حتى اللحظة [end] — (end-7d … end].
  static const int windowDays = 7;

  /// نافذة الأسبوع من الأسطر — يحصر الأسطر داخل (end-7 أيام … end] حصراً.
  static List<WeeklyLine> window(List<WeeklyLine> lines, DateTime end,
      {int days = windowDays}) {
    final start = end.subtract(Duration(days: days));
    return lines
        .where((l) => l.createdAt.isAfter(start) && !l.createdAt.isAfter(end))
        .toList();
  }

  /// المواضيع المتكررة عبر الأسبوع: كلمات معنوية (تطبيع عربي، 4+ أحرف، بلا
  /// وظيفية) تكررت 3 مرات فأكثر — أعلى 5 بالترتيب ثم بالألف.
  static List<String> topics(List<WeeklyLine> lines, {int max = 5}) {
    final counts = <String, int>{};
    for (final l in lines) {
      if (l.isMedia) continue;
      for (final t in SemanticSearchService.tokens(l.text)) {
        if (t.length >= 4) counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final words = counts.entries.where((e) => e.value >= 3).toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return words.take(max).map((e) => e.key).toList();
  }

  /// بناء ملخص الأسبوع — نص عربي جاهز للعرض من الرسائل المفكوكة حصراً.
  /// قائمة بلا رسائل نصية داخل النافذة تعيد null (لا ملخص أسبوع فارغ — ولا ادعاء).
  static String? build(List<WeeklyLine> lines, DateTime end) {
    final week = window(lines, end);
    final msgs = week
        .where((l) => !l.isMedia && l.text.trim().isNotEmpty)
        .toList();
    final media = week.where((l) => l.isMedia).length;
    if (msgs.isEmpty) return null;

    final start = end.subtract(const Duration(days: windowDays));
    final header =
        'ملخص الأسبوع — من ${HijriService.formatBoth(start)} إلى ${HijriService.formatBoth(end)}';

    // أيام النشاط: أيام مختلفة شهدت رسائل نصية داخل النافذة (عدّ صادق).
    final days = <String>{};
    for (final l in msgs) {
      days.add(DailySummaryService.dayKey(l.createdAt));
    }

    // أبرز المتحدثين (أسماء المرسلين كما فُكّت) — الثلاثة الأعلى.
    final byWho = <String, int>{};
    for (final l in msgs) {
      final w = l.who.trim();
      if (w.isNotEmpty) byWho[w] = (byWho[w] ?? 0) + 1;
    }
    String topSpeakers = '';
    if (byWho.length >= 2) {
      final top = byWho.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topSpeakers = top
          .take(3)
          .map((e) => '${e.key} (${e.value})')
          .join('، ');
    }

    final stats = StringBuffer();
    stats.write('${msgs.length} رسالة');
    if (media > 0) stats.write(' · $media وسائط');
    stats.write(' · نشاط في ${days.length} يوم');
    if (topSpeakers.isNotEmpty) {
      stats.write(' · أبرز المشاركين: $topSpeakers');
    }

    final t = topics(week);
    final parts = <String>[header, stats.toString()];
    if (t.isNotEmpty) parts.add('المواضيع المتكررة: ${t.join('، ')}');

    final asLines = msgs.map((l) => '${l.who}: ${l.text}').toList();
    parts.add(LocalAiService.summarizeLines(asLines, maxLines: 5));
    return parts.join('\n');
  }
}

/// مخزن الملخص الأسبوعي — المخزن الآمن على الجهاز حصراً (مفتاح لكل محادثة).
class WeeklySummaryStore {
  WeeklySummaryStore({FlutterSecureStorage? storage})
      : _secure = storage ?? const FlutterSecureStorage(
            aOptions: AndroidOptions());

  final FlutterSecureStorage _secure;
  static const _prefix = 'wasl_weekly_sum_';

  /// يقرأ ملخص الأسبوع إن وُجد **ليوم اليوم نفسه** — ملخص مبني قبل اليوم
  /// لا يُعرض (نافذته أقدم) ويُعاد بناؤه.
  Future<String?> load(String conversationId, DateTime now) async {
    try {
      final raw = await _secure.read(key: '$_prefix$conversationId');
      if (raw == null || raw.isEmpty) return null;
      final sep = raw.indexOf('\u001F');
      if (sep < 0) return null;
      if (raw.substring(0, sep) != DailySummaryService.dayKey(now)) return null;
      return raw.substring(sep + 1);
    } catch (_) {
      return null; // الفشل يهبط: يُبنى الملخص من جديد إن أمكن
    }
  }

  /// يخزّن الملخص مع مفتاح يوم بنائه (يستبدل الأقدم — صف واحد لكل محادثة).
  Future<void> save(String conversationId, String text, DateTime now) async {
    try {
      await _secure.write(
          key: '$_prefix$conversationId',
          value: '${DailySummaryService.dayKey(now)}\u001F$text');
    } catch (_) {
      // بلا تخزين: البناء الفوري يعمل على أي حال
    }
  }

  /// حذف ملخص محادثة (حذف الحساب يمسح المخزن كاملاً أصلاً).
  Future<void> clear(String conversationId) async {
    try {
      await _secure.delete(key: '$_prefix$conversationId');
    } catch (_) {}
  }

  /// مسح كل ملخصات الأسابيع (صيانة دورية محلية).
  Future<void> clearAll() async {
    try {
      final all = await _secure.readAll();
      for (final k in all.keys) {
        if (k.startsWith(_prefix)) await _secure.delete(key: k);
      }
    } catch (_) {}
  }
}
