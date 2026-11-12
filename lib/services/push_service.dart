import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_keys.dart';
import '../config.dart';
import '../firebase_options.dart';
import '../theme.dart';

/// الإشعارات عبر Firebase Cloud Messaging (اختيارية: إن لم يُعدّ Firebase تُتجاهل).
/// منذ 0.7.3:
/// - قنوات إشعارات أندرويد بأسماء عربية (الرسائل) بأهمية عالية،
/// - لافتة داخلية أنيقة عند وصول رسالة والتطبيق مفتوح،
/// - مفتاح تشغيل/إيقاف عام في الإعدادات يحذف رمز الجهاز فور الإيقاف،
/// - طلب صلاحيات تفصيلي (تنبيه + شارة + صوت) لأندرويد 13+ وiOS.
class PushService {
  static bool _ready = false;
  static bool _foregroundSet = false;
  static bool _tokenListenerSet = false;
  static bool _prefLoaded = false;

  static const _prefKey = 'notifications_enabled';
  static const _storage = FlutterSecureStorage();

  /// مفتاح الإشعارات العام (الإعدادات <- الإشعارات)، الافتراضي: مفعّل
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static Future<void> _loadPref() async {
    if (_prefLoaded) return;
    _prefLoaded = true;
    try {
      final v = await _storage.read(key: _prefKey);
      enabled.value = v != 'off';
    } catch (_) {}
  }

  /// يهيئ Firebase ويجهّز قنوات الإشعارات ومستمع الرسائل الأمامية
  static Future<void> init() async {
    if (kIsWeb) return;
    await _loadPref();
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _ready = true;
      await _setupChannels();
      _listenForeground();
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// قنوات الإشعارات على أندرويد: تنشأ أصلياً عبر MethodChannel (wasl/notify)
  /// لأن firebase_messaging 15.2+ أزال واجهة إنشاء القنوات — القناة تظهر
  /// بإعداداتها في إعدادات النظام، والخادم يوجه إليها بـ channel_id.
  static const _notify = MethodChannel('wasl/notify');

  static Future<void> _setupChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notify.invokeMethod('createMessageChannel');
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Push channels failed: $e');
    }
  }

  /// يطلب الإذن ويحفظ رمز الجهاز للمستخدم الحالي
  static Future<void> register() async {
    if (!_ready || !enabled.value) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(
          alert: true, badge: true, sound: true, provisional: false);
      final token = await fm.getToken();
      if (token != null) await _save(token);
      if (!_tokenListenerSet) {
        _tokenListenerSet = true;
        fm.onTokenRefresh.listen(_save);
      }
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  /// مستمع رسائل الخلفية الأمامية (التطبيق مفتوح): نعرض لافتة داخلية
  /// بدل الاعتماد على صمت النظام، والنقر عليها يغلقها فقط.
  static void _listenForeground() {
    if (_foregroundSet) return;
    _foregroundSet = true;
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _showInAppBanner(n.title ?? 'وصل شات', n.body ?? 'رسالة جديدة');
    });
  }

  static void _showInAppBanner(String title, String body) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    OverlayState? overlay;
    try {
      overlay = Overlay.of(ctx, rootOverlay: true);
    } catch (_) {
      return;
    }
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _InAppBanner(
        title: title,
        body: body,
        onDismiss: () {
          try {
            entry.remove();
          } catch (_) {}
        },
      ),
    );
    overlay.insert(entry);
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

  /// مفتاح الإشعارات من الإعدادات: التشغيل يعيد تسجيل الجهاز،
  /// والإيقاف يحذف الرمز من الخادم فوراً فلا يصلك أي تنبيه.
  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _storage.write(key: _prefKey, value: v ? 'on' : 'off');
    } catch (_) {}
    if (!_ready) return;
    if (v) {
      await register();
    } else {
      await unregister();
    }
  }
}

/// لافتة إشعار داخلية تظهر أعلى الشاشة عند وصول رسالة والتطبيق مفتوح:
/// شكل متسق مع هوية التطبيق، تختفي تلقائياً بعد 4 ثوانٍ أو بالنقر عليها.
class _InAppBanner extends StatefulWidget {
  const _InAppBanner({
    required this.title,
    required this.body,
    required this.onDismiss,
  });
  final String title;
  final String body;
  final VoidCallback onDismiss;

  @override
  State<_InAppBanner> createState() => _InAppBannerState();
}

class _InAppBannerState extends State<_InAppBanner> {
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), _close);
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, -18 * (1 - t)),
            child: child,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _close,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark ? WaslColors.darkSurface : WaslColors.lightSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: dark ? Colors.white24 : Colors.black.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: WaslColors.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.chat_bubble_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text(widget.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: dark ? Colors.white70 : WaslColors.ink2,
                                fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.close_rounded,
                      size: 18, color: dark ? Colors.white54 : WaslColors.ink3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
