/// مؤشرات الأداء على الجهاز (المرحلة 12 ب — 0.29.0): قياس آلي صادق لزمن
/// الفتح البارد وزمن تأكيد الخادم للرسائل وعدّ الأخطاء المحلية — كل شيء
/// محلي بلا أي شبكة ولا رفع لأي خادم، والأرقام تُعرض لصاحبها في الإعدادات.
///
/// المنهجية الصادقة (معروضة كما هي في ورقة المؤشرات):
/// - الفتح البارد: من أول سطر في main() إلى نهاية رسم أول إطار.
/// - زمن تأكيد الخادم: من بدء طلب الإدراج إلى عودة الاستجابة الناجحة —
///   هو ليس «زمن وصول الرسالة للطرف الآخر» ولا نسميه كذلك أبداً.
/// - الأخطاء: عدّ الأخطاء التي عبرت FlutterError/onError في الجلسة
///   (ليست معدل أعطال Crashlytics — وحدة التحكم يقرأها المالك عنده).
/// - النوافذ متدحرجة بأحجام مثبتة كي لا ينفجر المخزن ولا يتحيز المعدل للماضي البعيد.
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ==================== المنطق النقي (قابل للاختبار) ====================

/// لقطة مؤشرات محسوبة — قيم جاهزة للعرض بلا حساب أثناء البناء
class MetricsSnapshot {
  const MetricsSnapshot({
    required this.deliverCount,
    required this.deliverAvgMs,
    required this.deliverP95Ms,
    required this.coldCount,
    required this.coldLastMs,
    required this.coldAvgMs,
    required this.errors,
    required this.opens,
  });
  final int deliverCount;
  final int deliverAvgMs;
  final int deliverP95Ms;
  final int coldCount;
  final int coldLastMs;
  final int coldAvgMs;
  final int errors;
  final int opens;
}

/// مخزن المؤشرات النقي: نوافذ متدحرجة ونسب مئوية حتمية
class MetricsStore {
  MetricsStore({
    this.maxDeliveries = 50,
    this.maxColdStarts = 20,
    this.maxCounters = 100000,
  });

  /// أحدث العينات أولاً (نضيف في المقدمة ونقص عند السقف)
  final List<int> deliveries = [];
  final List<int> coldStarts = [];
  final int maxDeliveries;
  final int maxColdStarts;
  final int maxCounters;
  int errors = 0;
  int opens = 0;

  void addDelivery(int ms) => _addSample(deliveries, ms, maxDeliveries);
  void addColdStart(int ms) => _addSample(coldStarts, ms, maxColdStarts);

  /// عدّاد محمي بالسقف — سقف عددي لا يرقى مهما طال العمر
  void addError() => errors = min(errors + 1, maxCounters);
  void addOpen() => opens = min(opens + 1, maxCounters);

  void reset() {
    deliveries.clear();
    coldStarts.clear();
    errors = 0;
    opens = 0;
  }

  void _addSample(List<int> list, int ms, int cap) {
    if (ms < 0) return; // عينة سالبة غريبة تُسقط بلا اختراع
    list.insert(0, ms.clamp(0, 600000)); // سقف 10 دقائق: عينة عالقة لا تفسد المعدل
    if (list.length > cap) list.removeLast();
  }

  static int avg(List<int> xs) {
    if (xs.isEmpty) return 0;
    return xs.reduce((a, b) => a + b) ~/ xs.length;
  }

  /// المئين p بأقرب ترتيب صاعد (نقية: عينات سالبة مستبعدة سلفاً)
  static int percentile(List<int> xs, double p) {
    if (xs.isEmpty) return 0;
    final s = List<int>.from(xs)..sort();
    final idx = min(s.length - 1, max(0, (p * s.length).floor()));
    return s[idx];
  }

  MetricsSnapshot snapshot() => MetricsSnapshot(
        deliverCount: deliveries.length,
        deliverAvgMs: avg(deliveries),
        deliverP95Ms: percentile(deliveries, 0.95),
        coldCount: coldStarts.length,
        coldLastMs: coldStarts.isEmpty ? 0 : coldStarts.first,
        coldAvgMs: avg(coldStarts),
        errors: errors,
        opens: opens,
      );

  // ---------- تخزين مسطح بسيط (JSON يدوي بلا حزم) ----------

  String encode() => [
        deliveries.join(','),
        coldStarts.join(','),
        errors,
        opens,
      ].join('|');

  /// تحليل دفاعي: أي غرابة تُسقط والناقص يبدأ صفراً
  static MetricsStore decode(String? raw) {
    final s = MetricsStore();
    if (raw == null || raw.isEmpty) return s;
    try {
      final parts = raw.split('|');
      if (parts.length < 4) return s;
      for (final t in parts[0].split(',')) {
        final v = int.tryParse(t);
        if (v != null) s.addDelivery(v);
      }
      for (final t in parts[1].split(',')) {
        final v = int.tryParse(t);
        if (v != null) s.addColdStart(v);
      }
      s.errors = max(0, min(int.tryParse(parts[2]) ?? 0, s.maxCounters));
      s.opens = max(0, min(int.tryParse(parts[3]) ?? 0, s.maxCounters));
    } catch (_) {}
    return s;
  }
}

// ==================== طبقة الخزن والجسر ====================

class MetricsService {
  MetricsService._();

  static const _key = 'performance_metrics_v1';
  static const _storage = FlutterSecureStorage();

  static late MetricsStore _store;
  static bool _ready = false;

  /// اللقطة الحالية — تشتغل الشاشة عليها لحظياً
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static MetricsSnapshot get snapshot =>
      _ready ? _store.snapshot() : MetricsStore().snapshot();

  static Future<void> init() async {
    if (_ready) return;
    try {
      final raw = await _storage.read(key: _key);
      _store = MetricsStore.decode(raw);
    } catch (_) {
      _store = MetricsStore();
    }
    _ready = true;
    _store.addOpen(); // كل تهيئة تطبيق = فتح واحد
    version.value++;
    _persist();
  }

  static void recordDelivery(int ms) {
    if (!_ready) return;
    _store.addDelivery(ms);
    version.value++;
    _persist();
  }

  static void recordColdStart(int ms) {
    if (!_ready) return;
    _store.addColdStart(ms);
    version.value++;
    _persist();
  }

  static void recordError() {
    if (!_ready) return;
    _store.addError();
    version.value++;
    _persist();
  }

  /// إعادة تعيين كاملة (من ورقة الإعدادات) — لا شيء يتكتم
  static Future<void> reset() async {
    if (!_ready) return;
    _store.reset();
    version.value++;
    await _persist();
  }

  /// كتابة صامتة — فشل الخزن لا يعطل القياس ولا التطبيق
  static Future<void> _persist() async {
    try {
      await _storage.write(key: _key, value: _store.encode());
    } catch (_) {}
  }
}
