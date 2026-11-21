/// خانة النموذج المحلي للصياغة — ربط التطبيق لبنود 1.18.0 «ردود مقترحة
/// بأسلوب المستخدم» حسب GRAND_PLAN_3، مع جوهر بوابة القياس الميداني
/// (نسخة التطبيق من engines/wasl_fieldgate وفق عادة المحركات).
///
/// العقد الصادق: محرك الصياغة الإحصائي الموجود (style_assist_service منذ
/// الإصدارات الأولى) يبقى السلوك اليومي كما هو، والنموذج المحلي خانة تُحقن
/// — لكن اقتراحاته **لا تُعرض إلا لبند اجتاز قياسه الميداني** (سجل البوابة
/// `llm_suggestions` حكمه الأخير يجتاز): بند لم يقاس أو مؤجل يعيد الصياغة
/// الإحصائية مع إعلان الحالة صادقاً — «لا يُشحَن ناقصاً» حرفياً. والتوليد
/// على الجهاز حصراً: الحزمة نصوص محلية والمولد يُحقن من طبقة المحرك — لا
/// يغادر أي حرف.
library;

import 'style_assist_service.dart';

// ————— جوهر بوابة القياس الميداني (نسخة التطبيق من engines/wasl_fieldgate) —————

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

  final String feature;
  final int tokensPerSec;
  final int ttftMs;
  final double batteryPctDrainPerMin;
  final bool thermalThrottled;
  final int deviceRamMb;
  final Map<String, String> notes;
}

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

  static FeatureThresholds defaults(String feature) => FeatureThresholds(
        feature: feature,
        minTokensPerSec: 20,
        maxTtftMs: 2000,
        maxBatteryDrainPerMin: 1.0,
        minDeviceRamMb: 4096,
      );
}

enum GateVerdict { pass, deferred }

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

  bool get shippable => verdict == GateVerdict.pass;
}

class FieldGate {
  FieldGate._();

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
      verdict: reasons.isEmpty ? GateVerdict.pass : GateVerdict.deferred,
      reasons: reasons,
      measurement: m,
    );
  }
}

/// سجل الحكم المشترك — طبقة المحرك تعلن فيه نتائج قياساتها الفعلية
/// والواجهة تسأله قبل عرض أي اقتراح مولد محلياً
class GateLedger {
  final Map<String, GateResult> _latest = <String, GateResult>{};

  void declare(GateResult result) => _latest[result.feature] = result;

  GateResult? latest(String feature) => _latest[feature];

  bool canShip(String feature) => _latest[feature]?.shippable ?? false;

  /// للاختبارات حصراً: تفريغ السجل — الإنتاج يعلن بالقياس الكامل لا بالمسح
  void resetForTests() => _latest.clear();

  List<String> get deferredFeatures => _latest.entries
      .where((e) => !e.value.shippable)
      .map((e) => e.key)
      .toList();
}

// ————— خانة النموذج المحلي للصياغة —————

/// حزمة التغذية التي يقرؤها النموذج المحلي: الأسلوب المقاس من رسائلك +
/// سياق المحادثة الأخير + ما تريد قوله — بميزانية أحرف صارمة.
class StyleBrief {
  StyleBrief({
    required this.hint,
    required StyleProfile profile,
    List<String> recentContext = const <String>[],
    int maxChars = 800,
  })  : formality = profile.formality,
        avgWords = profile.avgWords,
        emojiRate = profile.emojiRate,
        topOpeners = List<String>.from(profile.topOpeners.take(3)),
        topClosers = List<String>.from(profile.topClosers.take(3)),
        sampleCount = profile.sampleCount {
    // السياق: أحدث الرسائل أولاً، وتُقص عند سقف الأحرف من الأقدم
    var used = hint.length + 60;
    for (final line in recentContext.reversed) {
      final cost = line.length + 1;
      if (used + cost > maxChars) break;
      used += cost;
      context.add(line);
    }
    // نعيد الترتيب زمنياً (الأقدم أولاً) كي يُقرأ كما جرى فعلاً
    final ordered = context.reversed.toList();
    context
      ..clear()
      ..addAll(ordered);
  }

  final String hint;
  final double formality;
  final double avgWords;
  final double emojiRate;
  final List<String> topOpeners;
  final List<String> topClosers;
  final int sampleCount;
  final List<String> context = <String>[];

