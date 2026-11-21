/// اختبارات مخزن بوتات الكتالوج (1.22.0): دورة التسلسل الكامل (نفس
/// أشكال الكتالوج الموثق)، حدود الخدمة نفسها (3 لكل غرفة والتكرار
/// مرفوض)، الإزالة الصادقة، والـJSON الفاسد يبدأ فارغاً بلا انفجار.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_chat/services/catalog_bot_store.dart';

import 'package:wasl_chat/services/bot_catalog_service.dart';

const String _k = 'wasl_catalog_bots_v1';

InstalledCatalogBot _bot(String username, {List<CatalogTemplate>? templates}) =>
    InstalledCatalogBot(
      username: username,
      displayName: 'بوت $username',
      templates: templates ??
          [const CatalogTemplate.welcome(['أهلاً {name}'])],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('التثبيت والاسترجاع', () {
    test('دورة كاملة: أضف ثم استرجع لغرفته حصراً', () async {
      final out = await CatalogBotStore.add('room1', _bot('helper_bot'));
      expect(out.isOk, isTrue, reason: out.reasons.toString());
      final bots = await CatalogBotStore.forConversation('room1');
      expect(bots.single.username, 'helper_bot');
      expect(bots.single.enabled, isTrue);
      expect(await CatalogBotStore.forConversation('room2'), isEmpty,
          reason: 'التثبيت لكل غرفة حصراً');
    });

    test('دورة قوالب كاملة: الأنواع الثلاثة تحفظ حقولها حرفياً', () async {
      final bot = _bot('full_bot', templates: const [
        CatalogTemplate.welcome(['أهلاً {name}!', 'كيف أساعدك؟']),
        CatalogTemplate.attendance([('20:00', '21:30'), ('08:00', '09:00')]),
        CatalogTemplate.suggestions(['أ', 'ب', 'ج', 'د']),
      ]);
      await CatalogBotStore.add('room1', bot);
      final back = (await CatalogBotStore.forConversation('room1')).single;
      final w = back.templates[0];
      expect(w.messages, ['أهلاً {name}!', 'كيف أساعدك؟']);
      final a = back.templates[1];
      expect(a.sessions, [('20:00', '21:30'), ('08:00', '09:00')]);
      final s = back.templates[2];
      expect(s.prompts, ['أ', 'ب', 'ج', 'د']);
    });

    test('حدود الخدمة نفسها: 3 لكل غرفة والرابع مرفوض', () async {
      await CatalogBotStore.add('room1', _bot('a_bot'));
      await CatalogBotStore.add('room1', _bot('b_bot'));
      await CatalogBotStore.add('room1', _bot('c_bot'));
      final out = await CatalogBotStore.add('room1', _bot('d_bot'));
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('بلغ الحد 3'));
    });

    test('التكرار مرفوض بنفس الغرفة — وحر في غيرها', () async {
      await CatalogBotStore.add('room1', _bot('helper_bot'));
      final dup = await CatalogBotStore.add('room1', _bot('helper_bot'));
      expect(dup.isRefused, isTrue);
      expect(dup.reasons.first, contains('بلا تكرار'));
      final other = await CatalogBotStore.add('room2', _bot('helper_bot'));
      expect(other.isOk, isTrue);
    });

    test('الإزالة الصادقة: يزيل الموجود ويرفض الغائب', () async {
      await CatalogBotStore.add('room1', _bot('helper_bot'));
      expect(await CatalogBotStore.remove('room1', 'helper_bot'), isTrue);
      expect(await CatalogBotStore.forConversation('room1'), isEmpty);
      expect(await CatalogBotStore.remove('room1', 'helper_bot'), isFalse);
      // وإعادة التركيب بعد الإزالة ممكنة
      expect((await CatalogBotStore.add('room1', _bot('helper_bot'))).isOk,
          isTrue);
    });
  });

  group('الفشل الصادق', () {
    test('JSON فاسد يبدأ فارغاً بلا انفجار', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{_k: '{not json'});
      final all = await CatalogBotStore.loadAll();
      expect(all, isEmpty);
    });

    test('مدخل غريب في القائمة يُسقط والسليم يبقى', () async {
      final good = {
        'username': 'helper_bot',
        'displayName': 'المساعد',
        'enabled': true,
        'templates': [
          {'type': 'welcome', 'messages': ['أهلاً {name}']}
        ],
      };
      // مدخلان: واحد سليم وواحد قيمه أرقام لا نصوص (JSON حقيقي لا toString)
      final raw =
          '{"room1": [${json.encode(good)}, {"username": 42, "displayName": 7}]}';
      SharedPreferences.setMockInitialValues(<String, Object>{_k: raw});
      final bots = await CatalogBotStore.forConversation('room1');
      expect(bots, hasLength(1), reason: 'الفاسد يُسقط والسليم يبقى');
      expect(bots.single.username, 'helper_bot');
    });
  });
}
