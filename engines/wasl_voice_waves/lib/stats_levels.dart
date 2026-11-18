/// استخلاص مستوى الصوت من إحصاءات WebRTC الخام — نقية بلا Flutter ولا شبكة.
///
/// المدخل أزواج (نوع التقرير، قيمه) كما تعيدها `getStats` في flutter_webrtc
/// (StatsReport.type و StatsReport.values)، والمخرج مستوى موحّد 0..1:
/// - المعياري `audioLevel` (0..1) في inbound-rtp و media-source و outbound-rtp
///   وبديل `totalAudioEnergy / totalSamplesDuration` للمتوسط.
/// - مقياس الإرث `audioInputLevel` / `audioOutputLevel` (0..32767) يوحَّد
///   بالقسمة — امتداد موثق للمنصات القديمة.
/// المنصة التي لا تعطي مستوى تعيد null — صمت صادق بلا ادعاء ولا تخمين.
library;

typedef StatsEntry = (String, Map<dynamic, dynamic>);

double? _num(Map<dynamic, dynamic> m, String key) {
  final v = m[key];
  if (v is num && v.isFinite && v >= 0) return v.toDouble();
  return null;
}

double _normalize(double v) {
  if (v <= 0) return 0;
  if (v <= 1) return v;
  if (v <= 32767) return v / 32767;
  return 1;
}

/// أفضل مستوى صوتي موحّد (0..1) من تقارير الاتصال، أو null إن لم يعطِ
/// أي تقرير مستوى. التفضيل للوارد (inbound-rtp) ثم المصدر المحلي ثم البقية.
double? extractAudioLevel(List<StatsEntry> entries) {
  double? inbound;
  double? source;
  double? any;
  for (final (type, r) in entries) {
    double? lv = _num(r, 'audioLevel');
    if (lv == null) {
      final legacy = _num(r, 'audioInputLevel') ?? _num(r, 'audioOutputLevel');
      if (legacy != null) lv = legacy;
    }
    if (lv == null && type == 'inbound-rtp') {
      final energy = _num(r, 'totalAudioEnergy');
      final dur = _num(r, 'totalSamplesDuration');
      if (energy != null && dur != null && dur > 0) {
        lv = (energy / dur).clamp(0.0, 1.0).toDouble();
      }
    }
    if (lv == null) continue;
    final v = _normalize(lv);
    if (type == 'inbound-rtp') {
      inbound ??= v;
    } else if (type == 'media-source' || type == 'outbound-rtp') {
      source ??= v;
    }
    any ??= v;
  }
  return inbound ?? source ?? any;
}
