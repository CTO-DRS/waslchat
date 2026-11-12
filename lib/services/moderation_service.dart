/// أدوات الإشراف في المجتمعات (ترحيل 023 — v0.11.0).
///
/// الفرض النهائي من الخادم عبر دوال `security definer` ومُحفّزات جدول الرسائل؛
/// هذه الخدمة تُصنّف أخطاء الخادم وتنسّق المدد وأسطر السجل لعرضها بالعربية.
/// الدوال النصية هنا نقية (بلا شبكة) لتُختبر مباشرة.
import 'package:flutter/material.dart';
class ModerationService {
  /// رسالة عربية واضحة لخطأ إرسال ناتج عن الإشراف، أو null إن لم يكن من الإشراف.
  static String? sendErrorHint(Object e) {
    final s = e.toString();
    if (s.contains('COMMUNITY_MUTED')) {
      return 'أنت مكتوم في هذا المجتمع — لا يمكنك الإرسال الآن';
    }
    if (s.contains('COMMUNITY_FILTER')) {
      return 'رسالتك تُعيد كلمة محجوبة في هذه الغرفة';
    }
    return null;
  }

  /// رسالة خطأ الانضمام إلى مجتمع مطرود منه.
  static String? joinErrorHint(Object e) {
    if (e.toString().contains('COMMUNITY_BANNED')) {
      return 'أنت مطرود من هذا المجتمع ولا يمكنك الانضمام';
    }
    return null;
  }

  /// خيارات مدد الكتم المعروضة للمشرف: (التسمية، الدقائق).
  /// الحد الأقصى للخادم 43200 دقيقة (30 يوماً).
  static const muteChoices = <(String, int)>[
    ('10 دقائق', 10),
    ('ساعة واحدة', 60),
    ('24 ساعة', 1440),
    ('7 أيام', 10080),
    ('30 يوماً', 43200),
  ];

  /// المدة المتبقية نصاً عربياً بمفرّد ومثنّى وجمع صحيح.
  static String formatRemaining(Duration d) {
    if (d.inSeconds < 60) return 'أقل من دقيقة';
    final days = d.inDays;
    final hours = d.inHours - days * 24;
    final mins = d.inMinutes - d.inHours * 60;
    if (days >= 1) {
      return hours > 0 ? '${_days(days)} و${_hours(hours)}' : _days(days);
    }
    if (hours >= 1) {
      return mins > 0 ? '${_hours(hours)} و${_minutes(mins)}' : _hours(hours);
    }
    return _minutes(mins);
  }

  /// وقت انتهاء الكتم نصاً مختصراً مثل «13 نوفمبر، 9:45».
  static String formatUntil(DateTime until, DateTime now) {
    final local = until.toLocal();
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final two = (int n) => n.toString().padLeft(2, '0');
    final sameDay =
        local.year == now.toLocal().year && local.month == now.toLocal().month && local.day == now.toLocal().day;
    final time = '${two(local.hour)}:${two(local.minute)}';
    return sameDay
        ? time
        : '${local.day} ${months[local.month - 1]}، $time';
  }

  /// سطر سجل الإشراف نصاً: الإجراء على من + السبب + بواسطة من.
  static String describeLog(Map<String, dynamic> row) {
    final action = row['action'] as String? ?? '';
    final actor = (row['actor_name'] as String?) ?? '';
    final target = (row['target_name'] as String?) ?? '';
    final details = (row['details'] as String?) ?? '';
    final targetPart = target.isEmpty ? '' : ' $target';
    final reasonPart = details.isEmpty ? '' : ' — $details';
    final actorPart = actor.isEmpty ? '' : ' · بواسطة $actor';
    switch (action) {
      case 'mute':
        return 'كتم$targetPart$reasonPart$actorPart';
      case 'unmute':
        return 'رفع الكتم عن$targetPart$actorPart';
      case 'kick':
        return 'طرد$targetPart$reasonPart$actorPart';
      case 'ban':
        return 'طرد وحظر$targetPart$reasonPart$actorPart';
      case 'unban':
        return 'رفع الحظر عن$targetPart$actorPart';
      case 'filter_add':
        return 'إضافة كلمة للفلتر: «$details»$actorPart';
      case 'filter_remove':
        return 'إزالة كلمة من الفلتر: «$details»$actorPart';
      default:
        return '$action$actorPart';
    }
  }

  /// أيقونة إجراء السجل المناسبة.
  static IconData? actionIcon(String action) => switch (action) {
        'mute' => Icons.mic_off_outlined,
        'unmute' => Icons.mic_outlined,
        'kick' => Icons.logout,
        'ban' => Icons.block_outlined,
        'unban' => Icons.check_circle_outline,
        'filter_add' => Icons.filter_alt_outlined,
        'filter_remove' => Icons.filter_alt_off_outlined,
        _ => null,
      };

  static String _minutes(int n) {
    if (n == 1) return 'دقيقة واحدة';
    if (n == 2) return 'دقيقتان';
    if (n >= 3 && n <= 10) return '$n دقائق';
    return '$n دقيقة';
  }

  static String _hours(int n) {
    if (n == 1) return 'ساعة واحدة';
    if (n == 2) return 'ساعتان';
    if (n >= 3 && n <= 10) return '$n ساعات';
    return '$n ساعة';
  }

  static String _days(int n) {
    if (n == 1) return 'يوم واحد';
    if (n == 2) return 'يومان';
    if (n >= 3 && n <= 10) return '$n أيام';
    return '$n يوماً';
  }
}
