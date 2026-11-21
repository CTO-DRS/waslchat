// اختبار جودة الإصدار (المرحلة 12 — 0.28.0): يمنع تكرار انزياح الإصدار
// الذي اكتُشف عائداً — config.dart ظل 0.25.0+54 بعد إصداري 0.26.0/0.27.0
// فرآى مستخدمو الإصدارَين «تحديث متوفر» زائفاً لأن فحص UpdateService يقارن
// build الخادم بثابت قديم. هذا الاختبار يكسر البناء على أي انزياح مستقبلي.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/config.dart';
import 'package:wasl_chat/services/media_limits.dart';

void main() {
  group('تطابق الإصدار — config ضد pubspec (منع انزياح 0.26/0.27)', () {
    late Match m;

    setUpAll(() {
      final text = File('pubspec.yaml').readAsStringSync();
      m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', multiLine: true)
          .firstMatch(text)!;
    });

    test('appVersion في config مطابق لرقم pubspec حرفياً', () {
      expect(AppConfig.appVersion, m.group(1),
          reason: 'انزياح إصدار! حدّث AppConfig.appVersion ليطابق pubspec.yaml — '
              'الانزياح يجعل شاشة «تحديث متوفر» تكذب على المستخدم');
    });

    test('appBuild في config مطابق لبناء pubspec حرفياً', () {
      expect(AppConfig.appBuild, int.parse(m.group(2)!),
          reason: 'انزياح بناء! فحص التحديث يقارن build الخادم بهذا الثابت — '
              'الثابت القديم يجعل الإصدار الحالي يعرض «تحديث متوفر» لنفسه');
    });
  });

  group('MediaLimits — مصدر واحد للحقيقة بدل التناثر اليدوي', () {
    test('حد الوسائط 24 م.ب بالبايتات الدقيقة', () {
      expect(MediaLimits.maxMediaBytes, 24 * 1024 * 1024);
      expect(MediaLimits.maxStatusBytes, 24 * 1024 * 1024);
    });

    test('حد حالة الفيديو الصارم 12 م.ب (0.27.0) دون تغيير', () {
      expect(MediaLimits.maxStatusVideoBytes, 12 * 1024 * 1024);
    });

    test('النص العربي الموحد يطابق الرقم المحسوب — أي تغيير حد يكذب إن نسيه', () {
      final mb = (MediaLimits.maxMediaBytes / (1024 * 1024)).toStringAsFixed(0);
      expect(MediaLimits.maxMediaText, contains(mb));
      expect(MediaLimits.maxMediaLabel, contains('م.ب'));
    });

    test('مفتاح VAPID العام مُعدّ بنقطة P-256 غير مضغوطة سليمة', () {
      // نقطة ECDSA P-256 غير مضغوطة: 65 بايتاً تبدأ بـ0x04 — صيغة VAPID
      final key = AppConfig.webPushVapidPublicKey;
      expect(key, isNotEmpty);
      // فك base64url يدوياً للتحقق من البنية
      var t = key.replaceAll('-', '+').replaceAll('_', '/');
      t += '=' * ((4 - (t.length % 4)) % 4);
      final bytes = base64Decode(t);
      expect(bytes.length, 65);
      expect(bytes.first, 0x04);
    });
  });
}
