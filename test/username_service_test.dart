/// اختبارات خدمة أسماء المستخدمين النقية (المرحلة 13 ب — 1.2.0 — تغطية يتيمة).
///
/// كل الاختبارات على الدوال النقية: الإزالة والتطبيع والتحقق والتحليل
/// ورابط الملف — مطابقة لقيد الخادم profiles_username_format.
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/username_service.dart';

void main() {
  group('stripAt — إزالة @ الصارمة', () {
    test('يزيل @ الأولى فقط بعد تقليم المسافات والتصغير', () {
      expect(UsernameService.stripAt('  @Ahmed  '), 'ahmed');
    });

    test('بلا @ يعيد التصغير المقلم كما هو', () {
      expect(UsernameService.stripAt('Ahmed'), 'ahmed');
    });

    test('@ داخل الاسم لا تُمس (الصيغة ترفضها لاحقاً)', () {
      expect(UsernameService.stripAt('a@b'), 'a@b');
    });
  });

  group('normalize — التطبيع المطابق للخادم', () {
    test('غير المسموح يُستبدل بشرطة سفلية لكل محرف', () {
      // «أح» محرفان عربيان → شرطتان، و«!» → شرطة
      expect(UsernameService.normalize('@أحmed!'), '__med_');
    });

    test('الحروف المسموحة تبقى كما هي', () {
      expect(UsernameService.normalize('user_01x'), 'user_01x');
    });
  });

  group('validationError — رسائل عربية صادقة أو null', () {
    test('سليم يعيد null', () {
      expect(UsernameService.validationError('ahmed_01'), isNull);
    });

    test('قصير جداً يذكر الحد الأدنى 4', () {
      final e = UsernameService.validationError('abc');
      expect(e, contains('4'));
    });

    test('طويل جداً يذكر الحد الأعلى 24', () {
      final e = UsernameService.validationError('a' * 25);
      expect(e, contains('24'));
    });

    test('الحد الأعلى المسموح 24 سليم بالضبط', () {
      expect(UsernameService.validationError('a' * 24), isNull);
    });

    test('حرف غير مسموح بعد التطبيع يستحيل — التطبيع يستبدله', () {
      // التطبيع يستبدل غير المسموح بشرطة سفلية فلا يبقى خطأ صيغة أبداً —
      // ولا تُختلق رسالة لنص سيصير سليماً
      expect(UsernameService.validationError('أحمد'), isNull);
    });
  });

  group('parseFromInput — الأشكال الثلاثة المقبولة', () {
    test('اسم مباشر سليم', () {
      expect(UsernameService.parseFromInput('ahmed_01'), 'ahmed_01');
    });

    test('مع @ في البداية', () {
      expect(UsernameService.parseFromInput('@ahmed_01'), 'ahmed_01');
    });

    test('رابط الملف الشخصي الكامل مع وم دون /', () {
      expect(UsernameService.parseFromInput('https://waslchat.app/@ahmed_01'),
          'ahmed_01');
    });

    test('رابط بشرطة مائلة أخيرة مقبول', () {
      expect(UsernameService.parseFromInput('waslchat.app/@ahmed_01/'),
          'ahmed_01');
    });

    test('رابط مجهول المضيف أو باسم قصير يُرفض بلا اختراع', () {
      expect(UsernameService.parseFromInput('https://evil.com/@ahmed_01'), isNull);
      expect(UsernameService.parseFromInput('waslchat.app/@abc'), isNull);
    });

    test('الفارغ والمتناثر يعيدان null', () {
      expect(UsernameService.parseFromInput(''), isNull);
      expect(UsernameService.parseFromInput('   '), isNull);
      expect(UsernameService.parseFromInput('!!!'), isNull);
    });
  });

  group('profileLink — رابط الملف العام', () {
    test('الرابط الصحيح من موقع وصل الرسمي', () {
      expect(UsernameService.profileLink('ahmed'),
          'https://waslchat.app/@ahmed');
    });
  });
}
