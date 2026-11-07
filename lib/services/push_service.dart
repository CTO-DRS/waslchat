import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../firebase_options.dart';
import '../main.dart';
import '../screens/chat_screen.dart';

/// الإشعارات عبر Firebase Cloud Messaging (اختيارية: إن لم يُعدّ Firebase تُتجاهل)
class PushService {
  static bool _ready = false;
  static bool _listening = false;
  static bool _tapsWired = false;

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
        fm.onTokenRefresh.listen((t) {
          unawaited(_save(t).catchError((_) {}));
        });
      }
      if (!_tapsWired) {
        _tapsWired = true;
        _wireTaps(fm);
      }
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  /// النقر على الإشعار يفتح المحادثة نفسها (على الجوال فقط؛ لويب/قنوات يُفتح التطبيق عادي)
  static void _wireTaps(FirebaseMessaging fm) {
    fm.getInitialMessage().then((m) {
      if (m != null) unawaited(_openFromTap(m));
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromTap);
  }

  static Future<void> _openFromTap(RemoteMessage message) async {
    final convId = message.data['conversation_id'] as String?;
    if (convId == null || convId.isEmpty) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    try {
      final conv = await supabase
          .from('conversations')
          .select('kind, is_group, title')
          .eq('id', convId)
          .maybeSingle();
      // القنوات وغرف المجتمعات لها شاشاتها الخاصة — يكتفي بفتح التطبيق
      if (conv == null || conv['kind'] != 'chat') return;
      final isGroup = conv['is_group'] == true;
      var title = (conv['title'] as String?) ?? 'محادثة';
      String? otherId;
      if (!isGroup) {
        final others = await supabase
            .from('conversation_participants')
            .select('user_id')
            .eq('conversation_id', convId)
            .neq('user_id', supabase.auth.currentUser?.id ?? '')
            .limit(1);
        otherId = others.isEmpty ? null : others.first['user_id'] as String;
        if (otherId != null) {
          final p = await supabase
              .from('profiles')
              .select('display_name, username')
              .eq('id', otherId)
              .maybeSingle();
          title = (p?['display_name'] ?? p?['username'] ?? title) as String;
        }
      }
      nav.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: convId,
          title: title,
          isGroup: isGroup,
          otherId: otherId,
          encrypted: true, // محادثات kind='chat' كلها مشفرة (خاصة ومجموعات)
          canPost: true,
        ),
      ));
    } catch (_) {}
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
