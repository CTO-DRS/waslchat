/// اختبارات كتالوج البوتات — خدمة التطبيق (1.21.0): نطاق التركيب الصادق
/// (المجتمعات حصراً والمشفرة مرفوضة)، الحدود المعلنة، التكرار، صيغة
/// الواجهة للاسم، التعطيل يقطع الرندر، والرندر الحتمي.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/bot_catalog_service.dart';

CatalogBotManifest _manifest(
        {String username = 'helper_bot',
        List<CatalogTemplate>? templates}) =>
    CatalogBotManifest(
      username: username,
      displayName: 'المساعد',
      templates: templates ??
          [const CatalogTemplate.welcome(['أهلاً {name}', 'كيف أساعدك؟'])],
    );

void main() {
  group('نطاق التركيب الصادق', () {
    test('تركيب في نطاق مجتمع: ناجح بالنموذج المعتمد', () {
      final out = BotCatalogService.install(
        isCommunityScope: true,
        installedCount: 0,
        alreadyInstalled: false,
        manifest: _manifest(),
      );
      expect(out.isOk, isTrue, reason: out.reasons.toString());
      expect(out.value.username, 'helper_bot');
      expect(out.value.enabled, isTrue);
    });

    test('تركيب في غرفة مشفرة طرف-لطرف: رفض صادق بالسبب الموثق', () {
      final out = BotCatalogService.install(
        isCommunityScope: false,
        installedCount: 0,
        alreadyInstalled: false,
        manifest: _manifest(),
      );
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('لا يفكه البوت أصلاً'));
    });

    test('الحد 3: الرابع مرفوض والسبب معلن بالرقمين', () {
      final out = BotCatalogService.install(
        isCommunityScope: true,
        installedCount: 3,
        alreadyInstalled: false,
        manifest: _manifest(),
      );
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('3 بلغ الحد 3'));
    });

    test('التكرار مرفوض', () {
      final out = BotCatalogService.install(
        isCommunityScope: true,
        installedCount: 0,
        alreadyInstalled: true,
        manifest: _manifest(),
      );
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('مركّب في هذه الغرفة أصلاً'));
    });

    test('اسم بلا _bot وقوالب فارغة — أسباب تجمع لا أولها', () {
      final out = BotCatalogService.install(
        isCommunityScope: false,
        installedCount: 9,
        alreadyInstalled: false,
        manifest: _manifest(username: 'helper', templates: []),
      );
      expect(out.isRefused, isTrue);
      expect(out.reasons.length, greaterThanOrEqualTo(4),
          reason: 'النطاق والحد والصيغة والقوالب الأربعة معاً');
      expect(out.reasons.any((r) => r.contains('_bot')), isTrue);
      expect(out.reasons.any((r) => r.contains('عدد القوالب')), isTrue);
    });
  });

  group('الإزالة والتعطيل', () {
    test('إزالة مركّب تنجح وغير المركّب ترفض', () {
      final bot = InstalledCatalogBot(
          username: 'helper_bot', displayName: 'المساعد', templates: []);
      final ok = BotCatalogService.remove(
          installed: [bot], username: 'helper_bot');
      expect(ok.isOk, isTrue);
      final no = BotCatalogService.remove(
          installed: [], username: 'helper_bot');
      expect(no.isRefused, isTrue);
      expect(no.reasons.first, contains('ليس مركّباً'));
    });

    test('تعطيل يقطع الرندر صادقاً — الصمت لا قائمة ميتة', () {
      final bot = InstalledCatalogBot(
        username: 'helper_bot',
        displayName: 'المساعد',
        templates: [const CatalogTemplate.welcome(['أهلاً {name}'])],
      );
      BotCatalogService.setEnabled(bot: bot, enabled: false);
      final out = BotCatalogService.renderWelcome(
          bot: bot, recipientName: 'أحمد');
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('معطّل'));
    });
  });

  group('الرندر الحتمي', () {
    test('قالب الترحيب يرندر {name} حتمياً', () {
      final bot = InstalledCatalogBot(
        username: 'helper_bot',
        displayName: 'المساعد',
        templates: [const CatalogTemplate.welcome(['أهلاً {name}', 'كيف أساعدك؟'])],
      );
      final out = BotCatalogService.renderWelcome(
          bot: bot, recipientName: 'أحمد');
      expect(out.isOk, isTrue);
      expect(out.value, 'أهلاً أحمد\nكيف أساعدك؟');
      // حتمية: نفس المدخلات نفس النص
      expect(
          BotCatalogService.renderWelcome(bot: bot, recipientName: 'أحمد')
              .value,
          out.value);
    });

    test('بوت بلا قالب ترحيب يرفض بصراحة', () {
      final bot = InstalledCatalogBot(
        username: 'poll_bot',
        displayName: 'استفتاء',
        templates: [const CatalogTemplate.suggestions(['أ', 'ب', 'ج'])],
      );
      final out = BotCatalogService.renderWelcome(
          bot: bot, recipientName: 'س');
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('بلا قالب ترحيب'));
    });
  });
}
