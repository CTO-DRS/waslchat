/// «إرسال ملاحظات» من داخل التطبيق (المرحلة 7 — برنامج المجرّبين، 0.19.0).
///
/// الملاحظة تدرج في جدول `app_feedback` (ترحيل 029) نصاً صريحاً بلا تشفير —
/// بصدق: ملاحظة لا يستطيع فريق وصل قراءتها لا تجدي، والشاشة تقول ذلك للمستخدم
/// قبل الإرسال. هذه الخدمة تُنسّق الفئات والتسميات والتنظيف والتحقق وتفسير
/// أخطاء الخادم بالعربية؛ دوالها النصية نقية (بلا شبكة) لتُختبر مباشرة.
import 'package:flutter/material.dart';

import '../config.dart';

/// (المعرف، التسمية، الأيقونة، اللون) — ترتيب العرض في الشاشة.
typedef FeedbackCategory = (String id, String label, IconData icon, Color color);

class FeedbackService {
  /// الفئات الأربع المتطابقة مع قيد الخادم في ترحيل 029 حرفياً.
  static const List<FeedbackCategory> categories = [
    ('bug', 'خلل أو خطأ', Icons.bug_report_outlined, Color(0xFFEF4444)),
    ('idea', 'فكرة أو تحسين', Icons.lightbulb_outline_rounded, Color(0xFFF59E0B)),
    ('privacy', 'ملاحظة خصوصية', Icons.privacy_tip_outlined, Color(0xFF14B8A6)),
    ('other', 'أخرى', Icons.chat_bubble_outline_rounded, Color(0xFF6366F1)),
  ];

  /// حدود الخادم في ترحيل 029 — الواجهة تفرضها قبل الإرسال كي لا يفاجأ المستخدم.
  static const minLen = 5;
  static const maxLen = 1500;

  /// حد الإغراق من الخادم (مُحفّز trg_feedback_rate): 5 ملاحظات في الساعة.
  static const limitPerHour = 5;

  /// تسمية الفئة عربياً، وأي معرف غريب يعود «أخرى» (المحلل الدفاعي).
  static String categoryLabel(String id) => switch (id) {
        'bug' => 'خلل أو خطأ',
        'idea' => 'فكرة أو تحسين',
        'privacy' => 'ملاحظة خصوصية',
        _ => 'أخرى',
      };

  /// تنظيف نص الملاحظة قبل الإرسال:
  /// إزالة محارف التحكم غير المرئية، وتقليص الأسطر الفارغة المتتالية
  /// والمسافات الطويلة، وقصّ الحدين — دون لمس محتوى الكلام نفسه.
  static String sanitize(String raw) {
    var s = raw.replaceAll(RegExp(r'[\u0000-\u0008\u000B-\u001F\u007F]'), '');
    s = s.replaceAll(RegExp(r'[ \t\u00A0]{2,}'), ' ');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    s = s.trim();
    if (s.length > maxLen) s = s.substring(0, maxLen).trim();
    return s;
  }

  /// لماذا يرفض الخادم (أو يجب رفضها قبل إرسالها له)؟ يعيد رسالة عربية
  /// أو null إن كان النص جاهزاً.
  static String? validationError(String body) {
    final s = sanitize(body);
    if (s.length < minLen) {
      return 'اكتب ملاحظة من $minLen أحرف على الأقل';
    }
    if (s.length > maxLen) {
      // نظرياً يستحيل بعد sanitize — حارس ضد تغيّر الحد لاحقاً
      return 'الملاحظة أطول من الحد المسموح ($maxLen حرفاً)';
    }
    return null;
  }

  /// رسالة عربية لخطأ الخادم، أو null إن لم يكن من أخطاء الملاحظات المعروفة.
  static String? sendErrorHint(Object e) {
    final s = e.toString();
    if (s.contains('FEEDBACK_RATE_LIMITED')) {
      return 'أرسلت ملاحظات كثيرة خلال الساعة الأخيرة — انتظر قليلاً ثم حاول من جديد';
    }
    if (s.contains('feedback_rate_guard') ||
        s.contains('feedback body check') ||
        s.contains('app_feedback_body_check')) {
      return 'الملاحظة فارغة أو أطول من الحد المسموح';
    }
    return null;
  }

  /// الإرسال الفعلي إلى الخادم — يعيد true عند النجاح.
  /// يفرض التحقق محلياً أولاً فيصل الخطأ العربي قبل أي طلب شبكي.
  static Future<bool> send({
    required String category,
    required String body,
    required String appVersion,
    required String platform,
  }) async {
    final err = validationError(body);
    if (err != null) throw Exception(err);
    if (!categories.any((c) => c.$1 == category)) category = 'other';
    // الإدراج المباشر بـRLS: سياسة «feedback insert own» تضمن هويتك،
    // ومُحفّز trg_feedback_rate يمنع الإغراق — بلا دالة سحابية جديدة.
    await supabase.from('app_feedback').insert({
      'category': category,
      'body': sanitize(body),
      'app_version': appVersion,
      'platform': platform,
    });
    return true;
  }
}
