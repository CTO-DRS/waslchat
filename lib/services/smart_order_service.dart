/// الترتيب الذكي للمحادثات على الجهاز (المرحلة 9 أ — 0.22.0)
///
/// يعيد ترتيب قائمة المحادثات بمزيج إشارات محلية صرفة:
/// 1) الحداثة: نطاقات زمنية من آخر رسالة (الساعة الأخيرة أثقل من الأسبوع).
/// 2) غير المقروء: كل رسالة غير مقروءة ترفع الأولوية (بسقف حتى لا يبتلع
///    غرفة صاخبة القائمة).
/// 3) التفاعل الفعلي: عدّاد الفتح المحلي لكل محادثة — يُسجَّل على جهازك كلما
///    فتحت المحادثة، والنمو اللوغاريتمي يكافئ العادة دون انفراد قاسٍ.
/// 4) الإشارات @: وجود إشارة مستخدم في المعاينة المفكوكة يدفع المحادثة للأعلى.
/// 5) الكتم يخفض، والمثبّت يحتفظ بمكانته الأولى دائماً (الأولوية للقرار اليدوي).
///
/// الصدق: هذا ترتيب محلي لا يغيّر أي صف على الخادم، ومفتاح تعطيل واحد
/// في الإعدادات يعيد القائمة لترتيب الخادم الأصلي فوراً.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SmartOrderService {
  SmartOrderService._();

  static const _enabledKey = 'wasl_smart_order';
  static const _countsKey = 'wasl_open_counts';

  static final FlutterSecureStorage _secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));

  /// مفتاح التفعيل — مفعّل افتراضياً، والتعطيل يعيد ترتيب الخادم فوراً.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// عدّادات الفتح المحلية (معرّف المحادثة ← عدد الفتحات).
  static Map<String, int> _openCounts = {};

  static bool _initialized = false;

  /// تحميل الحالة والعدّادات من المخزن الآمن — الفشل يهبط للإعدادات الافتراضية.
  static Future<void> ensureLoaded() async {
    if (_initialized) return;
    _initialized = true;
    try {
      enabled.value = await _secure.read(key: _enabledKey) != '0';
      final raw = await _secure.read(key: _countsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _openCounts = decoded.map((k, v) => MapEntry('$k', (v as num).toInt()));
        }
      }
    } catch (_) {
      _openCounts = {};
    }
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _secure.write(key: _enabledKey, value: v ? '1' : '0');
    } catch (_) {}
  }

  /// تسجيل فتح محادثة — عدّاد محلي على الجهاز بلا أي شبكة.
  /// سقف 500 محادثة مع حذف الأقدم عددياً حتى لا ينمو المخزن بلا حدود.
  static Future<void> recordOpen(String conversationId) async {
    if (conversationId.isEmpty) return;
    try {
      _openCounts[conversationId] = (_openCounts[conversationId] ?? 0) + 1;
      if (_openCounts.length > 500) {
        final sorted = _openCounts.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final e in sorted.take(_openCounts.length - 500)) {
          _openCounts.remove(e.key);
        }
      }
      await _secure.write(
          key: _countsKey, value: jsonEncode(_openCounts));
    } catch (_) {}
  }

  /// نسخة للقراءة (الواجهة تمررها لترتيب القائمة).
  static Map<String, int> get openCounts => Map.unmodifiable(_openCounts);

  /// نقاط الحداثة بنطاقات — معايرة ثابتة قابلة للاختبار:
  /// ≤1س: 30، ≤6س: 22، ≤24س: 14، ≤3أيام: 8، ≤7أيام: 4، أقدم: 1.
  static double recencyScore(DateTime lastAt, DateTime now) {
    final h = now.difference(lastAt).inMinutes / 60.0;
    if (h.isNegative) return 30; // رسالة المستقبل (ساعة جهاز) تعامل كالآن
    if (h <= 1) return 30;
    if (h <= 6) return 22;
    if (h <= 24) return 14;
    if (h <= 72) return 8;
    if (h <= 168) return 4;
    return 1;
  }

  /// نقاط المحادثة الواحدة — مجموع الإشارات الأربع المطروحة.
  static double score(
    Map<String, dynamic> chat, {
    String? preview,
    required Map<String, int> openCounts,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final lastAtIso = (chat['last_at'] ?? '') as String;
    final lastAt = DateTime.tryParse(lastAtIso)?.toLocal() ??
        t.subtract(const Duration(days: 30));
    var s = recencyScore(lastAt, t);

    final unread = (chat['unread'] as num?)?.toInt() ?? 0;
    if (unread > 0) s += math.min(unread, 20) * 3.0;

    final opens = openCounts[chat['conversation_id'] as String?] ?? 0;
    if (opens > 0) s += math.min(math.log(1 + opens) * 6.0, 24.0);

    if (preview != null && preview.contains('@')) s += 10;

    if (chat['muted'] == true) s -= 15;
    return s;
  }

  /// الترتيب الكامل: المثبّت أولاً بترتيب الخادم بينه، ثم غير المثبّت بالنقاط
  /// (التعادل يُحسم بترتيب الخادم الأصلي — ثبات لا مفاجآت). القائمة الأصلية
  /// لا تُعدَّل.
  static List<Map<String, dynamic>> order(
    List<Map<String, dynamic>> chats, {
    Map<String, String> previews = const {},
    Map<String, int> openCounts = const {},
    DateTime? now,
  }) {
    final pinned = <Map<String, dynamic>>[];
    final rest = <Map<String, dynamic>>[];
    for (final c in chats) {
      (c['pinned'] == true ? pinned : rest).add(c);
    }
    final scored = rest.indexed.map((e) => (e.$2, score(
          e.$2,
          preview: previews[e.$2['conversation_id'] as String?],
          openCounts: openCounts,
          now: now,
        ), e.$1)).toList()
      ..sort((a, b) {
        final byScore = b.$2.compareTo(a.$2);
        if (byScore != 0) return byScore;
        return a.$3.compareTo(b.$3); // ثبات الترتيب عند التعادل
      });
    return [...pinned, ...scored.map((e) => e.$1)];
  }

  /// الإفصاح الحرفي المعروض في الإعدادات بجوار المفتاح.
  static const String disclosure =
      'يعيد ترتيب المحادثات على جهازك حسب الحداثة وغير المقروء وفتحك السابق '
      'والإشارات @ — المثبّت يبقى أولاً ولا يُرسل أي شيء، والتعطيل يعيد '
      'الترتيب الأصلي فوراً';
}
