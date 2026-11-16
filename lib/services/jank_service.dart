/// قياس السقوط الإطاري (jank) — المرحلة 13 أ — 1.1.0.
///
/// قائمة الرسائل الافتراضية (ScrollablePositionedList) تبني العناصر المرئية
/// حصراً منذ 0.21.0 — وهذا القياس الموثق هو ما يُثبت السلاسة بأرقام حقيقية
/// لا بالادعاء: كل إطار مرسوم يُقاس (البناء + الرستر) ويُخزَّن في نافذة
/// متدحرجة على جهازك حصراً — لا شيء يُرفع لأي خادم — وتظهر نسبته ومتوسطه
/// وذروته في ورقة «مؤشرات الأداء» بالإعدادات.
///
/// المنهجية الصادقة (معروضة في الورقة نفسها):
/// - زمن الإطار = مدة البناء + مدة الرستر لتلك اللقطة.
/// - «إطار متعثر» = إطار تجاوز 32 مللي ثانية (أي أبطأ من نصف معدل 60fps) —
///   عتبة محافظة لا تسبّ كلاً من يلمس الشاشة بغير عمد.
/// - النافذة متدحرجة 600 إطار: الأحدث يبقى والقديم يُخلى، فلا انفجار مخزن
///   ولا انحياز لماضي بعيد.
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ==================== المنطق النقي (قابل للاختبار) ====================

/// مخزن الإطارات النقي: نافذة متدحرجة وإحصاء صادق
class JankStore {
  JankStore({this.maxFrames = 600});

  /// عتبة الإطار المتعثر بالملي ثانية — 32ms = أبطأ من 30fps فعلياً
  static const jankThresholdMs = 32;

  final int maxFrames;
  final List<int> frames = []; // الأحدث أولاً

  void addFrame(int ms) {
    if (ms < 0) return; // عينة غريبة تُسقط بلا اختراع
    frames.insert(0, ms.clamp(0, 10000)); // سقف 10 ثوانٍ للإطار العالق
    if (frames.length > maxFrames) frames.removeLast();
  }

  bool isJanky(int ms) => ms > jankThresholdMs;

  int get jankyCount => frames.where(isJanky).length;

  /// نسبة التعثر بالأجزاء المئوية من آخر [maxFrames] إطار — 0 حين لا عينات
  int jankRatioPercent() {
    if (frames.isEmpty) return 0;
    return (jankyCount * 100) ~/ frames.length;
  }

  int avgMs() {
    if (frames.isEmpty) return 0;
    return frames.reduce((a, b) => a + b) ~/ frames.length;
  }

  /// المئين p بأقرب ترتيب صاعد — حتمي بلا عوامة
  int percentile(double p) {
    if (frames.isEmpty) return 0;
    final s = List<int>.from(frames)..sort();
    var idx = (p * s.length).floor();
    if (idx < 0) idx = 0;
    if (idx > s.length - 1) idx = s.length - 1;
    return s[idx];
  }

  int worstMs() => frames.isEmpty ? 0 : frames.reduce(maxOf);

  static int maxOf(int a, int b) => a > b ? a : b;

  void reset() => frames.clear();

  String encode() => frames.join(',');

  /// تحليل دفاعي: أي غرابة تُسقط والصالح يبقى بنفس ترتيب التخزين
  /// (الأحدث أولاً كما حُفظ — لا انعكاس) والسقف يُفروض بعد التجميع
  static JankStore decode(String? raw, {int maxFrames = 600}) {
    final s = JankStore(maxFrames: maxFrames);
    if (raw == null || raw.isEmpty) return s;
    try {
      final vals = <int>[];
      for (final t in raw.split(',')) {
        final v = int.tryParse(t);
        if (v == null || v < 0) continue;
        vals.add(v.clamp(0, 10000));
      }
      s.frames.addAll(vals.length > maxFrames ? vals.sublist(0, maxFrames) : vals);
    } catch (_) {}
    return s;
  }
}

// ==================== طبقة الخزن والجسر ====================

class JankService {
  JankService._();

  static const _key = 'jank_metrics_v1';
  static const _storage = FlutterSecureStorage();

  static JankStore _store = JankStore();
  static bool _ready = false;
  static int _sincePersist = 0;

  /// للواجهة: تتغير عند كل دفعة قياس جديدة
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static JankStore get store => _store;

  /// ربط مراقب الإطارات — يُستدعى من main بعد التهيئة
  static Future<void> init() async {
    if (_ready) return;
    try {
      final raw = await _storage.read(key: _key);
      _store = JankStore.decode(raw);
    } catch (_) {
      _store = JankStore();
    }
    _ready = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    version.value++;
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!_ready || timings.isEmpty) return;
    for (final t in timings) {
      // زمن الإطار = البناء + الرستر كما هو — لا نخفي أحد التكلفين
      _store.addFrame(
          t.buildDuration.inMilliseconds + t.rasterDuration.inMilliseconds);
    }
    version.value++;
    // كتابة مُنقحرة كل 50 إطاراً — الكتابة لكل إطار ترف وحدها تعثراً
    _sincePersist += timings.length;
    if (_sincePersist >= 50) {
      _sincePersist = 0;
      _persist();
    }
  }

  static Future<void> persistNow() async {
    if (!_ready) return;
    _sincePersist = 0;
    await _persist();
  }

  /// إعادة تعيين من الورقة — بلا تكتم
  static Future<void> reset() async {
    if (!_ready) return;
    _store.reset();
    version.value++;
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      await _storage.write(key: _key, value: _store.encode());
    } catch (_) {}
  }
}
