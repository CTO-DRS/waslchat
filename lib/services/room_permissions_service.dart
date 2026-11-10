import 'package:supabase_flutter/supabase_flutter.dart';

/// الصلاحيات القابلة للتخصيص لكل غرفة (المرحلة 3 — 0.5.0).
/// يجب أن تبقى مطابقة لحرفياً لقائمة المفاتيح والافتراضات في
/// supabase/028_room_permissions.sql — اختبار الوحدة يتحقق من التطابق.
enum RoomPermKey {
  media('member_media', 'إرسال الوسائط'),
  voice('member_voice', 'الرسائل الصوتية'),
  polls('member_polls', 'الاستطلاعات'),
  invites('member_invites', 'إنشاء روابط الدعوة'),
  manageMembers('admin_manage_members', 'إدارة الأعضاء'),
  editInfo('admin_edit_info', 'تعديل معلومات الغرفة');

  const RoomPermKey(this.key, this.label);
  final String key;
  final String label;

  /// صلاحيات المشرفين (admin_*) لا تُطبّق إلا على المشرفين
  bool get adminOnly => key.startsWith('admin_');
}

/// الافتراضات تطابق السلوك القديم حرفياً: الدعوات كانت للإدارة فقط،
/// والبقية مسموحة. غرفة بلا إعدادات محفوظة = هذه الافتراضات.
const Map<String, bool> kRoomPermDefaults = {
  'member_media': true,
  'member_voice': true,
  'member_polls': true,
  'member_invites': false,
  'admin_manage_members': true,
  'admin_edit_info': true,
};

/// نتيجة جلب دوري وصلاحيات الغرفة، مع منطق التطبيق المحدد مطابق
/// للفرض الخادمي في 028 (المالك فوق كل شيء، المشرف فوق قيود الأعضاء)
class RoomPerms {
  const RoomPerms({required this.role, required this.perms});

  /// دوري في الغرفة: owner / admin / member / none (ليس عضواً)
  final String role;

  /// الخريطة المحفوظة على الخادم — الفارغة تعني «السلوك الافتراضي»
  final Map<String, bool> perms;

  bool get isOwner => role == 'owner';
  bool get isAdmin => isOwner || role == 'admin';
  bool get isMember => isAdmin || role == 'member';

  /// القيمة المحفوظة أو الافتراضي؛ المفتاح المجهول = false (أمان)
  bool _stored(String key) => perms[key] ?? kRoomPermDefaults[key] ?? false;

  /// هل يُسمح لي بهذه الصلاحية؟ مطابق للفرض الخادمي:
  /// - المالك يملك كل شيء دائماً
  /// - المشرف: فوق قيود صلاحيات الأعضاء (كالخادم في can_send والدعوات)،
  ///   وصلاحيات admin_ بحسب الغرفة
  /// - العضو: صلاحيات member_ بحسب الغرفة، ولا صلاحيات إدارية
  /// - غير العضو: لا شيء
  bool allows(RoomPermKey perm) {
    if (isOwner) return true;
    if (role == 'none') return false;
    if (perm.adminOnly) return role == 'admin' && _stored(perm.key);
    if (role == 'admin') return true;
    return _stored(perm.key);
  }

  bool get canSendMedia => allows(RoomPermKey.media);
  bool get canSendVoice => allows(RoomPermKey.voice);
  bool get canSendPolls => allows(RoomPermKey.polls);
  bool get canInvite => allows(RoomPermKey.invites);
  bool get canManageMembers => allows(RoomPermKey.manageMembers);
  bool get canEditInfo => allows(RoomPermKey.editInfo);

  /// تحليل استجابة my_room_perms من الخادم: {"role": ..., "perms": {...}}
  /// القيم غير البوليانية تُهمل (وليست false) — لا نقبل تحويلات لينة
  factory RoomPerms.parse(Map<String, dynamic> raw) {
    final roleRaw = raw['role'];
    final role = (roleRaw is String && roleRaw.isNotEmpty) ? roleRaw : 'none';
    final permsRaw = raw['perms'];
    final map = <String, bool>{};
    if (permsRaw is Map<String, dynamic>) {
      permsRaw.forEach((k, v) {
        if (v is bool) map[k] = v;
      });
    }
    return RoomPerms(role: role, perms: map);
  }
}

/// خدمة الصلاحيات: استدعاء واحد my_room_perms يجلب الدور والصلاحيات معاً
class RoomPermissionsService {
  const RoomPermissionsService._();

  static final SupabaseClient _client = Supabase.instance.client;

  /// يجلب دوري وصلاحيات الغرفة في استدعاء واحد.
  /// يعيد RoomPerms برول 'none' عند أي فشل — الواجهة تُبقي الخيارات
  /// بقرار الخادم عند الإرسال (الفشل لا يمنع الشاشة من العمل)
  static Future<RoomPerms> fetch(String conversationId) async {
    try {
      final raw = await _client.rpc('my_room_perms',
          params: {'p_conv': conversationId});
      if (raw is Map<String, dynamic>) {
        return RoomPerms.parse(raw);
      }
    } catch (_) {}
    return const RoomPerms(role: 'none', perms: {});
  }

  /// حفظ صلاحيات الغرفة (المالك فقط — الخادم يفرض ذلك).
  /// يعيد الخريطة النهائية كما سجلها الخادم.
  static Future<Map<String, bool>> save(
      String conversationId, Map<String, bool> perms) async {
    final r = await _client.rpc('room_set_permissions',
        params: {'p_conv': conversationId, 'p_perms': perms});
    final out = <String, bool>{};
    if (r is Map<String, dynamic>) {
      r.forEach((k, v) {
        if (v is bool) out[k] = v;
      });
    }
    return out;
  }

  /// رسالة عربية واضحة لرفض الخادم بسبب صلاحية الغرفة
  static String rejectionMessage(Object error) {
    final s = error.toString();
    if (s.contains('owner only')) return 'الصلاحيات يغيّرها مالك المجموعة فقط';
    if (s.contains('forbidden') || s.contains('admins only')) {
      return 'مالك المجموعة قيّد هذه الصلاحية';
    }
    if (s.contains('row-level') || s.contains('permission')) {
      return 'مالك المجموعة قيّد هذا النوع من الرسائل';
    }
    return 'تعذّر تنفيذ الطلب';
  }
}
