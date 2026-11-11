import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// من المتصل الآن؟ (Supabase Realtime Presence)
class PresenceService {
  static final online = ValueNotifier<Set<String>>(<String>{});
  static RealtimeChannel? _channel;

  static void start() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || _channel != null) return;

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

  static bool isOnline(String? userId) =>
      userId != null && online.value.contains(userId);
}