  /// وصف الأسلوب نصاً موحداً لأي مولد — أرقام كما قاست لا تجميل
  String render() {
    final sb = StringBuffer();
    sb.writeln('أسلوب المستخدم: الرسمية ${(formality * 100).round()}%،'
        ' متوسط الكلمات ${avgWords.toStringAsFixed(1)}،'
        ' نسبة الإيموجي ${(emojiRate * 100).round()}%'
        '${sampleCount > 0 ? ' (من $sampleCount رسالة)' : ' (بلا بيانات كافية)'}');
    if (topOpeners.isNotEmpty) sb.writeln('افتتاحياته المعتادة: ${topOpeners.join('، ')}');
    if (topClosers.isNotEmpty) sb.writeln('ختاماته المعتادة: ${topClosers.join('، ')}');
    if (context.isNotEmpty) sb.writeln('سياق المحادثة الأخير:\n${context.join('\n')}');
    sb.writeln('المطلوب: 3 صيغ مقترحة لما يريد قوله بأسلوبه، كل صيغة بسطر:');
    sb.writeln('ما يريد قوله: $hint');
    return sb.toString();
  }
}

/// واجهة المولد المحلي للأسلوب — خانة النموذج (تملأ عند ربط محرك الاستدلال
/// بعد اجتياز قياسه الميداني). إعادة null = غير جاهز أو رافض: فلا يُدّعى توليد.
abstract class LocalStyleGenerator {
  Future<List<String>?> suggest(StyleBrief brief);
}

/// حالة الاقتراح الصادقة: إحصائي كما هو، أو مؤجل بالبوابة، أو مولد محلياً.
enum StyleSuggestState { statistical, gateDeferred, generated }

/// نتيجة الاقتراح مع الإعلان الصادق الذي تعرضه الواجهة كما هو.
class StyleSuggestResult {
  const StyleSuggestResult({
    required this.state,
    required this.drafts,
    required this.disclosure,
  });

  final StyleSuggestState state;
  final List<StyleDraft> drafts;
  final String disclosure;
}

class StyleSuggestService {
  StyleSuggestService._();

  /// معرف البند في بوابة القياس الميداني — عتباته عتبات الخارطة نفسها
  static const String feature = 'llm_suggestions';

  /// أقصى عدد اقتراحات — ثلاثة كما في الخارطة
  static const int maxSuggestions = 3;

  /// السجل المشترك: تعلن طبقة المحرك فيه نتائج القياس الفعلية بعد ربطها
  static final GateLedger ledger = GateLedger();

  /// الاقتراح الكامل — البوابة تقرر قبل الحماس:
  /// لا مولد، أو بند لم يقاس، أو بند مؤجل → الصياغة الإحصائية القائمة كما هي
  /// مع إعلان الحالة صادقاً؛ المولد المسموح فقط يمر عبر تحقق الصياغات.
  static Future<StyleSuggestResult> suggest(
    String hint, {
    StyleProfile? profile,
    List<String> recentContext = const <String>[],
    LocalStyleGenerator? generator,
  }) async {
    final stat = () => StyleSuggestResult(
          state: StyleSuggestState.statistical,
          drafts: StyleAssistService.drafts(hint, profile: profile),
          disclosure: 'اقتراحات صياغة إحصائية من محرك الصياغة المحلي —'
              ' بلا نموذج لغوي ولا مغادرة أي حرف للجهاز',
        );
    final deferred = () => StyleSuggestResult(
          state: StyleSuggestState.gateDeferred,
          drafts: StyleAssistService.drafts(hint, profile: profile),
          disclosure: 'الاقتراحات المولدة بالأسلوب مؤجلة حتى اجتياز القياس'
              ' الميداني المعلن — تعرض الآن الصياغة الإحصائية كما هي',
        );

    final gen = generator;
    if (gen == null || !ledger.canShip(feature)) {
      return gen == null ? stat() : deferred();
    }

    final brief = StyleBrief(hint: hint, profile: profile ?? StyleProfile.neutral, recentContext: recentContext);
    final out = await gen.suggest(brief);
    if (out == null) return stat();
    // تحقق الصياغات: غير فارغة، فريدة، بحد الثلاثة — ما دون صياغة صالحة
    // واحدة يعيد الإحصائي بلا ادعاء توليد
    final seen = <String>{};
    final valid = <String>[];
    for (final raw in out) {
      final t = raw.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      valid.add(t);
      if (valid.length == maxSuggestions) break;
    }
    if (valid.isEmpty) return stat();
    return StyleSuggestResult(
      state: StyleSuggestState.generated,
      drafts: valid
          .map((t) => StyleDraft(label: 'بأسلوبك (محلي)', text: t, hint: hint))
          .toList(),
      disclosure: 'اقتراحات مولدة على جهازك من النموذج المحلي بأسلوبك'
          ' المقاس من رسائلك — اجتاز قياسه الميداني المعلن، ولا يغادر أي حرف',
    );
  }
}
