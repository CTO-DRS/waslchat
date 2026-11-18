/// كاشف «يتحدث» بهسترة عتبتين — نقية بلا شبكة ولا Flutter.
///
/// الحكم من مستوى الصوت المحلي (مخرج extractAudioLevel) حصراً: بداية
/// الكلام فورية فوق عتبة البدء، والتوقف يتطلب صمتاً متواصلاً مدة معلنة،
/// وبعد البدء حد أدنى للكلام يمنع الرمش على أقصر المقاطع — وبين العتبتين
/// هسترة تبقى الحالة كما هي. العتبات معايرة على مقياس RMS الصادر عن
/// WebRTC (كلام هادئ ~0.05–0.15 وصمت خلفية ~0.001–0.01) ومعروضة كما هي.
library;

class SpeakingDetector {
  SpeakingDetector({
    this.startLevel = 0.045,
    this.stopLevel = 0.018,
    this.minSpeech = const Duration(milliseconds: 300),
    this.minSilence = const Duration(milliseconds: 450),
  })  : assert(startLevel > stopLevel, 'عتبة البدء أعلى من عتبة التوقف'),
        assert(stopLevel > 0);

  final double startLevel;
  final double stopLevel;
  final Duration minSpeech;
  final Duration minSilence;

  bool _speaking = false;
  DateTime? _speechStart;
  DateTime? _silenceStart;

  bool get speaking => _speaking;

  /// عيينة مستوى جديدة في لحظتها — تعيد الحالة الحالية.
  bool update(double level, DateTime now) {
    if (!_speaking) {
      if (level >= startLevel) {
        _speaking = true;
        _speechStart = now;
        _silenceStart = null;
      }
      return _speaking;
    }
    if (_speechStart != null && now.difference(_speechStart!) < minSpeech) {
      return true;
    }
    if (level < stopLevel) {
      _silenceStart ??= now;
      if (now.difference(_silenceStart!) >= minSilence) {
        _speaking = false;
        _speechStart = null;
        _silenceStart = null;
      }
      return _speaking;
    }
    _silenceStart = null;
    return _speaking;
  }

  void reset() {
    _speaking = false;
    _speechStart = null;
    _silenceStart = null;
  }
}
