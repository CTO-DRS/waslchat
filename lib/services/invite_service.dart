import '../config.dart';

/// روابط دعوة المجموعات الخاصة — إنشاء/تجديد/تعطيل/انضمام.
///
/// - الرابط: https://waslchat.app/join?g=<رمز 10 أحرف>
/// - إنشاء الرمز يتم في الخادم (group_invite_create) لضمان التفرد،
///   والانضمام عبر group_invite_join بلا كشف جدول الدعوات.
/// - بعد الانضمام يغلّف عضو يملك مفتاح المجموعة المفتاح للعضو الجديد تلقائياً.
class InviteService {
  InviteService._();

  static const String _urlBase = '${AppConfig.siteUrl}/join?g=';

  /// رابط الدعوة الكامل من رمز
  static String urlFor(String code) => '$_urlBase$code';

  /// يستخرج الرمز من نص ملصوق: رابط كامل أو رمز مباشر.
  /// null إن لم يبدُ رمزاً صالحاً.
  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    // رابط كامل؟ خذ ما بعد g= (قبل أي معامل آخر)
    final marker = 'g=';
    final i = s.indexOf(marker);
    if (i >= 0) s = s.substring(i + marker.length);
    if (s.contains('&')) s = s.substring(0, s.indexOf('&'));
    if (s.contains('?')) s = s.substring(0, s.indexOf('?'));
    s = s.trim().toLowerCase();
    if (RegExp(r'^[a-z0-9]{10}$').hasMatch(s)) return s;
    return null;
  }

  /// الدعوة الحالية للمجموعة (null إن لا توجد) — للمشرفين فقط عبر RLS
  static Future<Map<String, dynamic>?> fetch(String conversationId) async {
    final rows = await supabase
        .from('group_invites')
        .select('code, created_at, revoked, use_count, max_uses, expires_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  /// هل الدعوة المعادة فعّالة؟
  static bool isActive(Map<String, dynamic>? invite) {
    if (invite == null || (invite['revoked'] as bool? ?? false)) return false;
    final exp = invite['expires_at'] as String?;
    if (exp != null && DateTime.tryParse(exp)?.isBefore(DateTime.now()) == true) {
      return false;
    }
    final maxUses = invite['max_uses'] as int?;
    final used = invite['use_count'] as int? ?? 0;
    if (maxUses != null && used >= maxUses) return false;
    return true;
  }

  /// إنشاء/تجديد الدعوة — يعيد الرمز الجديد
  static Future<String> create(String conversationId) async {
    final code = await supabase.rpc('group_invite_create',
        params: {'p_conv': conversationId}) as String;
    return code;
  }

  /// تعطيل الدعوة الحالية
  static Future<void> revoke(String conversationId) async {
    await supabase
        .from('group_invites')
        .update({'revoked': true})
        .eq('conversation_id', conversationId)
        .eq('revoked', false);
  }

  /// الانضمام برمز أو رابط — يعيد معرف المحادثة
  /// يرفع FunctionException برسالة INVITE_INVALID إن كان الرمز غير صالح.
  static Future<String> join(String codeOrUrl) async {
    final code = normalize(codeOrUrl);
    if (code == null) throw const FormatException('رمز غير صالح');
    final conv = await supabase.rpc('group_invite_join',
        params: {'p_code': code}) as String;
    return conv;
  }
}
