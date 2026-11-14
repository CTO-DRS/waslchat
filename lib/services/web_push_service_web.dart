/// تنفيذ الويب الحي لإشعارات المتصفح — يُستدعى حصراً على kIsWeb.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../../config.dart';
import 'web_push_service.dart';

/// حالة إشعارات المتصفح المعروضة في الإعدادات (نص التقرير الصادق)
final ValueNotifier<String> _status = ValueNotifier<String>('جارٍ الفحص…');

/// هل الاشتراك خُزِّن فعلاً على الخادم؟
final ValueNotifier<bool> _subscribed = ValueNotifier<bool>(false);

/// نص صلاحية المتصفح الحالية
final ValueNotifier<String> _permission = ValueNotifier<String>('…');

class WebPushService {
  static ValueNotifier<String> get status => _status;
  static ValueNotifier<bool> get subscribed => _subscribed;
  static ValueNotifier<String> get permission => _permission;

  /// الجاهزية الكلية: مفتاح مُعدّ + PushManager + Service Worker —
  /// قراءة خام ديناميكية كي لا تنكسر على متصفحات قديمة بلا الواجهات،
  /// وأي غياب يعطّل الميزة بأمان بلا استثناء.
  static bool get ready {
    try {
      final nav = web.window.navigator as JSObject;
      return WebPushRules.ready(
        keyConfigured: AppConfig.webPushVapidPublicKey.isNotEmpty,
        pushManagerSupported: nav.getProperty('pushManager'.toJS) != null,
        serviceWorkerSupported: nav.getProperty('serviceWorker'.toJS) != null,
      );
    } catch (_) {
      return false;
    }
  }

  static void init() => unawaited(_refresh());

  /// طلب الصلاحية والاشتراك وتخزينه — يفشل بهدوء صادق عند أي غرابة.
  static Future<bool> enable() async {
    if (!ready) {
      _status.value = 'المتصفح لا يدعم إشعارات الدفع';
      return false;
    }
    try {
      await web.Notification.requestPermission().toDart;
      // النوع NotificationPermission هو String تعريفاً — قراءة الخصبص
      // الثابتة أنقى من نتيجة الوعد (JSString) بلا التباس تحويل
      final granted = web.Notification.permission;
      _permission.value = WebPushRules.permissionLabel(granted);
      if (granted != 'granted') {
        _status.value = WebPushRules.permissionLabel(granted);
        return false;
      }
      final reg = await _registration();
      if (reg == null) {
        _status.value = 'لم يُسجَّل عامل الصفحة بعد — أعد فتح الصفحة';
        return false;
      }
      final key = WebPushRules.decodeBase64Url(AppConfig.webPushVapidPublicKey);
      if (key == null || key.isEmpty) {
        _status.value = 'مفتاح التفعيل غير صالح — أبلغ المطور';
        return false;
      }
      final sub = await reg.pushManager
          .subscribe(
            web.PushSubscriptionOptionsInit(
              userVisibleOnly: true,
              applicationServerKey: Uint8List.fromList(key).toJS,
            ),
          )
          .toDart;
      final p256dh = sub.getKey('p256dh');
      final auth = sub.getKey('auth');
      final uid = supabase.auth.currentUser?.id;
      if (p256dh == null || auth == null || uid == null) {
        _status.value = 'اشتراك ناقص — لم يُخزَّن';
        return false;
      }
      await supabase.from('web_push_subscriptions').upsert({
        'user_id': uid,
        'endpoint': sub.endpoint,
        'p256dh': _b64url(p256dh.toDart.asUint8List()),
        'auth': _b64url(auth.toDart.asUint8List()),
        'ua': web.window.navigator.userAgent,
      }, onConflict: 'endpoint');
      _subscribed.value = true;
      _status.value = 'إشعارات المتصفح تعمل';
      return true;
    } catch (_) {
      _status.value = 'تعذّر تفعيل الإشعارات — حاول مجدداً';
      return false;
    }
  }

  /// إيقاف الاشتراك: حذف محلي وعلى الخادم — فشل الخادم لا يمنع المحلي.
  static Future<void> disable() async {
    try {
      final reg = await _registration();
      final sub = await reg?.pushManager.getSubscription().toDart;
      if (sub != null) {
        await sub.unsubscribe().toDart;
        await supabase
            .from('web_push_subscriptions')
            .delete()
            .eq('endpoint', sub.endpoint);
      }
    } catch (_) {}
    _subscribed.value = false;
    _status.value = 'الإشعارات موقوفة لهذا المتصفح';
  }

  static Future<web.ServiceWorkerRegistration?> _registration() async {
    try {
      return await web.window.navigator.serviceWorker.getRegistration().toDart;
    } catch (_) {
      return null;
    }
  }

  /// فحص الوضع الحالي بلا أي طلب صلاحية — للعرض فقط.
  static Future<void> _refresh() async {
    if (!ready) {
      _status.value = 'المتصفح لا يدعم إشعارات الدفع';
      return;
    }
    try {
      final perm = web.Notification.permission;
      _permission.value = WebPushRules.permissionLabel(perm);
      final reg = await _registration();
      final sub = await reg?.pushManager.getSubscription().toDart;
      _subscribed.value = sub != null;
      _status.value = WebPushRules.statusLabel(
        ready: ready,
        subscribed: sub != null,
        permission: perm,
      );
    } catch (_) {
      _status.value = 'جاهزة — بانتظار تفعيل الخادم (خطوات المالك وفق RUNBOOK)';
    }
  }
}

String _b64url(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
