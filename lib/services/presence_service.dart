import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'privacy_service.dart';

/// من المتصل الآن؟ (Supabase Realtime Presence)
/// احتراماً لإعداد «إخفاء حالة الاتصال»: من فعّله لا يبثّ حالته أصلاً،
/// ولا يشترك في القناة (قاعدة المبادلة — لا ترى ولا يُرى).
class PresenceService {
  static final online = ValueNotifier<Set<String>>(<String>{});
  static RealtimeChannel? _channel;

  static void start() {
    // نقرأ إعداد الخصوصية أولاً حتى لا يبثّ المخفي حالته ولو للحظة
    PrivacyService.load().then((_) => _start());
  }

  static void _start() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || PrivacyService.hidePresence.value) return;
    if (_channel != null) return;

    final ch = supabase.channel('online');
    _channel = ch;
    ch.onPresenceSync((_) {
      final ids = <String>{};
      for (final state in ch.presenceState()) {
        for (final p in state.presences) {
          final id = p.payload['user_id'];
          if (id is String) ids.add(id);
        }
      }
      online.value = ids;
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({'user_id': uid});
      }
    });
  }

  static Future<void> stop() async {
    final ch = _channel;
    _channel = null;
    online.value = <String>{};
    if (ch != null) await supabase.removeChannel(ch);
  }

  /// يُستدعى عند تغيير إعداد «إخفاء حالة الاتصال» من الإعدادات
  static Future<void> apply() async {
    if (PrivacyService.hidePresence.value) {
      await stop();
    } else {
      await stop();
      _start();
    }
  }

  /// هل نعرض مؤشرات الاتصال للآخرين؟ (قاعدة المبادلة)
  static bool get canShowPresence => !PrivacyService.hidePresence.value;

  static bool isOnline(String? userId) =>
      userId != null && online.value.contains(userId);
}
