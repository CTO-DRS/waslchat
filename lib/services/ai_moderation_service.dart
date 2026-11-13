/// مساعد الإشراف الذكي للمجتمعات العامة (ترحيل 027 — v0.15.0).
///
/// الفحص عند الطلب من شاشة الإشراف فقط: دالة الخادم moderation-ai تجلب آخر
/// الرسائل النصية للغرف المجتمع العام وتصنّفها عبر Gemini وتخزّن الملاحظات في
/// community_ai_flags — المساعد يقترح ولا ينفذ أي إجراء (الكتم والطرد بأدوات
/// الإشراف القائمة من ترحيل 023). هذه الخدمة نقية: تسميات الفئات وأيقوناتها
/// وتحليل رد Gemini الدفاعي — بلا شبكة لتُختبر مباشرة.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../config.dart';

class AiModerationService {
  /// سقف الرسائل في الفحص الواحد — يطابق ثابت الدالة على الخادم.
  static const int scanLimit = 120;

  /// سقف الملاحظات المخزنة في الفحص الواحد — يطابق ثابت الدالة.
  static const int flagsLimit = 40;

  /// فئات الملاحظات الخمس — يجب أن تطابق قيد الخادم في ترحيل 027.
  static const categories = <String>['spam', 'abuse', 'scam', 'nsfw', 'danger'];

  /// تسمية الفئة بالعربية.
  static String categoryLabel(String category) => switch (category) {
        'spam' => 'إزعاج ودعاية',
        'abuse' => 'إساءة وتشهير',
        'scam' => 'احتيال وتصيّد',
        'nsfw' => 'محتوى حساس',
        'danger' => 'تهديد وتحريض',
        _ => 'ملاحظة',
      };

  /// أيقونة الفئة المناسبة.
  static IconData categoryIcon(String category) => switch (category) {
        'spam' => Icons.repeat_rounded,
        'abuse' => Icons.sentiment_very_dissatisfied_outlined,
        'scam' => Icons.phishing_outlined,
        'nsfw' => Icons.visibility_off_outlined,
        'danger' => Icons.warning_amber_rounded,
        _ => Icons.psychology_outlined,
      };

  /// لون الفئة — أحمر للخطر والإساءة والاحتيال، وأهدأ للإزعاج والحساس.
  static Color categoryColor(String category) => switch (category) {
        'spam' => const Color(0xFFE8912D),
        'abuse' => const Color(0xFFE5484D),
        'scam' => const Color(0xFFC23B4E),
        'nsfw' => const Color(0xFFA855F7),
        'danger' => const Color(0xFFDC2626),
        _ => const Color(0xFF6366F1),
      };

  /// تسمية درجة الخطورة.
  static String severityLabel(String severity) =>
      severity == 'high' ? 'خطورة عالية' : 'خطورة منخفضة';

  /// تسمية الإجراء الذي عالج الملاحظة.
  static String resolvedActionLabel(String? action) => switch (action) {
        'ignored' => 'جُهلت',
        'muted' => 'عقبها كتم المرسل',
        'kicked' => 'عقبها طرد المرسل',
        'deleted' => 'عقبها حذف الرسالة',
        'warned' => 'عقبها إنذار المرسل',
        _ => 'مُعالَجة',
      };

  /// تحليل رد Gemini دفاعياً: يقبل مصفوفة خاماً أو نصاً محاطاً بأسوار كود
  /// أو نصاً فيه مصفوفة، ويتجاهل ما ليس به معرّف وفئة معروفة.
  /// يعيد خريطة message_id → (فئة، درجة، سبب) دون تكرار.
  static Map<String, (String, String, String)> parseVerdicts(dynamic raw) {
    List<dynamic>? arr;
    if (raw is List) {
      arr = raw;
    } else if (raw is String) {
      var t = raw.trim();
      // أسوار الكود ```json ... ```
      if (t.startsWith('```')) {
        t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '').trim();
        if (t.endsWith('```')) t = t.substring(0, t.length - 3).trim();
      }
      final start = t.indexOf('[');
      final end = t.lastIndexOf(']');
      if (start >= 0 && end > start) {
        try {
          final parsed = jsonDecode(t.substring(start, end + 1));
          if (parsed is List) arr = parsed;
        } catch (_) {
          return const {};
        }
      }
    }
    if (arr == null) return const {};

    final out = <String, (String, String, String)>{};
    for (final item in arr.take(flagsLimit * 2)) {
      if (item is! Map) continue;
      final mid = (item['message_id'] ?? '').toString().trim();
      final cat = (item['category'] ?? '').toString().trim();
      if (mid.isEmpty || !categories.contains(cat)) continue;
      final severity = item['severity'] == 'high' ? 'high' : 'low';
      final reason = (item['reason'] ?? '').toString().trim();
      out[mid] = (cat, severity, reason.length > 300 ? reason.substring(0, 300) : reason);
      if (out.length >= flagsLimit) break;
    }
    return out;
  }

  // ---------- استدعاءات الخادم ----------

  /// تشغيل فحص عبر دالة moderation-ai — يعيد (عدد المفحوص، عدد الملاحظات) أو يرمي.
  static Future<(int, int)> scan(String communityId) async {
    final res = await supabase.functions
        .invoke('moderation-ai', body: {'community_id': communityId});
    final data = res.data;
    if (data is Map && data['error'] != null) throw Exception(data['error']);
    if (data is! Map) throw Exception('رد غير متوقع');
    return (
      (data['scanned'] as num?)?.toInt() ?? 0,
      (data['flagged'] as num?)?.toInt() ?? 0,
    );
  }

  /// تفعيل/إيقاف المساعد لمجتمع عام (الخادم يرفض المجتمعات الخاصة).
  static Future<void> setEnabled(String communityId, bool enabled) =>
      supabase.rpc('community_set_ai_moderation',
          params: {'cid': communityId, 'p_enabled': enabled});

  /// قائمة الملاحظات — لمشرفي المجتمع.
  static Future<List<Map<String, dynamic>>> flags(String communityId) async {
    final data = await supabase
        .rpc('community_ai_flags_list', params: {'cid': communityId});
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// تعيين ملاحظة معالَجة: action من {ignored, muted, kicked, deleted, warned}.
  static Future<void> resolve(String flagId, String action) =>
      supabase.rpc('community_ai_flag_resolve',
          params: {'fid': flagId, 'p_action': action});
}
