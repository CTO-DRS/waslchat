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

  // المرحلة 14 أ (1.3.0): كتالوج موسّع وكشف الكتابة وحارس اللغة السحابية
  group('الكتابة الموسعة (1.3.0)', () {
    test('تحيات وتعبيرات جديدة تترجم كاملة', () {
      expect(LocalTranslateService.translate('إن شاء الله', toEnglish: true).text,
          'God willing');
      expect(LocalTranslateService.translate('كم الساعة', toEnglish: true).text,
          'What time is it');
      expect(LocalTranslateService.translate('الأسبوع القادم', toEnglish: true).text,
          'Next week');
      expect(LocalTranslateService.translate('كل عام وأنتم بخير', toEnglish: true).text,
          contains('May you be well'));
    });

    test('أرقام ومواعيد جديدة في الطريقين', () {
      expect(LocalTranslateService.translate('خمسة', toEnglish: true).text, 'Five');
      expect(LocalTranslateService.translate('Five', toEnglish: false).text, 'خمسة');
      expect(LocalTranslateService.translate('صباح', toEnglish: true).text, 'Morning');
      expect(LocalTranslateService.translate(' رمضان كريم ', toEnglish: true).text,
          'Ramadan Kareem');
    });

    test('عبارات جديدة تعود من الإنجليزية عربياً', () {
      final r = LocalTranslateService.translate('God willing', toEnglish: false);
      expect(r.text, 'إن شاء الله');
      expect(r.coverage, 1.0);
    });
  });

  group('كشف الكتابة (1.3.0)', () {
    test('عربي غالب يعود ar واللاتيني الغالب يعود latin — والتعادل يميل للعربية', () {
      expect(LocalTranslateService.detectScript('مرحبا كيف حالك'), 'ar');
      expect(LocalTranslateService.detectScript('Hello world'), 'latin');
      expect(LocalTranslateService.detectScript('مرحبا hello'), 'ar'); // تعادل → عربي
      expect(LocalTranslateService.detectScript('hello world مرحبا'), 'latin');
    });

    test('أرقام ورموز بلا حروف تعود other بصدق', () {
      expect(LocalTranslateService.detectScript('12345 !!! ??'), 'other');
      expect(LocalTranslateService.detectScript(''), 'other');
    });

    test('التشكيل لا يكسر الكشف العربي', () {
      expect(LocalTranslateService.detectScript('مُرْحَبًا'), 'ar');
    });
  });

  group('حارس اللغة السحابية (1.3.0)', () {
    test('رد لاتيني لطلب لاتيني يقبل، وعربي يرفض بصدق', () {
      expect(LocalTranslateService.resultMatchesTarget('Bonjour mes amis', 'fr'), isTrue);
      expect(LocalTranslateService.resultMatchesTarget('مرحبا بك', 'fr'), isFalse);
      expect(LocalTranslateService.resultMatchesTarget('Hello there', 'en'), isTrue);
      expect(LocalTranslateService.resultMatchesTarget('مرحبا بك', 'en'), isFalse);
      expect(LocalTranslateService.resultMatchesTarget('Merhaba dünya', 'tr'), isTrue);
    });

    test('الأردية تُقبل بحروفها المميزة وترفض عربية خالية منها', () {
      expect(LocalTranslateService.resultMatchesTarget('میں ٹھیک ہوں', 'ur'), isTrue);
      expect(LocalTranslateService.resultMatchesTarget('أنا بخير الحمد لله', 'ur'), isFalse);
    });

    test('المساران القائمان ar/فرنسي غير معروف لا يُمسّان', () {
      expect(LocalTranslateService.resultMatchesTarget('أي نص', 'ar'), isTrue);
      expect(LocalTranslateService.resultMatchesTarget('أي نص', 'de'), isTrue);
      expect(LocalTranslateService.resultMatchesTarget('any text', 'es'), isTrue);
    });
  });
}
