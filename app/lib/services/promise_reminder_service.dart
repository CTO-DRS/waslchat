/// التذكيرات الذكية من الرسائل (المرحلة 9 ب — 0.23.0)
///
/// يكشف الوعود والمواعيد في رسائلك الوارد المفكوكة على جهازك — «اتفقنا
/// الخميس 8»، «بكرة الساعة 10:30»، «نلتقي بعد غدا المغرب» — ويقترح تذكيراً
/// محلياً بنقرة واحدة. خدمة ثقافية عربية خالصة: ثقافة «اتفقنا الخميس».
///
/// الصدق التصميمي: كشف قواعدي بنماذج عربية موثقة — لا يفهم كل صيغ الوقت
/// ولا النوايا الضمنية، ويعرض الثقة مع كل كشف. التذكير المحلي يجري على
/// جهازك بإشعار النظام المحلي — لا خادم ولا ترحيل ولا شبكة جديدة، ولا
/// يُرسل أي حرف من رسائلك لأي مكان.
import 'local_ai_service.dart';

class DetectedPromise {
  const DetectedPromise({
    required this.messageId,
    required this.text,
    required this.confidence,
    this.dayWord,
    this.dayOffset,
    this.hour,
    this.minute,
    this.isEvening,
    this.rawMatch,
  });

  final String messageId;
  final String text;
  final double confidence;

  /// كلمة اليوم المكتشفة كما وردت (الخميس، بكرة، بعد غدا…).
  final String? dayWord;

  /// عدد الأيام من اليوم حتى الموعد (0 = اليوم، 1 = بكرة…) — null إن لم
  /// يُحدَّد اليوم (الساعة وحدها).
  final int? dayOffset;

  /// الساعة 0–23 والدقيقة 0–59 كما فُهمتا (بعد تحويل الفجر/الظهر/المساء…).
  final int? hour;
  final int? minute;

  /// المساء/الليل → صحيح، الصباح/الفجر/الظهر/العصر → خطأ.
  final bool? isEvening;

  /// المقطع المطابق كما ورد (لعرضه في الاقتراح).
  final String? rawMatch;

  /// وصف عربي مختصر للموعد كما فُهم — يُعرض في الاقتراح.
  String describe() {
    final parts = <String>[];
    if (dayWord != null) parts.add(dayWord!);
    if (hour != null) {
      final m = minute != null ? ':${minute.toString().padLeft(2, '0')}' : '';
      if (isEvening == true) {
        parts.add('الساعة ${hour! >= 13 ? hour! - 12 : hour}$m مساءً');
      } else if (isEvening == false && hour! <= 12) {
        parts.add('الساعة ${hour}$m صباحاً');
      } else {
        parts.add('الساعة ${hour}$m');
      }
    }
    return parts.isEmpty ? 'موعد محتمل' : parts.join(' ');
  }
}

class PromiseReminderService {
  PromiseReminderService._();

  /// أيام الأسبوع العربية (المفاتيح تُطبَّع عند البناء) → DateTime.weekday.
  static final Map<String, int> _weekdays = {
    for (final e in const <String, int>{
      'السبت': DateTime.saturday,
      'الأحد': DateTime.sunday,
      'الإثنين': DateTime.monday,
      'الاثنين': DateTime.monday,
      'الثلاثاء': DateTime.tuesday,
      'الأربعاء': DateTime.wednesday,
      'الخميس': DateTime.thursday,
      'الجمعة': DateTime.friday,
    }.entries)
      LocalAiService.normalize(e.key): e.value,
  };

