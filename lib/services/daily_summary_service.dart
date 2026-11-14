/// الملخص اليومي المحلي لكل محادثة (المرحلة 9 أ — 0.22.0)
///
/// يُبنى عند **أول فتح للمحادثة في اليوم** من الرسائل المفكوكة على جهازك،
/// ويُخزَّن محلياً في المخزن الآمن — فالزيارة التالية تقرأه فوراً بلا إعادة
/// حساب، ولا يغادر أي حرف الجهاز: صفر شبكة في البناء والقراءة والخزن.
///
/// البناء استخلاصي خالص: إحصاءات اليوم (الرسائل والوسائط وأكثر المتحدثين)
/// + المواضيع المتكررة (كلمات معنوية تكررت مرتين فأكثر) + أهم 3 أسطر
/// بمحرك الاستخلاص نفسه المستخدم في الملخص الفوري (LocalAiService).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hijri_service.dart';
import 'local_ai_service.dart';
import 'semantic_search_service.dart';

/// سطر مشاركة في محادثة اليوم يدخل بناء الملخص.
class DailyLine {
  const DailyLine({required this.who, required this.text, this.isMedia = false});

  final String who;
  final String text;
  final bool isMedia;
}

class DailySummaryService {
  DailySummaryService._();

  /// أسماء أيام الأسبوع بالعربي (DateTime.weekday: 1=الاثنين … 7=الأحد).
  static const _weekdays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  /// مفتاح اليوم القياسي «2026-11-14» — أساس شرط «أول فتح في اليوم».
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// المواضيع المتكررة: كلمات معنوية (تطبيع عربي، 4+ أحرف، بلا وظيفية)
  /// تكررت مرتين فأكثر عبر أسطر اليوم — أعلى 3 بالترتيب ثم بالألف.
  static List<String> topics(List<DailyLine> lines, {int max = 3}) {
    final counts = <String, int>{};
    for (final l in lines) {
      if (l.isMedia) continue;
      for (final t in SemanticSearchService.tokens(l.text)) {
        if (t.length >= 4) counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final words = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return words.take(max).map((e) => e.key).toList();
  }

  /// بناء ملخص اليوم — نص عربي جاهز للعرض من الرسائل المفكوكة حصراً.
  /// قائمة فارغة تعيد null (لا ملخص يوم بلا رسائل — ولا ادعاء).
  static String? build(List<DailyLine> lines, DateTime day) {
    final msgs = lines.where((l) => !l.isMedia && l.text.trim().isNotEmpty).toList();
    final media = lines.where((l) => l.isMedia).length;
    // يوم بلا رسائل نصية (وسائط فقط أو فراغ) لا يستحق ملخصاً — ولا ادعاء
    if (msgs.isEmpty) return null;

    final wd = _weekdays[day.weekday - 1];
    final header = 'ملخص $wd — ${HijriService.formatBoth(day)}';

    // أكثر المتحدثين (أسماء المرسلين كما فُكّت — المجموعات أساساً)
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
          .take(2)
          .map((e) => '${e.key} (${e.value})')
          .join('، ');
    }

    final stats = StringBuffer();
    stats.write('${msgs.length} رسالة');
    if (media > 0) stats.write(' · $media وسائط');
    if (topSpeakers.isNotEmpty) stats.write(' · أبرز المشاركين: $topSpeakers');

    final t = topics(lines);
    final parts = <String>[header, stats.toString()];
    if (t.isNotEmpty) parts.add('المواضيع المتكررة: ${t.join('، ')}');

    if (msgs.isNotEmpty) {
      final asLines = msgs.map((l) => '${l.who}: ${l.text}').toList();
      final bullets = LocalAiService.summarizeLines(asLines, maxLines: 3);
      parts.add(bullets);
    }
    return parts.join('\n');
  }
}

/// مخزن الملخص اليومي — المخزن الآمن على الجهاز حصراً (مفتاح لكل محادثة).
class DailySummaryStore {
  DailySummaryStore({FlutterSecureStorage? storage})
      : _secure = storage ?? const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _secure;
  static const _prefix = 'wasl_daily_sum_';

  /// يقرأ ملخص اليوم إن وُجد **لليوم نفسه** — ملخص الأمس لا يُعرض أبداً.
  Future<String?> load(String conversationId, DateTime now) async {
    try {
      final raw = await _secure.read(key: '$_prefix$conversationId');
      if (raw == null || raw.isEmpty) return null;
      final sep = raw.indexOf('\u001F');
      if (sep < 0) return null;
      if (raw.substring(0, sep) != DailySummaryService.dayKey(now)) return null;
      return raw.substring(sep + 1);
    } catch (_) {
      return null; // الفشل يهبط: تُبنى الملخصة من جديد إن أمكن
    }
  }

  /// يخزّن الملخص مع مفتاح يومه (يستبدل ملخص الأمس — مخزن لكل محادثة صف واحد).
  Future<void> save(String conversationId, String text, DateTime now) async {
    try {
      await _secure.write(
          key: '$_prefix$conversationId', value: '${DailySummaryService.dayKey(now)}\u001F$text');
    } catch (_) {
      // بلا تخزين: الملخص الفوري يعمل على أي حال
    }
  }

  /// حذف ملخص محادثة (حذف الحساب يمسح المخزن كاملاً أصلاً).
  Future<void> clear(String conversationId) async {
    try {
      await _secure.delete(key: '$_prefix$conversationId');
    } catch (_) {}
  }

  /// مسح كل ملخصات الأيام (صيانة دورية محلية).
  Future<void> clearAll() async {
    try {
      final all = await _secure.readAll();
      for (final k in all.keys) {
        if (k.startsWith(_prefix)) await _secure.delete(key: k);
      }
    } catch (_) {}
  }
}
