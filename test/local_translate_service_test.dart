// اختبارات الترجمة المحلية القاموسية (المرحلة 9 ب — 0.23.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/local_translate_service.dart';

void main() {
  group('عربي ← إنجليزي', () {
    test('عبارة كاملة تترجم دفعة واحدة بغطاء تام', () {
      final r = LocalTranslateService.translate('صباح الخير', toEnglish: true);
      expect(r.text, 'Good morning');
      expect(r.coverage, 1.0);
      expect(r.low, isFalse);
    });

    test('العبارات أولاً على الكلمات: «كيف حالك» لا تتفكك', () {
      final r = LocalTranslateService.translate('كيف حالك', toEnglish: true);
      expect(r.text, 'How are you');
    });

    test('كلمات مفردة تترجم والمجهول يبقى كما هو', () {
      final r = LocalTranslateService.translate('شكرا كثيرا myfriend', toEnglish: true);
      expect(r.text, startsWith('Thanks'));
      expect(r.text, contains('myfriend'));
      expect(r.coverage, lessThan(1.0));
    });

    test('التشكيل والهمزات لا تكسر المطابقة والنص الأصلي يبقى عند الفشل', () {
      final r = LocalTranslateService.translate('شُكْراً جزيلاً', toEnglish: true);
      expect(r.text, 'Thank you very much');
      final r2 = LocalTranslateService.translate('أَهْلاً', toEnglish: true);
      expect(r2.text, 'Hello');
    });

    test('ترقيم الجملة الخارجي محفوظ', () {
      final r = LocalTranslateService.translate('نعم.', toEnglish: true);
      expect(r.text, 'Yes.');
    });

    test('سؤال مركب: عبارة + كلمات + كلمات مجهولة بنسبة صادقة', () {
      final r = LocalTranslateService.translate(
          'متى نلتقي مع العائلة في السوق xyzzy', toEnglish: true);
      expect(r.text, contains('When do we meet'));
      expect(r.text, contains('Family'));
      expect(r.text, contains('Market'));
      expect(r.text, contains('xyzzy'));
      expect(r.totalTokens, greaterThanOrEqualTo(5));
      expect(r.translatedTokens, lessThan(r.totalTokens));
    });
  });

  group('إنجليزي ← عربي', () {
    test('عبارة إنجليزية تعود عربياً', () {
      final r = LocalTranslateService.translate('Good morning', toEnglish: false);
      expect(r.text, 'صباح الخير');
      expect(r.coverage, 1.0);
    });

    test('كلمة إنجليزية مفردة', () {
      final r = LocalTranslateService.translate('Thanks', toEnglish: false);
      expect(r.text, 'شكرا');
    });

    test('حالة الأحرف الصغيرة والكبيرة لا تكسر', () {
      final r = LocalTranslateService.translate('GOOD MORNING', toEnglish: false);
      expect(r.text, 'صباح الخير');
    });
  });

  group('الصدق', () {
    test('نص فارغ نتيجة فارغة بلا إنفجار', () {
      final r = LocalTranslateService.translate('  ', toEnglish: true);
      expect(r.text, '');
      expect(r.totalTokens, 0);
    });

    test('نص لا يعرفه القاموس إطلاقاً يبقى كما هو وتغطيته صفر', () {
      const s = 'xyzzy plugh wibble';
      final r = LocalTranslateService.translate(s, toEnglish: true);
      expect(r.text, s);
      expect(r.coverage, 0);
      expect(r.low, isTrue);
    });

    test('تغطية ضعيفة تُعلن low بصدق', () {
      final r = LocalTranslateService.translate('مرحبا xyzzy qwerty zxcvb', toEnglish: true);
      expect(r.low, isTrue);
    });
  });
}
