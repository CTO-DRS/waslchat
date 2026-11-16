/// اختبارات خدمة دعوات المجموعات النقية (المرحلة 13 ب — 1.2.0 — تغطية يتيمة).
///
/// كل الاختبارات على الدوال النقية: بناء الرابط، واستخراج الرمز من نص ملصوق،
/// وقرار فعالية الدعوة — بلا شبكة ولا خادم.
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/invite_service.dart';

void main() {
  group('urlFor — بناء رابط الدعوة', () {
    test('الرمز يُلحق بقاعدة join الرسمية بمعامل g', () {
      expect(InviteService.urlFor('abcdefghij'),
          'https://waslchat.app/join?g=abcdefghij');
    });
  });

  group('normalize — استخراج الرمز من نص ملصوق', () {
    test('رمز مباشر بعشر محارف يُقبل', () {
      expect(InviteService.normalize('aB3dEf9Xyz'), 'ab3def9xyz');
    });

    test('رابط كامل يُستخرج منه ما بعد g=', () {
      expect(InviteService.normalize('https://waslchat.app/join?g=abcdefghij'),
          'abcdefghij');
    });

    test('معاملات إضافية بعد g تُقص', () {
      expect(
          InviteService.normalize('https://waslchat.app/join?g=abcdefghij&x=1'),
          'abcdefghij');
    });

    test('علامة استفهام بعد الرمز تُقص أيضاً', () {
      expect(InviteService.normalize('waslchat.app/join?g=abcdefghij?ref=app'),
          'abcdefghij');
    });

    test('الرمز يُصغَّر ويُقلم من فراغات', () {
      expect(InviteService.normalize('  ABCDEFGHIJ  '), 'abcdefghij');
    });

    test('طول غير العشر يُرفض بلا اختراع', () {
      expect(InviteService.normalize('abcdefgh'), isNull); // 9؟ لا — ثمانية
      expect(InviteService.normalize('abcdefghijk'), isNull); // أحد عشر
    });

    test('رمز بحرف خارج الأرقام والحروف اللاتينية يُرفض', () {
      expect(InviteService.normalize('abcdefghi!'), isNull);
      expect(InviteService.normalize('أبجدهوزحطي'), isNull);
    });

    test('النص الفارغ وبدون رمز يعيدان null', () {
      expect(InviteService.normalize(''), isNull);
      expect(InviteService.normalize('   '), isNull);
      expect(InviteService.normalize('لا يوجد رمز هنا'), isNull);
    });
  });

  group('isActive — قرار فعالية الدعوة', () {
    test('null أو مسحوبة يرفضان فوراً', () {
      expect(InviteService.isActive(null), isFalse);
      expect(
          InviteService.isActive({'revoked': true, 'use_count': 0}), isFalse);
    });

    test('دعوة حية بلا سقف ولا انتهاء = فعالة', () {
      expect(InviteService.isActive({'revoked': false}), isTrue);
      expect(InviteService.isActive({}), isTrue);
    });

    test('انتهاء ماضٍ يرفض ومستقبل يمر', () {
      final past = {
        'expires_at': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      };
      final future = {
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
      };
      expect(InviteService.isActive(past), isFalse);
      expect(InviteService.isActive(future), isTrue);
    });

    test('تاريخ غير قابل للتحليل لا يُفسر انتهاءً ولا يستدلّ خطأً', () {
      expect(InviteService.isActive({'expires_at': 'not-a-date'}), isTrue);
    });

    test('سقف الاستعمال: الاستنفد يرفض وقبله يمر', () {
      final full = {'max_uses': 10, 'use_count': 10};
      final near = {'max_uses': 10, 'use_count': 9};
      final noCap = {'max_uses': null, 'use_count': 999999};
      expect(InviteService.isActive(full), isFalse);
      expect(InviteService.isActive(near), isTrue);
      expect(InviteService.isActive(noCap), isTrue);
    });
  });
}
