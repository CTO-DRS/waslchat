/// المقترح المنفذ بعد موافقة المشرف (المرحلة 15 ج — 1.7.0، ترحيل 039).
///
/// التصميم الصادق — بلا صلاحية جديدة للبوت إطلاقاً: بوت مجتمعي نشط يرسل
/// تنبيهه نصاً عادياً ويحمل معه مقترحاً منظماً (كتم عضو لمدة أو طرده) يتحقق
/// منه الخادم صارماً على غرف المجتمعات العامة حصراً، فينام «معلقاً» حتى
/// يوافق مشرفٌ بشري من شاشة الإشراف — والتنفيذ يجري **بصلاحية المشرف
/// نفسه** عبر دوال الإشراف القائمة (ترحيل 023) لا بصلاحية البوت، وأي
/// إخفاق إشرافي حقيقي (هدف مشرف مثلاً) يُعلن بصدق ويبقي المقترح معلقاً.
///
/// حدود صادقة: المقترحات تُدار من شاشة الإشراف حصراً (هذه الخدمة)، والطرد
/// في هذه المرحلة بلا حظر (الحظر قرار بشري أثقل)، والمجموعات المشفرة لا
/// يراها البوت أصلاً فلا مقترح عليها.
import '../config.dart';

/// صف مقترح معلق كما يعود من `proposals_list` — تحليل دفاعي: الناقص
/// الجوهري يُسقط بلا انهيار
class BotProposal {
  const BotProposal({
    required this.messageId,
    required this.conversationId,
    required this.roomTitle,
    required this.botId,
    required this.botName,
    required this.targetId,
    required this.targetName,
    required this.action,
    required this.minutes,
    required this.reason,
    required this.createdAtIso,
  });

  final String messageId;
  final String conversationId;
  final String roomTitle;
  final String botId;
  final String botName;
  final String targetId;
  final String targetName;
  final String action; // mute | kick
  final int? minutes; // الكتم حصراً
  final String reason;
  final String createdAtIso;

  static BotProposal? fromRow(Map<String, dynamic> r) {
    final mid = r['message_id'] as String?;
    final cid = r['conversation_id'] as String?;
    final botId = r['bot_id'] as String?;
    final action = r['action'] as String?;
    final targetId = r['target_id'] as String?;
    if (mid == null ||
        mid.isEmpty ||
        cid == null ||
        cid.isEmpty ||
        botId == null ||
        action == null ||
        targetId == null ||
        targetId.isEmpty) {
      return null;
    }
    if (action != 'mute' && action != 'kick') return null;
    final mins = (r['minutes'] as num?)?.toInt();
    if (action == 'mute' && (mins == null || mins < 1)) return null;
    return BotProposal(
      messageId: mid,
      conversationId: cid,
      roomTitle: (r['room_title'] as String?) ?? '',
      botId: botId,
      botName: ((r['bot_name'] as String?) ?? '').trim().isEmpty
          ? 'بوت'
          : (r['bot_name'] as String),
      targetId: targetId,
      targetName: ((r['target_name'] as String?) ?? '').trim().isEmpty
          ? 'عضو'
          : (r['target_name'] as String),
      action: action,
      minutes: mins,
      reason: (r['reason'] as String?) ?? '',
      createdAtIso: (r['created_at'] as String?) ?? '',
    );
  }
}

/// الخدمة: الجلب والقرار — والأجزاء النصية نقية تُختبر مباشرة
class BotProposalsService {
  BotProposalsService._();

  /// جلب المقترحات المعلقة لمجتمع — لمشرفيه حصراً (الخادم يفرضها)
  static Future<List<BotProposal>> fetch(String communityId) async {
    final rows = await supabase.rpc('proposals_list',
        params: {'cid': communityId}) as List;
    return rows
        .map((r) => BotProposal.fromRow(Map<String, dynamic>.from(r)))
        .whereType<BotProposal>()
        .toList();
  }

  /// قرار المشرف: موافقة تنفذ بإجراءات الإشراف بصلاحية المشرف، أو رفض.
  /// يعيد نص النتيجة الصادق من الخادم: muted / kicked / rejected.
  static Future<String> resolve(String messageId, bool approve) async {
    return await supabase.rpc('proposal_resolve',
        params: {'p_msg': messageId, 'p_approve': approve}) as String;
  }

  /// المدة المعلنة نصاً — دقائق كما هي والساعات والأيام للقيم المضبوطة
  /// حصراً (60/1440 وأضدادها) فلا تقريب ولا ادعاء دقة زائفة
  static String minutesLabel(int n) {
    if (n == 1) return 'دقيقة واحدة';
    if (n == 2) return 'دقيقتان';
    if (n >= 3 && n <= 10) return '$n دقائق';
    if (n >= 1440 && n % 1440 == 0) {
      final d = n ~/ 1440;
      if (d == 1) return 'يوم واحد';
      if (d == 2) return 'يومان';
      return '$d أيام';
    }
    if (n >= 60 && n % 60 == 0) {
      final h = n ~/ 60;
      if (h == 1) return 'ساعة واحدة';
      if (h == 2) return 'ساعتان';
      return '$h ساعات';
    }
    return '$n دقيقة';
  }

  /// وصف المقترح كاملاً عربياً — نقية للعرض في البطاقة
  static String describe(BotProposal p) {
    final who = p.targetName;
    final reason = p.reason.isEmpty ? '' : ' — ${p.reason}';
    return p.action == 'mute'
        ? 'كتم $who لمدة ${minutesLabel(p.minutes ?? 0)}$reason'
        : 'طرد $who$reason';
  }

  /// رسالة خطأ عربية لقرار فشل — الأخطاء الإشرافية الحقيقية تعلن بصدق
  static String resolveErrorHint(Object e) {
    final s = e.toString();
    if (s.contains('not allowed')) {
      return 'لا يمكن إشراف مشرف — القرار يتخذ بأدوات العضو مباشرة';
    }
    if (s.contains('cannot moderate yourself')) {
      return 'لا يمكن إشراف على المشرف الموافق نفسه';
    }
    if (s.contains('not a member')) {
      return 'الهدف لم يعد عضواً — المقترح تجاوزه الزمن';
    }
    if (s.contains('proposal not found')) {
      return 'المقترح عُولج من مشرف آخر لحظة قبل قرارك';
    }
    if (s.contains('not a community room')) {
      return 'المقترح ليس في غرفة مجتمع';
    }
    return 'تعذّر تنفيذ القرار — جرّب لاحقاً';
  }

  /// نص نتيجة القرار بعد النجاح — نقية
  static String outcomeLabel(String outcome, BotProposal p) {
    switch (outcome) {
      case 'muted':
        return 'نُفّذ كتم ${p.targetName} لمدة ${minutesLabel(p.minutes ?? 0)}';
      case 'kicked':
        return 'نُفّذ طرد ${p.targetName}';
      case 'rejected':
        return 'رُفض المقترح بلا أي إجراء';
      default:
        return 'عُولج المقترح';
    }
  }
}