  /// أفعال وعود وإشارات اتفاق — تُطبَّع عند البناء (فـ«سأرسل» تجد نصّها
  /// المطبَّع «سارسل» في أي رسالة)، ووجود أحدها شرط ثقة عليا.
  static final List<String> _promiseVerbs = const <String>[
    'اتفقنا', 'موعدنا', 'نلتقي', 'أراك', 'سأرسل', 'سأجي', 'سأمرر', 'أغادر',
    'لا تنسى', 'ع الساعة', 'عند الساعة', 'بمشيئة الله', 'إن شاء الله',
    'أسوي', 'أتمم', 'أخلص', 'أحضر', 'نجي',
  ].map(LocalAiService.normalize).toList();

  /// كلمات الأيام النسبية (تُطبَّع عند البناء) → إزاحة الأيام.
  static final Map<String, int> _relativeDays = {
    for (final e in const <String, int>{
      'اليوم': 0,
      'بعد غدا': 2,
      'بعد بكرة': 2,
      'بكرة': 1,
      'غداً': 1,
      'غدا': 1,
    }.entries)
      LocalAiService.normalize(e.key): e.value,
  };

  /// الفترات (تُطبَّع عند البناء) → (الساعة الافتراضية بلا رقم، إزاحة 12
  /// للساعة الصريحة ≤11، ليلٌ للعرض) — فـ«4 عصرا» = 16 و«8 مساء» = 20
  /// و«نلتقي المغرب» = 18 وحدها.
  static final Map<String, (int, bool, bool)> _periods = {
    for (final e in const <String, (int, bool, bool)>{
      'الفجر': (5, false, false),
      'فجرا': (5, false, false),
      'الصباح': (9, false, false),
      'صباحا': (9, false, false),
      'الظهر': (12, false, false),
      'ظهرا': (12, false, false),
      'العصر': (16, true, false),
      'عصرا': (16, true, false),
      'المغرب': (18, true, true),
      'مغربا': (18, true, true),
      'مساء': (20, true, true),
      'العشاء': (20, true, true),
      'الليل': (21, true, true),
      'ليلا': (21, true, true),
    }.entries)
      LocalAiService.normalize(e.key): e.value,
  };

  static final RegExp _hourRe =
      RegExp(r'الساع[ةه]\s*(\d{1,2})(?:[:٫.](\d{1,2}))?');
  static final RegExp _clockRe = RegExp(r'\b(\d{1,2})[:٫](\d{2})\b');
  static final RegExp _bareHourRe = RegExp(r'\b(\d{1,2})\s*(?:صباحا|مساءا|مساء|العصر|الظهر|المغرب|الفجر|العشاء|الليل)');

  /// مسح رسائل واردة (معرّف، نص مفكوك) — يعيد أعلى 3 كشفات فقط
  /// (بترتيب الثقة ثم ترتيب الوصول)، والمستبعدَين سلفاً يُحذفان.
  static List<DetectedPromise> scan(
    List<(String, String)> incoming,
    DateTime now, {
    Set<String> dismissed = const {},
    int max = 3,
  }) {
    final out = <(int, DetectedPromise)>[];
    for (final (i, (id, text)) in incoming.indexed) {
      if (dismissed.contains(id)) continue;
      final p = detect(id, text, now);
      if (p != null && p.confidence >= 0.5) out.add((i, p));
    }
    out.sort((a, b) {
      final byConf = b.$2.confidence.compareTo(a.$2.confidence);
      if (byConf != 0) return byConf;
      return a.$1.compareTo(b.$1); // ثبات ترتيب الوصول عند التعادل
    });
    return out.map((e) => e.$2).take(max).toList();
  }

