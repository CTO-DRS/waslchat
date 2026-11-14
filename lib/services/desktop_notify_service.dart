/// إشعارات سطح المكتب الأساسية (المرحلة 12 — 0.28.0): ويندوز/لينكس/ماك.
///
/// تطبيق سطح المكتب لا يملك FCM — الرسائل تصل عبر قناة Realtime نفسها،
/// وهذه الخدمة تعرض إشعاراً محلياً عند وصول رسالة **والتطبيق ليس في
/// المقدمة** (الحالة غير resumed) — قواعد القرار النقية `DesktopNotifyRules`
/// مُختبَرة على كل المنصات، والتنفيذ الحي ملفوف فأي فشل يهبط بصمت
/// (سطح المكتب بلا إشعار، لا انهيار).
///
/// الصدق: النص والمنطق نسخة من دالة الخادم حرفياً — «🔒 رسالة مشفرة»
/// للمشفر واسم المرسل للمحادثات الفردية، وأسماء المجموعات المشفرة تظهر
/// «مجموعة» لأن فكها يجري في القائمة لا في خدمة الإشعار.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import 'platform_name.dart';
import 'push_service.dart';

/// معرّف تطبيق ويندوز (AUMID) الثابت — يلزم لعرض الإشعارات على ويندوز.
const _windowsAppUserModelId = 'app.waslchat.wasl_chat';
const _windowsGuid = 'e3b0c442-98fc-4bb7-9f45-a21f64d2f1b0';

/// قواعد إشعار سطح المكتب النقية — تُختبَر في VM بلا أي منصة.
class DesktopNotifyRules {
  DesktopNotifyRules._();

  /// هل المنصة مستهدفة أصلاً؟ الجوال والويب لهما مسارهما (FCM/PushService).
  static bool platformSupported({required bool kIsWeb, required String ioLabel}) =>
      !kIsWeb &&
      (ioLabel == 'ويندوز' || ioLabel == 'لينكس' || ioLabel == 'ماك');

  /// قرار الإشعار — كل الشروط الصادقة معاً:
  /// - مفعّل من الإعدادات.
  /// - التطبيق ليس في المقدمة (resumed = المستخدم ينظر أصلاً).
  /// - المحادثة ليست المعروضة الآن (اللافتة الداخلية تكفي).
  /// - ليس رسالتي أنا (من جهاز آخر).
  /// - المحادثة غير مكتومة.
  static bool shouldNotify({
    required bool enabled,
    required bool resumed,
    required String? visibleConversation,
    required String conversationId,
    required bool fromSelf,
    required bool muted,
  }) =>
      enabled &&
      !resumed &&
      visibleConversation != conversationId &&
      !fromSelf &&
      !muted;

  /// نص الإشعار من صف الرسالة — نسخة منطق دالة push الخادمية حرفياً:
  /// المشفر يُعلن مشفراً بلا فك، والوسائط بأيقونتها، وأي غرابة نص عام.
  static String bodyOf(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'image':
        return '📷 صورة';
      case 'voice':
        return '🎤 رسالة صوتية';
      case 'video':
        return '🎬 فيديو';
      case 'file':
        return '📎 ملف';
      default:
        final c = m['content'];
        if (c is String && RegExp(r'^v[123]\.').hasMatch(c)) {
          return '🔒 رسالة مشفرة';
        }
        if (c is String && c.isNotEmpty) {
          return c.length <= 140 ? c : '${c.substring(0, 140)}…';
        }
        return 'رسالة جديدة';
    }
  }

  /// عنوان الإشعار: «اسم المرسل · اسم المجموعة» للمجموعات و«اسم المرسل»
  /// للفردية — اسم المجموعة المشفر يظهر «مجموعة» كما يفعل الخادم.
  static String titleOf({
    required String senderName,
    required bool isGroup,
    required String? groupTitle,
  }) {
    if (!isGroup) return senderName;
    final t = (groupTitle == null || RegExp(r'^v1\.').hasMatch(groupTitle))
        ? 'مجموعة'
        : groupTitle;
    return '$senderName · $t';
  }
}

/// التنفيذ الحي — يُستدعى من main فقط على سطح المكتب.
class DesktopNotifyService {
  DesktopNotifyService._();

  static bool _initialized = false;
  static bool _initializing = false;
  static bool _resumed = true;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// مفتاح الإشعارات على سطح المكتب (الإعدادات) — الافتراضي مفعّل
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// ذاكرة أسماء المرسلين وكتوم المحادثات وشكلها — استعلام واحد لكل مجهول
  static final Map<String, String> _names = {};
  static final Map<String, (DateTime, bool)> _muted = {};
  static final Map<String, (bool, String?)> _shapes = {};
  static const _mutedTtl = Duration(minutes: 3);
  static const _storage = FlutterSecureStorage();
  static const _prefKey = 'desktop_notifications_enabled';

