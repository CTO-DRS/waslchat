/// محرك بوابة القياس الميداني — المحرك النقي العاشر من محركات وصل
/// (المرحلة 20 — 1.18.0).
///
/// الشرط البنيوي الحرفي من GRAND_PLAN_3: «بوابة لكل بند: قياس ميداني
/// (بطارية، حرارة، رموز/ثانية) قبل النشر، والنتائج معروضة صادقاً — والبند
/// الذي لا يجتاز يُعلن مؤجلاً في الشفافية لا يُشحَن ناقصاً».
///
/// العقد الصادق: العتبات **تُعلن قبل القياس لا بعده** (FeatureThresholds
/// معلنة ثابتة)، وكل عتبة تفشل تنتج سبباً صريحاً قابلاً للعرض، والحكم
/// إما `pass` أو `deferred` — لا حالة وسيطة ولا «شبه جاهز». وسجل الحكم
/// (GateLedger) يمنع قلب قرار «مؤجل» إلى منشور: الشحن يُسأل عن الحكم
/// الأخير وحده، والحكم الجديد لا يُعلن إلا بقياس جديد كامل. والتقرير نص
/// جاهز للشفافية بأرقامه كما قيس — بلا تجميل.
library;

/// قياس ميداني واحد لبند واحد — تنتجه طبقة الجهاز عند القياس الفعلي
/// (كل الحقول كما قاست الأداة، بلا تقريب يخدم القرار).
class FieldMeasurement {
  const FieldMeasurement({
    required this.feature,
    required this.tokensPerSec,
    required this.ttftMs,
    required this.batteryPctDrainPerMin,
    required this.thermalThrottled,
    required this.deviceRamMb,
    this.notes = const <String, String>{},
  });

  /// معرف البند (llm_suggestions / whisper_transcribe / neural_translate /
  /// moderation_ondevice)
  final String feature;

  /// إنتاجية الاستدلال: رموز/ثانية كما قاست (للبنود غير اللغوية = 0 والعتبة
  /// تعامل بالمعنى: عتبة 0 فقط تعبر صفراً)
  final int tokensPerSec;

  /// زمن أول رمز بالميلي ثانية (للبنود غير اللغوية يُقاس زمن أول نتيجة
  /// بنفس الحقل — الاسم موحد والوحدة موحدة)
  final int ttftMs;

  /// استنزاف البطارية نسبة مئوية/دقيقة أثناء القياس
  final double batteryPctDrainPerMin;

  /// هل تعثر الأداء بالحرارة أثناء القياس؟ (أي تعثر = سبب مؤجلة صريح)
  final bool thermalThrottled;

  /// ذاكرة الجهاز الحية بالميجابايت
  final int deviceRamMb;

  /// ملاحظات موثقة إضافية (نموذج، ترقيع، إصدار محرك...) تظهر في التقرير كما هي
  final Map<String, String> notes;
}

/// عتبات اعتماد بند — **تُعلن قبل القياس**: الأرقام الافتراضية هي أرقام
/// الخارطة نفسها (أول رمز ≤ 2ث، ≥ 20 رمز/ث على 4GB) ولا تُعدَّل بعد القياس.
class FeatureThresholds {
  const FeatureThresholds({
    required this.feature,
    required this.minTokensPerSec,
    required this.maxTtftMs,
    required this.maxBatteryDrainPerMin,
    required this.minDeviceRamMb,
    this.allowThermalThrottle = false,
  });

  final String feature;
  final int minTokensPerSec;
  final int maxTtftMs;
  final double maxBatteryDrainPerMin;
  final int minDeviceRamMb;
  final bool allowThermalThrottle;

  /// عتبات الخارطة الافتراضية لأي بند ذكاء محلي
  static FeatureThresholds defaults(String feature) => FeatureThresholds(
        feature: feature,
        minTokensPerSec: 20,
        maxTtftMs: 2000,
        maxBatteryDrainPerMin: 1.0,
        minDeviceRamMb: 4096,
      );

  /// مشتق بشيء واحد يتغير — العتبات الرقمية تبقى ثابتة كما أُعلنت
  FeatureThresholds copyWith({bool? allowThermalThrottle}) =>
      FeatureThresholds(
        feature: feature,
        minTokensPerSec: minTokensPerSec,
        maxTtftMs: maxTtftMs,
        maxBatteryDrainPerMin: maxBatteryDrainPerMin,
        minDeviceRamMb: minDeviceRamMb,
        allowThermalThrottle: allowThermalThrottle ?? this.allowThermalThrottle,
      );
}

/// حكم البند: يجتاز أو مؤجل — لا شيء بينهما.
enum GateVerdict { pass, deferred }

/// نتيجة الحكم الكاملة بأسبابها الصريحة القابلة للعرض.
class GateResult {
  const GateResult({
    required this.feature,
    required this.verdict,
    required this.reasons,
    required this.measurement,
  });

