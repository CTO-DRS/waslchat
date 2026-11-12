/// أحداث المجتمع وتذكيراتها (ترحيل 024 — v0.12.0).
///
/// الفرض النهائي من الخادم عبر دوال `security definer` (الإنشاء والتعديل والحذف
/// لمشرفي المجتمع أو منشئ الحدث، والرد على الحضور لأي عضو على حدث لم ينتهِ)؛
/// التذكير من الخادم: pg_cron كل 10 دقائق يستدعي دالة event-reminders فترسل
/// إشعاراً لكل الأعضاء قبل البدء بالمدة المحددة، مرة واحدة لكل حدث.
/// هذه الخدمة تنسّق الخيارات والأزمنة والنصوص العربية لعرضها — نقية بلا شبكة.
import 'package:flutter/material.dart';

class CommunityEventService {
  /// خيارات التذكير قبل البدء: (التسمية، الدقائق — صفر = بلا تذكير).
  /// يجب أن تطابق المجموعة المسموحة في الخادم {0, 15, 30, 60, 180, 1440}.
  static const remindChoices = <(String, int)>[
    ('بلا تذكير', 0),
    ('قبل 15 دقيقة', 15),
    ('قبل 30 دقيقة', 30),
    ('قبل ساعة', 60),
    ('قبل 3 ساعات', 180),
    ('قبل 24 ساعة', 1440),
  ];

  /// خيارات مدة الحدث: (التسمية، الدقائق). حد الخادم 5 → 10080 دقيقة (أسبوع).
  static const durationChoices = <(String, int)>[
    ('30 دقيقة', 30),
    ('ساعة واحدة', 60),
    ('ساعتان', 120),
    ('ثلاث ساعات', 180),
    ('يوم كامل', 1440),
  ];

  /// تسمية رد الحضور بالعربية.
  static String responseLabel(String? r) => switch (r) {
        'going' => 'سأحضر',
        'maybe' => 'ربما',
        'not_going' => 'لن أحضر',
        _ => 'لن أحضر',
      };

  /// أيقونة رد الحضور المناسبة.
  static IconData responseIcon(String? r) => switch (r) {
        'going' => Icons.check_circle_outline,
        'maybe' => Icons.help_outline,
        _ => Icons.cancel_outlined,
      };

  /// وقت البدء نصاً: «اليوم 20:30» / «غداً 09:00» / «20 نوفمبر، 18:30»
  /// (و مع السنة إن كان في سنة أخرى).
  static String formatStartsAt(DateTime starts, DateTime now) {
    final local = starts.toLocal();
    final today = now.toLocal();
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final two = (int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    final sameDay =
        local.year == today.year && local.month == today.month && local.day == today.day;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final isTomorrow = local.year == tomorrow.year &&
        local.month == tomorrow.month &&
        local.day == tomorrow.day;
    if (sameDay) return 'اليوم $time';
    if (isTomorrow) return 'غداً $time';
    final dayMonth = '${local.day} ${months[local.month - 1]}';
    final sameYear = local.year == today.year;
    return sameYear ? '$dayMonth، $time' : '$dayMonth ${local.year}، $time';
  }

  /// المتبقي حتى البدء نصاً: «يبدأ الآن» / «بعد 5 دقائق» / «بعد ساعتين و30 دقيقة».
  /// بمفرّد ومثنّى وجمع صحيح — نفس أسلوب formatRemaining في الإشراف.
  static String startsInLabel(Duration d) {
    if (d.inSeconds <= 0) return 'يبدأ الآن';
    final days = d.inDays;
    final hours = d.inHours - days * 24;
    final mins = d.inMinutes - d.inHours * 60;
    if (days >= 1) {
      return 'بعد ${hours > 0 ? '${_days(days)} و${_hours(hours)}' : _days(days)}';
    }
    if (hours >= 1) {
      return 'بعد ${mins > 0 ? '${_hours(hours)} و${_minutes(mins)}' : _hours(hours)}';
    }
    return 'بعد ${_minutes(mins)}';
  }

  /// هل الحدث جارٍ الآن (بدأ ولم ينته)؟
  static bool isLive(DateTime starts, int durationMinutes, DateTime now) {
    final end = starts.add(Duration(minutes: durationMinutes));
    return starts.isBefore(now) && end.isAfter(now);
  }

  /// تسمية خيار التذكير المختار (لعرضه في تفاصيل الحدث).
  static String remindLabel(int minutes) {
    for (final (label, m) in remindChoices) {
      if (m == minutes) return label;
    }
    return 'تذكير قبل $minutes دقيقة';
  }

  static String _minutes(int n) {
    if (n == 1) return 'دقيقة واحدة';
    if (n == 2) return 'دقيقتين';
    if (n >= 3 && n <= 10) return '$n دقائق';
    return '$n دقيقة';
  }

  static String _hours(int n) {
    if (n == 1) return 'ساعة واحدة';
    if (n == 2) return 'ساعتين';
    if (n >= 3 && n <= 10) return '$n ساعات';
    return '$n ساعة';
  }

  static String _days(int n) {
    if (n == 1) return 'يوم واحد';
    if (n == 2) return 'يومين';
    if (n >= 3 && n <= 10) return '$n أيام';
    return '$n يوماً';
  }
}
