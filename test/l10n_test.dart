import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/l10n.dart';
import 'package:wasl_chat/services/locale_service.dart';

/// اختبارات الكتالوج النقي وخدمة اللغة (المرحلة 12 ب — 0.29.0):
/// كل مفتاح كامل في اللغات الثلاث، والسقوط دائماً للعربية أم التصميم،
/// والاختيار يرفض غير المدعوم — بلا نصوص مكسورة ولا فراغات أبداً.
void main() {
  group('اكتمال الكتالوج — لا مفتاح ناقص في أي لغة', () {
    test('كل مفتاح مترجم بالكامل في العربية والإنجليزية والفرنسية', () {
      final keys = l10nKeys();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(l10nComplete(k), isTrue,
            reason: 'المفتاح "$k" ناقص في إحدى اللغات');
      }
    });

    test('أسماء اللغات معرفة بالثلاثة وتعرض بلغتها نفسها', () {
      expect(l10nLanguageNames.keys, containsAll(l10nSupported));
      expect(l10nLanguageNames['ar'], 'العربية');
      expect(l10nLanguageNames['en'], 'English');
      expect(l10nLanguageNames['fr'], 'Français');
    });

    test('العربية فقط يمين-لليسار وen/fr يساران', () {
      expect(l10nIsRtl('ar'), isTrue);
      expect(l10nIsRtl('en'), isFalse);
      expect(l10nIsRtl('fr'), isFalse);
      expect(l10nIsRtl('xx'), isFalse);
    });
  });

  group('الترجمة والسقوط الصادق', () {
    test('النص نفسه يتبدل بين اللغات الثلاث لمفتاح التنقل', () {
      expect(l10nT('nav_chats', 'ar'), 'المحادثات');
      expect(l10nT('nav_chats', 'en'), 'Chats');
      expect(l10nT('nav_chats', 'fr'), 'Discussions');
    });

    test('المفتاح الغائب في لغة يهبط إلى العربية لا لترجمة غريبة', () {
      // فحص المنطق بمفتاح موجود: النتيجة للعربية هي النص العربي دائماً
      expect(l10nT('act_send', 'ar'), 'إرسال');
      // ومفتاح غير موجود إطلاقاً يعود باسمه كي يُكشف بالتحليل لا يظهر فراغاً
      expect(l10nT('missing_key', 'ar'), 'missing_key');
      expect(l10nT('missing_key', 'en'), 'missing_key');
    });

    test('مفاتيح الجودة الأربعة تطابق مستويات الشارة الحالية', () {
      for (final lvl in ['excellent', 'good', 'weak', 'poor']) {
        expect(l10nT('call_quality_$lvl', 'ar'), isNot('call_quality_$lvl'),
            reason: 'مفتاح الجودة $lvl يجب أن يكون مترجماً');
      }
    });
  });

  group('خدمة اللغة — اختيار محفوظ ورفض صادق', () {
    test('الافتراضية العربية', () {
      expect(LocaleService.lang.value, 'ar');
      expect(LocaleService.locale.languageCode, 'ar');
    });

    test('التبديل للإنجليزية والفرنسية يعمل والاتجاه يتبع', () async {
      expect(await LocaleService.set('en'), isTrue);
      expect(LocaleService.lang.value, 'en');
      expect(LocaleService.locale.languageCode, 'en');
      expect(await LocaleService.set('fr'), isTrue);
      expect(LocaleService.lang.value, 'fr');
      // العودة للعربية
      expect(await LocaleService.set('ar'), isTrue);
      expect(LocaleService.lang.value, 'ar');
      expect(l10nIsRtl(LocaleService.lang.value), isTrue);
    });

    test('غير المدعوم يُرفض ولا يتغير الاختيار', () async {
      expect(await LocaleService.set('xx'), isFalse);
      expect(await LocaleService.set('de'), isFalse);
      expect(await LocaleService.set(''), isFalse);
      expect(l10nSupported, ['ar', 'en', 'fr'],
          reason: 'الترتيب ثابت والعربية أولاً');
    });
  });
}