  final String feature;
  final GateVerdict verdict;
  final List<String> reasons;
  final FieldMeasurement measurement;

  /// الشحن مسموح لما يجتاز حصراً — «لا يُشحَن ناقصاً» حرفياً
  bool get shippable => verdict == GateVerdict.pass;
}

/// بوابة القياس الميداني — الحكم الصارم بأسباب كل عتبة فشلت.
class FieldGate {
  FieldGate._();

  /// الحكم: كل عتبة فاشلة تضيف سبباً؛ أسباب متعددة تُجمع كلها لا أولها —
  /// فالمطور يرى الصورة الكاملة ولا يصلح سبباً فيكتشف آخر بعد النشر.
  static GateResult judge(FieldMeasurement m, FeatureThresholds t) {
    if (m.feature != t.feature) {
      throw ArgumentError('العتبات لبند آخر: ${t.feature} وليس ${m.feature}');
    }
    final reasons = <String>[];
    if (m.tokensPerSec < t.minTokensPerSec) {
      reasons.add(
          'الإنتاجية ${m.tokensPerSec} رمز/ثانية تحت العتبة المعلنة ${t.minTokensPerSec}');
    }
    if (m.ttftMs > t.maxTtftMs) {
      reasons.add(
          'زمن أول رمز ${m.ttftMs} م.ث فوق السقف المعلن ${t.maxTtftMs} م.ث');
    }
    if (m.batteryPctDrainPerMin > t.maxBatteryDrainPerMin) {
      reasons.add(
          'استنزاف البطارية ${m.batteryPctDrainPerMin}%/دقيقة فوق السقف المعلن ${t.maxBatteryDrainPerMin}%/دقيقة');
    }
    if (m.thermalThrottled && !t.allowThermalThrottle) {
      reasons.add('تعثر حراري أثناء القياس والبند لا يسمح بالتعثر الحراري');
    }
    if (m.deviceRamMb < t.minDeviceRamMb) {
      reasons.add(
          'الذاكرة الحية ${m.deviceRamMb} م.ب تحت الحد المعلن ${t.minDeviceRamMb} م.ب');
    }
    return GateResult(
      feature: m.feature,
      verdict:
          reasons.isEmpty ? GateVerdict.pass : GateVerdict.deferred,
      reasons: reasons,
      measurement: m,
    );
  }
}

/// سجل الحكم المؤسسي: يمنع قلب «مؤجل» إلى منشور. الشحن يسأل السجل عن
/// الحكم الأخير وحده — والحكم الجديد لا يعلن إلا بقياس جديد كامل.
class GateLedger {
  final Map<String, GateResult> _latest = <String, GateResult>{};

  /// إعلان حكم بقياس كامل — يحل محل الحكم السابق للبند نفسه
  void declare(GateResult result) => _latest[result.feature] = result;

  /// آخر حكم معلن للبند (null = لم يقاس أصلاً)
  GateResult? latest(String feature) => _latest[feature];

  /// هل يجوز شحن البند الآن؟ لم يقاس = لا يجوز (لا شحن بلا قياس أصلاً)
  bool canShip(String feature) => _latest[feature]?.shippable ?? false;

  /// بنود مؤجلة حالياً — قائمة الشفافية
  List<String> get deferredFeatures => _latest.entries
      .where((e) => !e.value.shippable)
      .map((e) => e.key)
      .toList();
}

/// تقرير الشفافية — نص جاهز للنشر في TRANSPARENCY.md بأرقام القياس كما هي.
class TransparencyReport {
  TransparencyReport._();

  static String render(
    List<GateResult> results, {
    required String measuredAtIso,
    required String deviceSummary,
  }) {
    final sb = StringBuffer();
    sb.writeln('## قياس ميداني للبنود المحلية — $measuredAtIso');
    sb.writeln();
    sb.writeln('الجهاز: $deviceSummary');
    sb.writeln();
    if (results.isEmpty) {
      sb.writeln('لا بنود مقيسة بعد — كل بنود الذكاء المحلي معلنة مؤجلة.');
      return sb.toString();
    }
    for (final r in results) {
      final m = r.measurement;
      sb.writeln('- **${r.feature}**: ${r.verdict == GateVerdict.pass ? 'يجتاز ✅' : 'مؤجل ⏸'}'
          ' — ${m.tokensPerSec} رمز/ث، أول رمز ${m.ttftMs} م.ث،'
          ' بطارية ${m.batteryPctDrainPerMin}%/د،'
          ' ${m.thermalThrottled ? 'تعثر حراري نعم' : 'بلا تعثر حراري'}،'
          ' ذاكرة ${m.deviceRamMb} م.ب');
      for (final note in m.notes.entries) {
        sb.writeln('  - $note: ${m.notes[note.key]}');
      }
      for (final reason in r.reasons) {
        sb.writeln('  - سبب التأجيل: $reason');
      }
    }
    return sb.toString();
  }
}
