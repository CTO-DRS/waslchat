import 'package:flutter/foundation.dart';

import '../config.dart';

/// إعدادات الخصوصية الاختيارية (بند المرحلة 1 من خارطة الطريق):
/// إخفاء «متصل الآن» وعلامات القراءة ✓✓.
///
/// قاعدة المبادلة (نفس سلوك واتساب): من يخفي حالته لا يرى حالة الآخرين،
/// ومن يخفي علاماته لا يرى علامات الآخرين.
/// الإعداد نفسه محفوظ في جدول privacy_settings ولا يقرؤه أي مستخدم آخر.
class PrivacyService {
  /// إخفاء حالة الاتصال: لا بثّ «متصل الآن» ولا عرض حالة الآخرين.
  static final hidePresence = ValueNotifier<bool>(false);

  /// إخفاء علامات القراءة: لا يُرسَل إيصال القراءة ولا تُعرض ✓✓ للآخرين.
  static final hideReceipts = ValueNotifier<bool>(false);

  static bool _loaded = false;

  /// يقرأ الإعدادات من الخادم مرة واحدة بعد الدخول؛ عند أي فشل تبقى القيم
  /// الافتراضية (كل شيء ظاهر) — الخصوصية الاختيارية لا تعطّل التطبيق.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final row = await supabase
          .from('privacy_settings')
          .select('hide_presence, hide_read_receipts')
          .eq('user_id', uid)
          .maybeSingle();
      hidePresence.value = row?['hide_presence'] as bool? ?? false;
      hideReceipts.value = row?['hide_read_receipts'] as bool? ?? false;
      _loaded = true;
    } catch (_) {}
  }

  /// يطبّق التغيير محلياً فوراً ثم يحفظه على الخادم بصمت.
  static Future<void> save({
    required bool hidePresenceValue,
    required bool hideReceiptsValue,
  }) async {
    hidePresence.value = hidePresenceValue;
    hideReceipts.value = hideReceiptsValue;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      await supabase.from('privacy_settings').upsert({
        'user_id': uid,
        'hide_presence': hidePresenceValue,
        'hide_read_receipts': hideReceiptsValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// يُعاد ضبطه عند تسجيل الخروج حتى لا يتسرّب إعداد مستخدم لمستخدم آخر.
  static void reset() {
    _loaded = false;
    hidePresence.value = false;
    hideReceipts.value = false;
  }
}
