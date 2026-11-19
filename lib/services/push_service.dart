import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_keys.dart';
import '../config.dart';
import '../firebase_options.dart';
import '../widgets/in_app_banner.dart';
import 'call_quality_service.dart';
import 'quick_action_service.dart';
import 'tone_service.dart';

/// الإشعارات عبر Firebase Cloud Messaging (اختيارية: إن لم يُعدّ Firebase تُتجاهل).
/// منذ 0.7.3:
/// - قنوات إشعارات أندرويد بأسماء عربية (الرسائل) بأهمية عالية،
/// - لافتة داخلية أنيقة عند وصول رسالة والتطبيق مفتوح،
/// - مفتاح تشغيل/إيقاف عام في الإعدادات يحذف رمز الجهاز فور الإيقاف،
/// - طلب صلاحيات تفصيلي (تنبيه + شارة + صوت) لأندرويد 13+ وiOS.
/// منذ 0.20.0 (المرحلة 8): إجراءات الإشعار — رد سريع وإيموجي وتمييز مقروء
/// من شريط الإشعار نفسه: الخادم يرسل رسائل المحادثات لأندرويد «بيانات فقط»
/// والتطبيق يعرضها بإشعار محلي يحمل الإجراءات الممتدة — أي فشل في العرض
/// أو الإجراء يهبط للسلوك السابق (فتح التطبيق أو صمت) بلا استثناء.
class PushService {
  static bool _ready = false;
  static bool _foregroundSet = false;
  static bool _tokenListenerSet = false;
  static bool _prefLoaded = false;
  static bool _localNotifReady = false;
  static bool _bgHandlerSet = false;

  static const _prefKey = 'notifications_enabled';
  static const _storage = FlutterSecureStorage();

  /// معرّفات إجراءات أندرويد الممتدة (نفسها في العرض والمعالجة)
  static const actionReply = 'wa_reply';
  static const actionReact = 'wa_react';
  static const actionMark = 'wa_mark';

  /// إيموجي التفاعل السريع من الشريط
  static const quickEmoji = '❤️';

  /// المحادثة المعروضة حالياً على الشاشة: لا إشعار محلي لها (اللافتة تكفي)
  static String? visibleConversation;