  /// المهيأة الصادقة (لعرض الحالة في الإعدادات)
  static bool get initialized => _initialized;

  static Future<void> init() async {
    if (_initialized || _initializing) return;
    final label = devicePlatformLabel();
    if (!DesktopNotifyRules.platformSupported(
        kIsWeb: kIsWeb, ioLabel: label)) {
      return;
    }
    _initializing = true;
    try {
      final on = await _storage.read(key: _prefKey);
      if (on == 'off') enabled.value = false;
      // مستمع دورة الحياة يبقى حياً عبر ربطه بربط الويدجات — لا حاجة
      // للإمساك به هنا (الربط نفسه يمنع جمعه)
      AppLifecycleListener(onStateChange: _onState);
      _resumed = WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
      final settings = InitializationSettings(
        windows: label == 'ويندوز'
            ? const WindowsInitializationSettings(
                appName: 'وصل شات',
                appUserModelId: _windowsAppUserModelId,
                guid: _windowsGuid,
              )
            : null,
        linux: label == 'لينكس'
            ? const LinuxInitializationSettings(defaultActionName: 'فتح')
            : null,
        macOS: label == 'ماك'
            ? const DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              )
            : null,
      );
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      _initialized = false; // هبوط صادق: بلا إشعار ولا انهيار
    } finally {
      _initializing = false;
    }
  }

  static void _onState(AppLifecycleState s) =>
      _resumed = s == AppLifecycleState.resumed;

  /// تغيير المفتاح من الإعدادات — يحفظ فوراً.
  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _storage.write(key: _prefKey, value: v ? 'on' : 'off');
    } catch (_) {}
  }

  /// نقطة الاستدعاء من اشتراك Realtime في قائمة المحادثات —
  /// كل غرابة تُسقط بصمت (بلا استثناء يعطل القائمة).
  static Future<void> onMessageInserted(Map<String, dynamic> m) async {
    try {
      if (!_initialized) return;
      final convId = '${m['conversation_id'] ?? ''}';
      final senderId = '${m['sender_id'] ?? ''}';
      if (convId.isEmpty || senderId.isEmpty) return;
      final muted = await _isMuted(convId);
      final grp = await _shape(convId);
      if (!DesktopNotifyRules.shouldNotify(
        enabled: enabled.value,
        resumed: _resumed,
        visibleConversation: PushService.visibleConversation,
        conversationId: convId,
        fromSelf: senderId == supabase.auth.currentUser?.id,
        muted: muted,
      )) {
        return;
      }
      final title = DesktopNotifyRules.titleOf(
        senderName: await _senderName(senderId),
        isGroup: grp.$1,
        groupTitle: grp.$2,
      );
      await _plugin.show(
        convId.hashCode & 0x7fffffff,
        title,
        DesktopNotifyRules.bodyOf(m),
        const NotificationDetails(),
      );
    } catch (_) {}
  }

  static Future<String> _senderName(String id) async {
    final cached = _names[id];
    if (cached != null) return cached;
    try {
      final p = await supabase
          .from('profiles')
          .select('username, display_name')
          .eq('id', id)
          .single();
      final n = (p['display_name'] as String?) ??
          (p['username'] as String?) ??
          'وصل شات';
      _names[id] = n;
      return n;
    } catch (_) {
      return 'وصل شات';
    }
  }

  static Future<bool> _isMuted(String convId) async {
    final c = _muted[convId];
    if (c != null && DateTime.now().difference(c.$1) < _mutedTtl) return c.$2;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return false;
      final r = await supabase
          .from('conversation_participants')
          .select('muted_until')
          .eq('conversation_id', convId)
          .eq('user_id', uid)
          .maybeSingle();
      final mu = r?['muted_until'] as String?;
      final now = DateTime.now();
      final muted = mu != null &&
          (mu == 'infinity' || DateTime.tryParse(mu)?.isAfter(now) == true);
      _muted[convId] = (now, muted);
      return muted;
    } catch (_) {
      return false;
    }
  }

  /// شكل المحادثة: (مجموعة؟, عنوانها) — مخزّن للجلسة.
  static Future<(bool, String?)> _shape(String convId) async {
    final c = _shapes[convId];
    if (c != null) return c;
    try {
      final r = await supabase
          .from('conversations')
          .select('is_group, title')
          .eq('id', convId)
          .single();
      final shape = (
        (r['is_group'] as bool?) ?? false,
        r['title'] as String?,
      );
      _shapes[convId] = shape;
      return shape;
    } catch (_) {
      return (false, null);
    }
  }
}
