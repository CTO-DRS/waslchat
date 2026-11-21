/// إشعارات المتصفح الفورية W3C Web Push (المرحلة 12 — 0.28.0).
///
/// مسار مستقل عن Firebase حصراً: اشتراك PushManager بمفتاح VAPID العام،
/// وتخزين الاشتراك في جدول web_push_subscriptions (ترحيل 036)، ودالة push
/// الممتدة ترسل له مباشرة (VAPID ES256 + تشفير RFC 8291 على الخادم).
/// الجهد كله على جهازك: لا محتوى يمر بالاشتراك — الرسائل مشفرة بين
/// الطرفين والخادم يرسل نص إشعار عاماً كما يفعل لأندرويد حرفياً.
///
/// الصدق: المفتاح مُعدّ في config لكن النشر يتطلب خطوات المالك (ضبط السر
/// وإعادة نشر الدالة وتشغيل الترحيل وفق RUNBOOK §3.13) — قبلها الواجهة
/// تُعلن «جاهز بانتظار تفعيل الخادم» بلا ادعاء بالعمل.
export 'web_push_service_stub.dart'
    if (dart.library.js_interop) 'web_push_service_web.dart';

import 'dart:convert';

/// قواعد Web Push النقية — بلا وصول للمنصة، تُختبَر في VM مباشرة.
class WebPushRules {
  WebPushRules._();

  /// فك base64url (بدون حشوة) — صيغة applicationServerKey القياسية.
  /// يرفض المشوّه بصدق (null) بلا استثناء ولا تخمين.
  static List<int>? decodeBase64Url(String s) {
    if (s.isEmpty) return null;
    var t = s.replaceAll('-', '+').replaceAll('_', '/');
    switch (t.length % 4) {
      case 2:
        t = '$t==';
        break;
      case 3:
        t = '$t=';
        break;
      case 1:
        return null; // طول مستحيل — مدخل مشوه
    }
    try {
      return List<int>.from(base64Decode(t));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// جاهزية الميزة في هذا المتصفح: مفتاح مُعدّ في البناء + PushManager
  /// + Service Worker — أي غياب يعطّلها بأمان.
  static bool ready({
    required bool keyConfigured,
    required bool pushManagerSupported,
    required bool serviceWorkerSupported,
  }) =>
      keyConfigured && pushManagerSupported && serviceWorkerSupported;

  /// النص الصادق لحالة الصلاحية كما تعرضه الواجهة حرفياً.
  static String permissionLabel(String permission) {
    switch (permission) {
      case 'granted':
        return 'الصلاحية ممنوحة';
      case 'denied':
        return 'رُفضت من المتصفح — فتحها من إعدادات الموقع';
      default:
        return 'لم تُطلب بعد';
    }
  }

  /// نص الحالة الكامل — الصدق أولاً: إعداد الكود لا يعني عمل الإشعار
  /// قبل خطوات المالك الخادمية.
  static String statusLabel({
    required bool ready,
    required bool subscribed,
    required String permission,
  }) {
    if (!ready) return 'المتصفح لا يدعم إشعارات الدفع';
    if (permission == 'denied') return permissionLabel(permission);
    if (subscribed) return 'إشعارات المتصفح تعمل';
    return 'جاهزة — بانتظار تفعيل الخادم (خطوات المالك وفق RUNBOOK)';
  }

  /// عنوان/نص الإشعار من حمولة الخادم — نفس منطق دالة push الحرفي:
  /// «🔒 رسالة مشفرة» للمحتوى المشفر و«رسم الوصلة» مع صورة الوسائط
  /// بأيقونتها — أي حقل غائب نص عام لا استثناء.
  static (String, String) titleBody(Map<String, dynamic> payload) {
    final title = (payload['title'] as String?) ?? 'وصل شات';
    final body = (payload['body'] as String?) ?? 'رسالة جديدة';
    return (title, body);
  }
}
