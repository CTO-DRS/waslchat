/// التقييم البحثي لنموذج لغة صغير على الجهاز (المرحلة 9 ب — 0.23.0)
///
/// هذا بند «تقييم بحثي» كما وثّقه GRAND_PLAN: يقرأ قدرة الجهاز محلياً
/// (/proc/meminfo على أندرويد ولينكس — بلا أي إذن ولا حزمة جديدة)، ويقارنه
/// بكَتالوج نماذج صغيرة مفتوحة (أوزان Q4 كمّية)، ويحدد المرشح المناسب
/// ومعايير القرار المكتوبة — بينما **ربط محرك الاستدلال فعلياً** (llama.cpp
/// عبر FFI أو حزمة أصلية مماثلة) قرار مؤجل بالأداء المقاس على جهاز متوسط،
/// موثق بالكامل في `docs/ON_DEVICE_LLM.md`.
///
/// الصدق التصميمي: لا يُنزَّل أي شيء تلقائياً ولا يُفرض على أحد — هذه
/// مرحلة قياس وقرار، والتنزيل حين يأتي سيكون صريحاً بالحجم وبموافقة نقر.
import 'dart:io';

/// نموذج مرشّح في الكَتالوج البحثي.
class OnDeviceModelSpec {
  const OnDeviceModelSpec({
    required this.id,
    required this.label,
    required this.sizeMb,
    required this.ramNeedMb,
    required this.notes,
  });

  final String id;
  final String label;
  final int sizeMb;
  final int ramNeedMb;
  final String notes;
}

class OnDeviceModelVerdict {
  const OnDeviceModelVerdict({
    required this.level,
    required this.title,
    required this.detail,
    this.recommended,
  });

  /// 'no-info' | 'too-weak' | 'eligible'
  final String level;
  final String title;
  final String detail;
  final OnDeviceModelSpec? recommended;
}

class OnDeviceModelService {
  OnDeviceModelService._();

  /// كَتالوج المرشحين — نماذج صغيرة مفتوحة بأوزان Q4 تقريبية:
  /// (المقاسات قيم تصميمية للتقييم لا وعود تنزيل)
  static const catalog = <OnDeviceModelSpec>[
    OnDeviceModelSpec(
      id: 'mini-0.5b-q4',
      label: 'نموذج صغير 0.5B — كمي Q4',
      sizeMb: 400,
      ramNeedMb: 2600,
      notes: 'أخف المرشحين: ردود قصيرة عربية مقبولة على أجهزة اقتصادية',
    ),
    OnDeviceModelSpec(
      id: 'small-1.5b-q4',
      label: 'نموذج متوسط 1.5B — كمي Q4',
      sizeMb: 1000,
      ramNeedMb: 4200,
      notes: 'توازن جودة/حجم — المرشح الأقرب لجهاز أندرويد متوسط اليوم',
    ),
    OnDeviceModelSpec(
      id: 'mid-3b-q4',
      label: 'نموذج أعمق 3B — كمي Q4',
      sizeMb: 1900,
      ramNeedMb: 6500,
      notes: 'جودة أعلى بثمن ذاكرة أعلى — للأجهزة القوية حصراً',
    ),
  ];

  /// معايير القرار المكتوبة (تُعرض في الواجهة كما هي):
  /// أول رمز خلال ثانيتين، و20 رمزة/ثانية على جهاز متوسط (4GB رام)،
  /// وهامش ذاكرة 1.5GB للنظام والتطبيق قبل أي مرشح.
  static const criteria = <String>[
    'أول رمز مولَّد خلال ثانيتين من الطلب — أقل من ذلك فالميزة تضر بالتجربة',
    '20 رمزة/ثانية على جهاز متوسط (ذاكرة 4 ج.ب) — الحد الأدنى للطلاقة',
    'هامش 1.5 ج.ب ذاكرة للنظام والتطبيق قبل احتساب أي نموذج',
    'تنزيل صريح يقبل الحجم قبل بدئه — ولا فرض على أحد إطلاقاً',
  ];

  /// قراءة الذاكرة الكلية من نص /proc/meminfo — «MemTotal:  7973264 kB».
  /// يعيد null على أي نص غير مفهوم أو منصة بلا ملف (الويب).
  static int? parseMemTotalMb(String meminfoRaw) {
    final m = RegExp(r'MemTotal:\s*(\d+)\s*kB').firstMatch(meminfoRaw);
    if (m == null) return null;
    final kb = int.tryParse(m.group(1)!);
    if (kb == null || kb <= 0) return null;
    return kb ~/ 1024;
  }

  /// قراءة الذاكرة فعلياً على المنصات التي تملك الملف — الفشل يعيد null
  /// بلا أي استثناء (الويب وسطح المكتب غير اللينكس يدخلان هنا).
  static int? readTotalRamMb() {
    try {
      if (!Platform.isAndroid && !Platform.isLinux && !Platform.isFuchsia) {
        return null;
      }
      final raw = File('/proc/meminfo').readAsStringSync();
      return parseMemTotalMb(raw);
    } catch (_) {
      return null;
    }
  }

  /// الحكم البحثي: هل يمر هذا الجهاز على أي مرشح، وأيهما؟
  /// القاعدة: حاجة النموذج من الرام ≤ الرام − 1.5 ج.ب هامشاً للنظام.
  static OnDeviceModelVerdict verdict({int? ramMb}) {
    if (ramMb == null) {
      return const OnDeviceModelVerdict(
        level: 'no-info',
        title: 'تعذّرت قراءة الذاكرة على هذا الجهاز',
        detail:
            'التقييم البحثي يحتاج قراءة /proc/meminfo (أندرويد/لينكس). '
            'المعايير والكتالوج معروضان أدناه — والقرار يوثق في ON_DEVICE_LLM.md',
      );
    }
    final budget = ramMb - 1500;
    final eligible = catalog
        .where((m) => m.ramNeedMb <= budget)
        .toList()
      ..sort((a, b) => b.ramNeedMb.compareTo(a.ramNeedMb));
    if (eligible.isEmpty) {
      return OnDeviceModelVerdict(
        level: 'too-weak',
        title: 'الذاكرة (${ramMb} م.ب) لا تكفي لأي مرشح من الكَتالوج',
        detail:
            'أخف المرشحين يحتاج ${catalog.first.ramNeedMb} م.ب مع هامش '
            '${1500} م.ب للنظام — لا فرض ولا تنزيل على هذا الجهاز',
      );
    }
    final rec = eligible.first;
    return OnDeviceModelVerdict(
      level: 'eligible',
      title: 'المرشح المقترح للتقييم: ${rec.label}',
      detail:
          'ذاكرتك ${ramMb} م.ب تسمح به ضمن الهامش — والقياس الفعلي (أول رمز '
          'وسرعة التوليد) على جهاز حقيقي هو قرار الربط الموثق في ON_DEVICE_LLM.md',
      recommended: rec,
    );
  }

  /// نص الإفصاح المعروض في بلاطة الإعدادات حرفياً.
  static const String disclosure =
      'تقييم بحثي بلا تنزيل تلقائي ولا فرض على أحد — لا يُربط محرك الاستدلال '
      'إلا بقرار أداء موثق على جهاز متوسط، وكل القراءة تجري على جهازك';
}
