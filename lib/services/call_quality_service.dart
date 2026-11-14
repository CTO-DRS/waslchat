/// خدمة جودة المكالمة النقية (المرحلة 11 أ — 0.26.0).
///
/// كل ما يُقرَّر هنا محلي بلا شبكة وبلا WebRTC — ليُختبر مباشرة. المدخل
/// عيّنات إحصاءات الاتصال (RTT/Jitter/Fقدان الحزم) كما يعيدها getStats
/// من flutter_webrtc، والمخرج تصنيف صادق لجودة الوصلة وقرار تكييف صادق.
///
/// التصميم الصادق:
/// - التصنيف من قياسات جهازك أنت حصراً — لا شيء يُرسل للخادم أو للطرف الآخر.
/// - جهاز الاستقرار (hysteresis) يمنع وميض الشارة: التدهور يحتاج عينتين
///   متتاليتين أسوأ من المستوى الحالي، والتحسن كذلك — فلا ترتد الشارة
///   بين مستويين كل ثانية.
/// - التكييف الوحيد المطبق: إيقاف الكاميرا تلقائياً مرة واحدة عند جودة
///   «ضعيفة» في مكالمة مرئية والكاميرا تعمل — الصوت دائماً أولوية.
///   لا يُعاد تشغيل الكاميرا تلقائياً أبداً؛ قرارك أنت بعدك.
/// - غياب الإحصاءات (أجهزة لا تعيد الحقول) → بلا شارة ولا ادعاء، لا
///   تخمين أبداً.
import 'package:flutter/material.dart';

/// مستويات جودة الوصلة كما تظهر للمستخدم
enum CallQualityLevel { excellent, good, weak, poor }

/// قرار التكييف المحلي
enum CallAdaptation { none, noteOnly, dimCamera }

/// عيّنة إحصاءات واحدة من getStats — كل الحقول اختيارية لأن أجهزة
/// libwebrtc لا تملأها كلها دائماً؛ الفارغ صادق ولا يُخمَّن.
class QualitySample {
  const QualitySample({this.rttMs, this.jitterMs, this.lossRate, this.audioLevel});
  final double? rttMs; // زمن الذهاب والعودة بالمللي ثانية
  final double? jitterMs; // اهتزاز الوصول بالمللي ثانية
  final double? lossRate; // نسبة فقدان الحزم 0..1
  final double? audioLevel; // مستوى صوتي 0..1 (لإشارة يتحدث)

  bool get empty =>
      rttMs == null && jitterMs == null && lossRate == null && audioLevel == null;
}

/// التصنيف القاعدي الحتمي لعينة واحدة — العتبات مثبتة ووثّقت معانيها:
/// excellent: RTT ≤ 100ms وجيتر ≤ 40ms وفقدان ≤ 1%
/// good:      RTT ≤ 250ms وجيتر ≤ 40ms وفقدان ≤ 3%
/// weak:      RTT ≤ 500ms وجيتر ≤ 80ms وفقدان ≤ 8%
/// poor:      ما وراء ذلك
CallQualityLevel classifySample(QualitySample s) {
  final rtt = s.rttMs;
  final jitter = s.jitterMs;
  final loss = s.lossRate;
  if (rtt == null && jitter == null && loss == null) return CallQualityLevel.good;
  var level = CallQualityLevel.excellent;
  void worst(CallQualityLevel l) {
    if (l.index > level.index) level = l;
  }

  if (rtt != null) {
    if (rtt > 500) {
      worst(CallQualityLevel.poor);
    } else if (rtt > 250) {
      worst(CallQualityLevel.weak);
    } else if (rtt > 100) {
      worst(CallQualityLevel.good);
    }
  }
  if (jitter != null) {
    if (jitter > 80) {
      worst(CallQualityLevel.poor);
    } else if (jitter > 40) {
      worst(CallQualityLevel.weak);
    }
  }
  if (loss != null) {
    if (loss > 0.08) {
      worst(CallQualityLevel.poor);
    } else if (loss > 0.03) {
      worst(CallQualityLevel.weak);
    } else if (loss > 0.01) {
      worst(CallQualityLevel.good);
    }
  }
  return level;
}

/// جهاز الاستقرار: يحفظ آخر 3 عينات ويُخرج المستوى المستقر.
/// القاعدة: التغيير من المستوى الحالي يحتاج عينتين متتاليتين تشيران إلى
/// مستوى آخر — العينة الوحيدة الشاذة لا تحرك الشارة.
class CallQualityGate {
  CallQualityLevel? _current;
  final List<CallQualityLevel> _recent = [];

