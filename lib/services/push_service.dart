import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../firebase_options.dart';

/// الإشعارات عبر Firebase Cloud Messaging (اختيارية: إن لم يُعدّ Firebase تُتجاهل)
class PushService {
  static bool _ready = false;
  static bool _listening = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _ready = true;
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// يطلب الإذن ويحفظ رمز الجهاز للمستخدم الحالي
  static Future<void> register() async {
    if (!_ready) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token != null) await _save(token);
      if (!_listening) {
        _listening = true;
        fm.onTokenRefresh.listen(_save);
      }
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  static Future<void> _save(String token) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await supabase.from('device_tokens').upsert({
      'token': token,
      'user_id': uid,
      'platform': defaultTargetPlatform.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// عند تسجيل الخروج: لا نرسل إشعارات لهذا الجهاز بعد الآن
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await supabase.from('device_tokens').delete().eq('token', token);
      }
    } catch (_) {}
  }
}
