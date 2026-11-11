import '../config.dart';

/// الحظر والإبلاغ (المرحلة 0 — مطلوب للمتاجر)
/// قائمة الحظر خاصة بكل مستخدم (RLS على blocks)، والفرض النهائي من الخادم
/// عبر مُحفّز `assert_dm_not_blocked` على جدول messages (ترحيل 015).
class BlockService {
  static final Set<String> _blocked = {};
  static Future<void>? _loading;

  static bool isBlocked(String userId) => _blocked.contains(userId);

  /// يجلب قائمة الحظر مرة واحدة لكل فتح تطبيق (ويعيد المحاولة إن فشلت)
  static Future<void> ensureLoaded() {
    if (_loading != null) return _loading!;
    _loading = _load();
    return _loading!;
  }

  static Future<void> _load() async {
    try {
      final rows = await supabase.from('blocks').select('blocked');
      _blocked
        ..clear()
        ..addAll(rows.map((r) => r['blocked'] as String));
    } catch (_) {
      // فشل مؤقت (شبكة): أعِد المحاولة في الاستدعاء التالي
      _loading = null;
    }
  }

  static Future<void> block(String userId) async {
    final me = supabase.auth.currentUser!.id;
    await supabase.from('blocks').insert({'blocker': me, 'blocked': userId});
    _blocked.add(userId);
  }

  static Future<void> unblock(String userId) async {
    final me = supabase.auth.currentUser!.id;
    await supabase
        .from('blocks')
        .delete()
        .eq('blocker', me)
        .eq('blocked', userId);
    _blocked.remove(userId);
  }

  /// إبلاغ عن مستخدم أو رسالة. يُقرأ من المشرفين فقط (ترحيل 014 + 015).
  static Future<void> report({
    String? targetUser,
    String? messageId,
    required String reason,
  }) async {
    final me = supabase.auth.currentUser!.id;
    await supabase.from('reports').insert({
      'reporter': me,
      if (targetUser != null) 'target_user': targetUser,
      if (messageId != null) 'message_id': messageId,
      'reason': reason,
    });
  }

  /// هل رفض الخادم الإرسال بسبب الحظر؟
  static bool isBlockedError(Object e) =>
      e.toString().toUpperCase().contains('BLOCKED');
}