  CallQualityLevel? get current => _current;

  /// إدخال عينة فارغة (بلا أي قياس) لا يغير شيئاً — بلا ادعاء
  CallQualityLevel? add(QualitySample s) {
    if (s.empty) return _current;
    final base = classifySample(s);
    _recent.add(base);
    if (_recent.length > 3) _recent.removeAt(0);
    if (_current == null) {
      // أول عينتين تؤسسان المستوى — لا استخلاص من واحدة
      if (_recent.length >= 2 && _recent[0] == _recent[1]) {
        _current = base;
      }
      return _current;
    }
    // عينتان متتاليتان أخريان مختلفان عن الحالي → الانتقال
    final n = _recent.length;
    if (n >= 2) {
      final a = _recent[n - 2];
      final b = _recent[n - 1];
      if (a == b && a != _current) {
        // الانتقال يقفز مستوى واحداً كحد أقصى في كل خطوة — لا قفزات صادمة
        final step = a.index > _current!.index
            ? CallQualityLevel.values[_current!.index + 1]
            : CallQualityLevel.values[_current!.index - 1];
        _current = step;
      }
    }
    return _current;
  }

  void reset() {
    _current = null;
    _recent.clear();
  }
}

/// تسميات وألوان الشارة الصادقة
class CallQualityView {
  static String label(CallQualityLevel l) => switch (l) {
        CallQualityLevel.excellent => 'الشبكة ممتازة',
        CallQualityLevel.good => 'الشبكة جيدة',
        CallQualityLevel.weak => 'الشبكة متقطعة',
        CallQualityLevel.poor => 'الشبكة ضعيفة',
      };

  static IconData icon(CallQualityLevel l) => switch (l) {
        CallQualityLevel.excellent => Icons.signal_cellular_4_bar_rounded,
        CallQualityLevel.good => Icons.signal_cellular_alt,
        CallQualityLevel.weak => Icons.signal_cellular_alt_2_bar,
        CallQualityLevel.poor => Icons.signal_wifi_off,
      };

  static Color color(CallQualityLevel l) => switch (l) {
        CallQualityLevel.excellent => const Color(0xFF22C55E),
        CallQualityLevel.good => const Color(0xFF38BDF8),
        CallQualityLevel.weak => const Color(0xFFF59E0B),
        CallQualityLevel.poor => const Color(0xFFEF4444),
      };
}

/// قرارات التكييف — صادقة ومحدودة:
/// - مكالمة صوتية: لا شيء يُطفأ؛ الملاحظة فقط.
/// - مكالمة مرئية ضعيفة وكاميرا تعمل ولم يتكيفنا من قبل: أطفئ الكاميرا مرة
///   واحدة مع ملاحظة صادقة.
/// - بعد الإطفاء: لا قرار آخر — الإعادة بيد المستخدم وحده.
CallAdaptation decideAdaptation(
  CallQualityLevel level, {
  required bool isVideo,
  required bool cameraOn,
  required bool alreadyAdapted,
}) {
  if (alreadyAdapted) return CallAdaptation.none;
  if (!isVideo) return level == CallQualityLevel.poor ? CallAdaptation.noteOnly : CallAdaptation.none;
  if (level == CallQualityLevel.weak) return CallAdaptation.noteOnly;
  if (level == CallQualityLevel.poor && cameraOn) return CallAdaptation.dimCamera;
  return CallAdaptation.none;
}

/// نص الملاحظة الصادقة التي ترافق كل تكييف
String? adaptationNote(CallAdaptation a) => switch (a) {
      CallAdaptation.none => null,
      CallAdaptation.noteOnly => 'الشبكة متقطعة — الصوت له الأولوية وقد تتباين اللحظات',
      CallAdaptation.dimCamera =>
        'أوقفنا كاميرتك مؤقتاً لأن الشبكة ضعيفة — الصوت أولاً. يمكنك إعادتها من زر الكاميرا',
    };

