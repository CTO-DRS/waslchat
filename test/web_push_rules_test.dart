// اختبارات قواعد إشعارات المتصفح (المرحلة 12 — 0.28.0): فك base64url
// بكل غرابته وجاهزية الميزة ببواباتها الثلاث ونصوص الحالة الصادقة.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/web_push_service.dart';

void main() {
  group('WebPushRules.decodeBase64url — صيغة applicationServerKey القياسية', () {
    test('مفتاح خام 65 بايتاً يُفك كاملاً', () {
      final raw = List<int>.generate(65, (i) => (i * 7 + 4) % 256);
      final b64u = base64Url.encode(raw).replaceAll('=', '');
      final out = WebPushRules.decodeBase64Url(b64u);
      expect(out, isNotNull);
      expect(out!.length, 65);
      expect(out, raw);
    });

    test('مفتاح VAPID الحقيقي المضمّن يفك إلى 65 بايتاً تبدأ بـ0x04 (نقطة غير مضغوطة)', () {
      // مفتاح config — نقطة منحنى P-256 غير مضغوطة تبدأ 0x04 دائماً
      final key = WebPushRules.decodeBase64Url(
          'BADInn-mhqqZWdNBBHNYsmjkX103yHW7kowEWUXJb-oOETkmTqFH5nDh4iRrz3cyDhCEUtUgtg1jw2gYXUCI-DA');
      expect(key, isNotNull);
      expect(key!.length, 65);
      expect(key.first, 0x04);
    });

    test('بدون حشوة وبحشوة = نفس النتيجة', () {
      final raw = List<int>.generate(31, (i) => i * 3);
      final padded = base64Url.encode(raw);
      final unpadded = padded.replaceAll('=', '');
      expect(WebPushRules.decodeBase64Url(unpadded), raw);
      expect(WebPushRules.decodeBase64Url(padded), raw);
    });

    test('النص الفارغ والمشوه يرفضان بصدق بلا استثناء', () {
      expect(WebPushRules.decodeBase64Url(''), isNull);
      expect(WebPushRules.decodeBase64Url('%%%%'), isNull);
      expect(WebPushRules.decodeBase64Url('Ab1'), isNull); // طول مستحيل mod 4
      expect(
        WebPushRules.decodeBase64Url('!!!غير صالح!!!'),
        isNull,
      );
    });
  });

  group('WebPushRules.ready — بوابات الجاهزية الثلاث', () {
    test('الثلاث مكتملة = جاهز', () {
      expect(
        WebPushRules.ready(
            keyConfigured: true,
            pushManagerSupported: true,
            serviceWorkerSupported: true),
        isTrue,
      );
    });

    test('أي بوابتين ناقصتين = غير جاهز', () {
      expect(
        WebPushRules.ready(
            keyConfigured: false,
            pushManagerSupported: true,
            serviceWorkerSupported: true),
        isFalse,
      );
      expect(
        WebPushRules.ready(
            keyConfigured: true,
            pushManagerSupported: false,
            serviceWorkerSupported: true),
        isFalse,
      );
      expect(
        WebPushRules.ready(
            keyConfigured: true,
            pushManagerSupported: true,
            serviceWorkerSupported: false),
        isFalse,
      );
    });
  });

  group('WebPushRules.permissionLabel — نصوص الصلاحية الصادقة', () {
    test('منوحة ومرفوضة وافتراضية تسميات صريحة', () {
      expect(WebPushRules.permissionLabel('granted'), contains('ممنوحة'));
      expect(WebPushRules.permissionLabel('denied'), contains('رُفضت'));
      expect(WebPushRules.permissionLabel('default'), contains('لم تُطلب'));
      // أي قيمة غريبة تسقط على «لم تُطلب» بلا استثناء
      expect(WebPushRules.permissionLabel('weird'), contains('لم تُطلب'));
    });
  });

  group('WebPushRules.statusLabel — الصدق قبل كل شيء', () {
    test('متصفح لا يدفع = يععلن ذلك حرفياً', () {
      expect(
        WebPushRules.statusLabel(
            ready: false, subscribed: false, permission: 'default'),
        contains('لا يدعم'),
      );
    });

    test('الصلاحية المرفوضة تتصدر مهما كان الاشتراك', () {
      expect(
        WebPushRules.statusLabel(
            ready: true, subscribed: true, permission: 'denied'),
        contains('رُفضت'),
      );
    });

    test('مشترك = يعمل، وغير مشترك = بانتظار خطوات المالك بلا ادعاء', () {
      expect(
        WebPushRules.statusLabel(
            ready: true, subscribed: true, permission: 'granted'),
        contains('تعمل'),
      );
      expect(
        WebPushRules.statusLabel(
            ready: true, subscribed: false, permission: 'granted'),
        contains('بانتظار'),
      );
    });
  });

  group('WebPushRules.titleBody — حمولة الخادم', () {
    test('حمولة كاملة تُمرر كما هي', () {
      final (title, body) =
          WebPushRules.titleBody({'title': 'سالم', 'body': '🔒 رسالة مشفرة'});
      expect(title, 'سالم');
      expect(body, '🔒 رسالة مشفرة');
    });

    test('حقول غائبة نص عام لا استثناء', () {
      final (title, body) = WebPushRules.titleBody({});
      expect(title, 'وصل شات');
      expect(body, 'رسالة جديدة');
    });
  });
}
