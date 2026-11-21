/// اختبارات كتالوج wasl_l10n النقي — مكيَّفة الاستيراد من اختبارات التطبيق:
/// اكتمال كل مفتاح في اللغات الثلاث، والسقوط دائماً للعربية أم التصميم،
/// والعربية فقط يمين-لليسار — بلا نصوص مكسورة ولا فراغات أبداً.
import 'package:test/test.dart';
import 'package:wasl_l10n/l10n.dart';

void main() {
  group('اكتمال الكتالوج — لا مفتاح ناقص في أي لغة', () {
    test('كل مفتاح مترجم بالكامل في العربية والإنجليزية والفرنسية', () {
      final keys = l10nKeys();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(l10nComplete(k), isTrue, reason: 'المفتاح "$k" ناقص في إحدى اللغات');
      }
    });

    test('أسماء اللغات معرفة بالثلاثة وتعرض بلغتها نفسها', () {
      expect(l10nLanguageNames.keys, containsAll(l10nSupported));
      expect(l10nLanguageNames['ar'], 'العربية');
      expect(l10nLanguageNames['en'], 'English');
      expect(l10nLanguageNames['fr'], 'Français');
    });
  });

  group('السقوط الصادق', () {
    test('مفتاح غائب في en/fr يهبط للعربية لا لنص مكسور', () {
      expect(l10nT('nav_chats', 'en'), 'Chats');
      expect(l10nT('nav_chats', 'ar'), 'المحادثات');
    });

    test('مفتاح غائب عن الكتالوج كله يعود باسمه — لا فراغات أبداً', () {
      expect(l10nT('not_a_real_key', 'ar'), 'not_a_real_key');
      expect(l10nT('not_a_real_key', 'en'), 'not_a_real_key');
    });

    test('لغة غير مدعومة تهبط للعربية', () {
      expect(l10nT('act_cancel', 'xx'), 'إلغاء');
    });
  });

  group('الاتجاه واللغات', () {
    test('العربية فقط يمين-لليسار وen/fr يساران', () {
      expect(l10nIsRtl('ar'), isTrue);
      expect(l10nIsRtl('en'), isFalse);
      expect(l10nIsRtl('fr'), isFalse);
      expect(l10nIsRtl('xx'), isFalse);
    });

    test('اللغات المدعومة مرتبة والعربية أولاً دائماً', () {
      expect(l10nSupported.first, 'ar');
      expect(l10nSupported, ['ar', 'en', 'fr']);
    });
  });

  group('توسعة 2.0.0 — الأسطح الجديدة كاملة الثلاثة', () {
    test('مفاتيح الدعوة الجديدة تترجم في اللغات الثلاث', () {
      expect(l10nT('invite_join_button', 'en'),
          'Join a group with an invite code');
      expect(l10nT('invite_join_button', 'fr'),
          'Rejoindre un groupe par code d’invitation');
      expect(l10nT('invite_invalid', 'ar'), 'الرمز غير صالح — تأكد من نسخه كاملاً');
    });

    test('أفعال الرسائل والمجتمعات مكتملة', () {
      for (final k in [
        'chat_attach', 'act_reply', 'act_forward', 'act_copy',
        'comm_create', 'ch_discover', 'sec_lock_app', 'gen_offline',
      ]) {
        expect(l10nComplete(k), isTrue, reason: k);
      }
    });
  });
}