  /// مفتاح الإشعارات العام (الإعدادات <- الإشعارات)، الافتراضي: مفعّل
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

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
      _setupBackgroundHandler();
      await _initLocalNotifications();
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// معالج الخلفية (عملية معزولة عند قتل التطبيق): يعتمد بيانات الرسالة
  /// حصراً (العنوان والنص معهما) — لا يحتاج قاعدة البيانات ليُعرض.
  @pragma('vm:entry-point')
  static Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] == 'call') return; // المكالمات يعرضها النظام كما هي
    final conv = data['conversation_id'] as String?;
    if (conv == null) return;
    await PushService.showLocalNotification(
      title: data['title'] as String? ?? 'وصل شات',
      body: data['body'] as String? ?? 'رسالة جديدة',
      conversationId: conv,
      messageId: data['message_id'] as String?,
    );
  }

  /// يهيئ الإشعارات المحلية بإجراءاتها الممتدة (أندرويد فقط)
  static Future<void> _initLocalNotifications() async {
    if (defaultTargetPlatform != TargetPlatform.android || _localNotifReady) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _local.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: notificationBackgroundResponse,
      );
      _localNotifReady = true;
    } catch (e) {
      debugPrint('Local notifications disabled: $e');
    }
  }

  /// معالج الاستجابة في الخلفية (عملية معزولة): تهيئة ثم تنفيذ بالأفضل الجهد
  @pragma('vm:entry-point')
  static Future<void> notificationBackgroundResponse(NotificationResponse r) async {
    final action = QuickActionService.parse(r.payload);
    if (action == null) return;
    if (r.actionId == actionReply) {
      final text = r.input?.isNotEmpty == true ? r.input! : null;
      if (text == null || text.trim().isEmpty) return;
      if (!await QuickActionService.ensureBackend()) return;
      await QuickActionService.reply(action.conversationId, text);
      return;
    }
    if (r.actionId == actionMark) {
      if (!await QuickActionService.ensureBackend()) return;
      await QuickActionService.markRead(action.conversationId);
      return;
    }
    if (r.actionId == actionReact && action.messageId != null) {
      if (!await QuickActionService.ensureBackend()) return;
      await QuickActionService.react(action.conversationId, action.messageId!, quickEmoji);
      return;
    }
  }

  /// معالج الاستجابة في المقدمة (نفس الترتيب)
  static Future<void> _onNotificationResponse(NotificationResponse r) async {
    final action = QuickActionService.parse(r.payload);
    if (action == null) return;
    if (r.actionId == actionReply) {
      final text = r.input?.trim();
      if (text == null || text.isEmpty) return;
      if (await QuickActionService.reply(action.conversationId, text)) {
        _snackLocal('أُرسل ردك');
      } else {
        _snackLocal('تعذّر إرسال الرد — افتح التطبيق ثم أعد المحاولة');
      }
      return;
    }
    if (r.actionId == actionMark) {
      _snackLocal(await QuickActionService.markRead(action.conversationId)
          ? 'تميّز المحادثة كمقروءة'
          : 'تعذّر التنفيذ — افتح التطبيق');
      return;
    }
    if (r.actionId == actionReact && action.messageId != null) {
      _snackLocal(await QuickActionService.react(
                  action.conversationId, action.messageId!, quickEmoji)
          ? 'أُرسل التفاعل'
          : 'تعذّر إرسال التفاعل');
    }
  }

  /// صوت الإشعار: نغمة جاهزة من res/raw، أو نغمتك من الاستوديو برابطها
  static AndroidNotificationSound? _soundFor(WaslTone t) {
    if (t.id == 'system') return null;
    if (t.isCustom) return t.uri == null ? null : UriAndroidNotificationSound(t.uri!);
    return RawResourceAndroidNotificationSound(t.id);
  }

  static void _snackLocal(String msg) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// عرض إشعار محلي بإجراءات أندرويد الممتدة (رد/تفاعل/مقروء)
  /// إصلاح 1.0.1: معالج الخلفية يعمل في عزل معزول تكون فيه هذه الحالة غير
  /// مهيأة (ثابتة لكل عزل) — كانت الإشعارات تُسقط بصمت عند مقتل التطبيق.
  /// التهيئة الذاتية هنا بنفس نمط scheduleLocalReminder القائم — يدوية
  /// وغير مكلفة (تهيئة مهيأة تُعاد فوراً بحارسها) وتصلح العزلين معاً.
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    required String conversationId,
    String? messageId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!_localNotifReady) await _initLocalNotifications();
    if (!_localNotifReady) return;
    final payload = QuickActionService.encodeOpen(conversationId, messageId: messageId);
    // نغمة «وصل شات» (1.11.0): نغمة المحادثة إن اختيرت، وإلا النغمة العامة
    final t = await ToneService.effectiveTone(conversationId);
    final tone = t.id;
    final details = AndroidNotificationDetails(
      ToneService.channelId(tone),
      t.id == 'system' ? 'الرسائل' : 'الرسائل — ${t.label}',
      channelDescription: 'تنبيهات الرسائل الجديدة في محادثاتك',
      importance: Importance.high,
      priority: Priority.high,
      sound: _soundFor(t),
      playSound: true,
      groupKey: conversationId,
      setAsGroupSummary: false,
      category: AndroidNotificationCategory.message,
      actions: [
        AndroidNotificationAction(actionReply, 'رد',
            inputs: [const AndroidNotificationActionInput(label: 'اكتب رداً…')],
            allowGeneratedReplies: false,
            showsUserInterface: false),
        AndroidNotificationAction(actionReact, quickEmoji, showsUserInterface: false),
        AndroidNotificationAction(actionMark, 'مقروء', showsUserInterface: false),
      ],
    );
    try {
      await _local.show(
        conversationId.hashCode.abs(),
        title,
        body,
        NotificationDetails(android: details),
        payload: payload,
      );
    } catch (_) {}
  }

  /// إشعار «مكالمة واردة» يرن فوق القفل (المرحلة 11 أ — 0.26.0):
  /// قناة مخصصة بأهمية أقصى ونص ملء الشاشة وصوت المنبه الافتراضي للنظام،
  /// والإشعار نفسه بنية fullScreenIntent كي يظهر فوق شاشة القفل إن سمح
  /// النظام (صلاحية تلقائية قبل أندرويد 14 وبموافقة المستخدم بعدها).
  /// لا نص مخصص للرن: صوت النظام الافتراضي صادق ومضمون العمل.
  /// معرّف آخر إشعار مكالمة واردة معروض — للإسكات الدقيق بأي نهاية
  static int? _lastCallNotifId;

  static Future<void> showIncomingCallNotification({
    required String callerName,
    required bool video,
    required String conversationId,
  }) async {
    // إصلاح 1.0.1: تهيئة ذاتية للعزل المعزول — المسار نفسه الذي يشغّل
    // هذه الدالة عند الرن من الخلفية قد يكون عزلاً غير مهيأ
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!_localNotifReady) await _initLocalNotifications();
    if (!_localNotifReady) return;
    const details = AndroidNotificationDetails(
      CallAlert.channelId,
      CallAlert.channelName,
      channelDescription: CallAlert.channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      autoCancel: true,
      ongoing: false,
      visibility: NotificationVisibility.public,
    );
    final payload = QuickActionService.encodeOpen(conversationId);
    final id = CallAlert.notifId(conversationId);
    _lastCallNotifId = id;
    try {
      await _local.show(
        id,
        CallAlert.title,
        CallAlert.body(callerName: callerName, video: video),
        const NotificationDetails(android: details),
        payload: payload,
      );
    } catch (_) {}
  }

  /// إسكات رن المكالمة الواردة بأي نهاية لها — صمت صادق لا بواقي
  static Future<void> cancelIncomingCallNotification() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!_localNotifReady) await _initLocalNotifications();
    if (!_localNotifReady) return;
    try {
      final id = _lastCallNotifId;
      _lastCallNotifId = null;
      if (id != null) await _local.cancel(id);
    } catch (_) {}
  }

  /// بيانات مكالمة واردة من نقرة فتح التطبيق بارداً على إشعار الرن
  /// (المرحلة 11 أ) — null في كل غير ذلك
  static Future<Map<String, dynamic>?> initialCallData() async {
    if (!_ready || kIsWeb) return null;
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      if (m == null) return null;
      final data = m.data;
      if (data['type'] == 'call' && data['call_id'] is String) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {}
    return null;
  }

  /// معرّف الإشعار المحلي المحدد — دالة حتمية من لحظة الإطلاق، فالإلغاء
  /// يعيد حساب المعرف نفسه بلا تخزين (المناسبات الهجرية 1.4.0 تعتمده).
  static int localReminderId(DateTime fireAt) =>
      fireAt.millisecondsSinceEpoch ~/ 1000 & 0x7FFFFFFF;

  /// إلغاء تذكير محلي مجدول بلحظة إطلاقه — صامت دائماً: عدم وجود إشعار
  /// بهذا المعرف لا خطأ ولا ادعاء، والإيقاف يمنع الجدولة القادمة.
  static Future<void> cancelLocalReminder(DateTime fireAt) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _initLocalNotifications();
    if (!_localNotifReady) return;
    try {
      await _local.cancel(localReminderId(fireAt));
    } catch (_) {}
  }

  /// جدولة تذكير محلي في وقت موعد مكتشف (المرحلة 9 ب — 0.23.0):
  /// إشعار محلي على جهازك حصراً بلا أي خادم — الفشل يعيد رسالة صادقة
  /// ولا يرمي استثناءً؛ المحاولة الدقيقة أولاً ثم غير الدقيقة على أندرويد
  /// 12+ إن لم تتاح صلاحية المنبه الدقيق.
  static Future<String?> scheduleLocalReminder({
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return 'التذكير المجدول يعمل على أندرويد حالياً';
    }
    await _initLocalNotifications();
    if (!_localNotifReady) return 'تعذّر تهيئة الإشعارات المحلية';
    if (!fireAt.isAfter(DateTime.now())) return 'الوقت المكتشف انقضى — بلا جدولة';
    final t = await ToneService.effectiveTone(null);
    final tone = t.id;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        ToneService.reminderChannelId(tone),
        'التذكيرات المحلية',
        channelDescription: 'تذكيرات المواعيد على جهازك من وصل شات',
        importance: Importance.high,
        priority: Priority.high,
        sound: _soundFor(t),
      ),
    );
    final id = localReminderId(fireAt);
    try {
      tz_data.initializeTimeZones();
      final scheduled = tz.TZDateTime.from(fireAt, tz.UTC);
      await _local.zonedSchedule(
        id, title, body, scheduled, details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return null;
    } catch (_) {
      try {
        tz_data.initializeTimeZones();
        final scheduled = tz.TZDateTime.from(fireAt, tz.UTC);
        await _local.zonedSchedule(
          id, title, body, scheduled, details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        return null;
      } catch (e) {
        return 'تعذّرت جدولة التذكير على هذا الجهاز';
      }
    }
  }

  /// تسجيل مستمع رسائل الخلفية مرة واحدة (بيانات المحادثات فقط)
  static void _setupBackgroundHandler() {
    if (_bgHandlerSet || defaultTargetPlatform != TargetPlatform.android) return;
    _bgHandlerSet = true;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
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
  /// منذ 0.20.0: رسالة المحادثة (بيانات فقط) تُعرض أيضاً بإشعار محلي
  /// بإجراءاته — إلا إن كانت المحادثة معروضة حالياً أمام المستخدم.
  static void _listenForeground() {
    if (_foregroundSet) return;
    _foregroundSet = true;
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      final n = message.notification;
      final conv = data['conversation_id'] as String?;
      if (conv != null && data['type'] != 'call') {
        // رسالة محادثة (بيانات فقط من الخادم)
        if (conv == visibleConversation) return;
        unawaited(showLocalNotification(
          title: data['title'] as String? ?? 'وصل شات',
          body: data['body'] as String? ?? 'رسالة جديدة',
          conversationId: conv,
          messageId: data['message_id'] as String?,
        ));
        final title = data['title'] as String?;
        if (title != null || n != null) {
          _showInAppBanner(title ?? 'وصل شات',
              (data['body'] as String?) ?? n?.body ?? 'رسالة جديدة');
        }
        return;
      }
      if (n == null) return;
      _showInAppBanner(n.title ?? 'وصل شات', n.body ?? 'رسالة جديدة');
    });
  }

  /// اللافتة الداخلية بشكل «استوديو التطبيق» (1.13.0) — انظر WaslBanner
  static void _showInAppBanner(String title, String body) =>
      WaslBanner.show(title, body);

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
