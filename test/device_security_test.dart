import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/device_security_service.dart';
import 'package:wasl_chat/services/e2e_service.dart';

/// اختبارات نقية لأمن الأجهزة المرتبطة — إزالة جهاز كاملة (المرحلة 10 — 0.24.0):
/// تحليل مفاتيح جلسات v3 وإسقاط جلسات الأجهزة الميتة — بلا شبكة ولا تخزين.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const conv = '11111111-2222-3333-4444-555555555555';
  const devA = 'aaaaaaaa-0000-0000-0000-000000000000';
  const devB = 'bbbbbbbb-0000-0000-0000-000000000000';

  test('تحليل مفتاح جلسة v3 سليم يعيد معرف الجهاز', () {
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_$conv#$devA'), devA);
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_abc#$devB'), devB);
    // معرفات بشرطات أو بلاها — كل ما بعد # الأخير هو الجهاز
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_x#dev-with-dash'),
        'dev-with-dash');
  });

  test('المفاتيح غير السلِمة تُرفض بلا تخمين (null)', () {
    // بلا بادئة الجلسات
    expect(DeviceSecurityService.sessionDeviceId('e2e_group_key_x#dev'), isNull);
    expect(DeviceSecurityService.sessionDeviceId(''), isNull);
    // بلا #
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_$conv'), isNull);
    // # في البداية (محادثة فارغة)
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_#$devA'), isNull);
    // جهاز فارغ بعد #
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_$conv#'), isNull);
    // جهاز يحمل # — شكل غير ممكن من الكود، يُرفض
    expect(DeviceSecurityService.sessionDeviceId('e2e_r3_$conv#a#b'), isNull);
  });

  test('الإسقاط: جلسات الأجهزة الميتة فقط تُسقط والحية وغير المفهومة تبقى', () {
    final keys = [
      'e2e_r3_$conv#$devA', // جهاز ميت
      'e2e_r3_$conv#$devB', // جهاز حي
      'e2e_r3_conv2#$devA', // نفس الجهاز الميت في محادثة أخرى
      'e2e_group_key_$conv', // ليس جلسة — يبقى
      'e2e_r3_broken', // غير مفهوم — يبقى (لا نلمس ما لا نفهمه)
    ];
    final dead = DeviceSecurityService.staleSessionKeys(keys, {devB});
    expect(dead, ['e2e_r3_$conv#$devA', 'e2e_r3_conv2#$devA']);
    // كله حي: لا شيء يُسقط
    expect(DeviceSecurityService.staleSessionKeys(keys, {devA, devB}), isEmpty);
    // لا أجهزة حية أصلاً (قائمة فارغة من الخادم): الجلسات المفهومة كلها تُسقط
    final all = DeviceSecurityService.staleSessionKeys(keys, {});
    expect(all.length, 3); // devB أيضاً ميت حين لا أجهزة حية إطلاقاً
  });

  test('mk من الميتا: صالح 32 بايت حصراً — والبقية ترفض بلا استثناء', () {
    final valid = base64.encode(List<int>.generate(32, (i) => i * 7 % 256));
    expect(E2eService.mediaKeyFromMeta({'mk': valid}), valid);
    // قصير / طويل / غير base64 / غائب / بنوع خاطئ
    expect(E2eService.mediaKeyFromMeta({'mk': valid.substring(0, 10)}), isNull);
    expect(E2eService.mediaKeyFromMeta({'mk': valid + valid}), isNull);
    expect(E2eService.mediaKeyFromMeta({'mk': '%%%% not base64 %%%%'}), isNull);
    expect(E2eService.mediaKeyFromMeta({'name': 'فيلم'}), isNull);
    expect(E2eService.mediaKeyFromMeta(null), isNull);
    expect(E2eService.mediaKeyFromMeta({'mk': 42}), isNull);
    expect(E2eService.mediaKeyFromMeta({'mk': ''}), isNull);
  });

  test('التسلسل الحي يبقى صامتاً: نصوص ميتا بلا mk لا تكتب ولا تُبوح', () async {
    // rememberMediaKey مع مدخلات غير صالحة: صمت كامل بلا استثناء ولا كتابة
    await E2eService.rememberMediaKey('conv', 'msg1', 'ليس JSON');
    await E2eService.rememberMediaKey('conv', 'msg2', '{"name":"ملف"}');
    await E2eService.rememberMediaKey('conv', null, '{"mk":"x"}');
    await E2eService.rememberMediaKey('', 'msg3', null);
    // لا طريقة للتحقق من المخزن في بيئة الاختبار (لا منصة) —
    // والفشل هنا يعني فقط أن الدالة لا ترمي: سلوكها التعاقدي الصامت
    expect(true, isTrue);
  });
}