/// تحليل إحصاءات getStats الخام إلى عيّنة — دفاعي حرفياً: أي غرابة أو حقل
/// غائب أو قيمة غير عددية → حقل null لا استثناء. المدخل أزواج
/// (نوع الصف، قيمه) كما تعيدها الحزمة من StatsReport.type و.values —
/// النمط الأصلي يضع النوع على التقرير نفسه لا داخل القيم.
QualitySample parseQualitySample(List<(String, Map<dynamic, dynamic>)> entries) {
  double? rtt;
  double? jitter;
  double? loss;
  double? audio;

  double? readNum(Map<dynamic, dynamic> m, String key) {
    final v = m[key];
    if (v is num && v.isFinite) return v.toDouble();
    return null;
  }

  for (final (type, r) in entries) {
    if (type == 'candidate-pair') {
      // الزوج الناجح المرشَّح حصراً: succeeded أو nominated
      final state = r['state'];
      final nominated = r['nominated'];
      final ok = state == 'succeeded' || nominated == true;
      if (!ok) continue;
      // currentRoundTripTime بالثواني في المواصفة → مللي ثانية
      final crt = readNum(r, 'currentRoundTripTime');
      if (crt != null && crt >= 0) rtt ??= crt * 1000;
    } else if (type == 'inbound-rtp') {
      // المواصفة: jitter بالثواني → مللي ثانية، والفقدان نسبة محسوبة
      final j = readNum(r, 'jitter');
      if (j != null && j >= 0) jitter ??= j * 1000;
      final lost = readNum(r, 'packetsLost');
      final received = readNum(r, 'packetsReceived');
      if (lost != null && received != null) {
        final total = lost + received;
        if (total > 0) loss ??= (lost / total).clamp(0.0, 1.0);
      }
      final a = readNum(r, 'audioLevel');
      if (a != null && a >= 0 && a <= 1) audio ??= a;
      // بديل شائع: totalAudioEnergy مقسوم على المدة يقارب المستوى المتوسط
      if (audio == null) {
        final energy = readNum(r, 'totalAudioEnergy');
        final dur = readNum(r, 'totalSamplesDuration');
        if (energy != null && dur != null && dur > 0) {
          final v = (energy / dur).clamp(0.0, 1.0);
          audio = v;
        }
      }
    } else if (type == 'outbound-rtp' || type == 'media-source') {
      final a = readNum(r, 'audioLevel');
      if (a != null && a >= 0 && a <= 1) audio ??= a;
    }
  }
  return QualitySample(rttMs: rtt, jitterMs: jitter, lossRate: loss, audioLevel: audio);
}

/// قرار عرض المكالمة الواردة (المرحلة 11 أ — الرن فوق القفل):
/// التطبيق أمام المستخدم → شاشة التطبيق مباشرة كما اليوم.
/// التطبيق بالخلفية أو ميت → إشعار محلي بنية ملء الشاشة يرن ويظهر فوق القفل
/// (إن سمح النظام — الصلاحية تلقائية قبل أندرويد 14 وبموافقة المستخدم بعدها).
enum CallAlertPresentation { inAppScreen, fullScreenNotification }

CallAlertPresentation decidePresentation({required bool appResumed}) =>
    appResumed ? CallAlertPresentation.inAppScreen : CallAlertPresentation.fullScreenNotification;

/// إعداد إشعار الرن الصادر — قيم مثبتة تستهلكها PushService
class CallAlert {
  static const channelId = 'wasl-calls';
  static const channelName = 'المكالمات الواردة';
  static const channelDescription =
      'رن المكالمات الواردة فوق القفل بشاشة كاملة من وصل شات';
  static const tagPrefix = 'wasl-call-';

  static const title = 'مكالمة واردة';

  static String body({required String callerName, required bool video}) =>
      video ? '$callerName يتصل بك مرئياً' : '$callerName يتصل بك صوتياً';

  /// معرّف الإشعار مستقر للمحادثة الواحدة — رن متجدد يستبدل لا يتراكم
  static int notifId(String conversationId) =>
      tagPrefix.hashCode ^ conversationId.hashCode & 0x7FFFFFFF;

  /// حارس استئناف من الإشعار: صف مكالمة جُلب عند فتح التطبيق من الرن —
  /// لا نعرض إلا ما يرن فعلاً: رنّة، أنا المستدعى، وعمرها داخل مهلة الرنين
  /// (45 ثانية) — أطول من ذلك يعني أن الرن انتهى قبل فتحك.
  static bool resumeEligible({
    required String status,
    required bool iAmCallee,
    required Duration age,
  }) {
    if (status != 'ringing') return false;
    if (!iAmCallee) return false;
    return age >= Duration.zero && age <= const Duration(seconds: 45);
  }
}