  /// كشف موعد واحد في رسالة — null إن لم يوجد ما يستحق الاقتراح.
  static DetectedPromise? detect(String messageId, String text, DateTime now) {
    final n = LocalAiService.normalize(text);
    if (n.trim().isEmpty) return null;

    final hasVerb = _promiseVerbs.any(n.contains);
    if (!hasVerb) return null; // بلا فعل وعد/اتفاق لا نقترح شيئاً

    // اليوم: نسبة أو يوم أسبوع
    String? dayWord;
    int? dayOffset;
    for (final e in _relativeDays.entries) {
      if (n.contains(e.key)) {
        dayWord = e.key;
        dayOffset = e.value;
        break;
      }
    }
    if (dayWord == null) {
      for (final e in _weekdays.entries) {
        if (n.contains(e.key)) {
          dayWord = e.key;
          dayOffset = _daysUntil(e.value, now.weekday);
          break;
        }
      }
    }

    // الوقت: الساعة 8 / 10:30 / 8 مساء
    int? hour;
    int? minute;
    bool? evening;
    String? raw;
    final hm = _hourRe.firstMatch(n);
    final cm = _clockRe.firstMatch(n);
    final bm = _bareHourRe.firstMatch(n);
    Match? m = hm ?? bm ?? cm;
    if (hm != null) {
      hour = int.tryParse(hm.group(1)!);
      minute = hm.group(2) != null ? int.tryParse(hm.group(2)!) : null;
    } else if (cm != null) {
      hour = int.tryParse(cm.group(1)!);
      minute = int.tryParse(cm.group(2)!);
    } else if (bm != null) {
      hour = int.tryParse(bm.group(1)!);
    }
    if (m != null) raw = m.group(0);

    // الفترة: كلمة فترة صريحة — تعطي ليل العرض، إزاحة 12 للساعة الصريحة
    // الصغيرة (8 مساء = 20، 4 عصرا = 16)، والساعة الافتراضية بلا رقم
    // (نلتقي المغرب = 18)
    for (final e in _periods.entries) {
      if (n.contains(e.key)) {
        evening = e.value.$3;
        if (hour != null && hour < 12 && e.value.$2) {
          hour = hour + 12;
        } else if (hour == null) {
          hour = e.value.$1;
        }
        break;
      }
    }
    // التحقق النهائي للساعة: المستحيل يُسقط ولا يُخترع
    if (hour != null && (hour > 23 || (minute != null && minute > 59))) {
      hour = null;
      minute = null;
      raw = null;
    }

    // الثقة: فعل + يوم + وقت = أعلى، فعل + يوم = عالية، فعل + وقت = متوسطة
    double conf = 0;
    if (dayWord != null && hour != null) {
      conf = 0.9;
    } else if (dayWord != null) {
      conf = 0.7;
    } else if (hour != null) {
      conf = 0.6;
    }
    if (conf == 0) return null;

    return DetectedPromise(
      messageId: messageId,
      text: text,
      confidence: conf,
      dayWord: dayWord,
      dayOffset: dayOffset,
      hour: hour,
      minute: minute,
      isEvening: evening,
      rawMatch: raw ?? dayWord,
    );
  }

  /// أقرب يوم مستقبلي لنوع أسبوعي (اليوم نفسه يحسب 0 إن لم يمضِ الوقت —
  /// هنا نحسب اليوم إن كان المسافة 0 صحيحة للعرض).
  static int _daysUntil(int target, int current) {
    var d = target - current;
    if (d < 0) d += 7;
    return d;
  }

  /// التاريخ الميلادي التالي للموعد المكتشف — للتذكير المحلي.
  /// بلا يوم/ساعة يعيد null (لا نؤرخ ما لم يُفهم).
  static DateTime? resolveDate(DetectedPromise p, DateTime now) {
    if (p.dayOffset == null && p.hour == null) return null;
    final base = DateTime(now.year, now.month, now.day)
        .add(Duration(days: p.dayOffset ?? 0));
    if (p.hour == null) return base;
    return DateTime(base.year, base.month, base.day, p.hour!, p.minute ?? 0);
  }

  /// نص الإفصاح المعروض داخل بطاقة الاقتراح حرفياً.
  static const String disclosure =
      'الكشف يجري على جهازك حصراً من نص الرسالة المفكوك — والتذكير إشعار '
      'محلي على جهازك لا يمر بأي خادم، ولا يُرسل أي حرف من رسائلك لأي مكان';
}
