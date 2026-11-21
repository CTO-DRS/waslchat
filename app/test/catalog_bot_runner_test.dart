/// اختبارات عدّاء قوالب البوتات (1.22.0): أوامر الغرفة الثلاثة، المطابقة
/// الحصرية للنص الكامل، المعطّل صامت، البوت بلا قالب النوع يسقط، تعدد
/// البوتات بترتيبها، والإسناد الصادق في بادئة المسودة.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/bot_catalog_service.dart';
import 'package:wasl_chat/services/catalog_bot_runner.dart';

InstalledCatalogBot _bot({
  String name = 'المساعد',
  String username = 'helper_bot',
  bool enabled = true,
  List<CatalogTemplate> templates = const [
    CatalogTemplate.welcome(['أهلاً {name}!', 'كيف أساعدك؟'])
  ],
}) =>
    InstalledCatalogBot(
        username: username, displayName: name, templates: templates, enabled: enabled);

void main() {
  group('أوامر الغرفة الثلاثة — مطابقة النص الكامل حصراً', () {
    test('«ترحيب» يرندر قالب الترحيب بالاسم الموثق', () {
      final drafts = CatalogBotRunner.respond(message: 'ترحيب', bots: [_bot()]);
      expect(drafts, hasLength(1));
      expect(drafts.first.command, 'ترحيب');
      expect(drafts.first.text, 'أهلاً العضو!\nكيف أساعدك؟');
    });

    test('«حضور» و«اقتراحات» يرندران قوالب نوعيهما', () {
      final att = _bot(
          name: 'المنسق',
          username: 'attends_bot',
          templates: [const CatalogTemplate.attendance([('20:00', '21:30')])]);
      final d1 = CatalogBotRunner.respond(message: 'حضور', bots: [att]);
      expect(d1.single.text, 'الحضور: 20:00–21:30');

      final sug = _bot(
          name: 'الملهم',
          username: 'ideas_bot',
          templates: [
            const CatalogTemplate.suggestions(['فكرة أولى', 'فكرة ثانية', 'فكرة ثالثة'])
          ]);
      final d2 = CatalogBotRunner.respond(message: 'اقتراحات', bots: [sug]);
      expect(d2.single.text, contains('• فكرة أولى'));
      expect(d2.single.text, contains('• فكرة ثالثة'));
    });

    test('النص الطويل ليس أمراً — لا ذكاء مزعوم ولا توليد', () {
      expect(
          CatalogBotRunner.respond(
              message: 'مرحبا يا شباب كيف الحال', bots: [_bot()]),
          isEmpty);
      expect(CatalogBotRunner.respond(message: 'ترحيب بالأعضاء', bots: [_bot()]),
          isEmpty);
      expect(CatalogBotRunner.respond(message: '', bots: [_bot()]), isEmpty);
    });

    test('المسافات المحيطة لا تكسر الأمر — القص قبل المطابقة', () {
      final drafts = CatalogBotRunner.respond(message: '  ترحيب  ', bots: [_bot()]);
      expect(drafts, hasLength(1));
    });
  });

  group('الصمت الصادق', () {
    test('المعطّل لا مسودات منه', () {
      final drafts = CatalogBotRunner.respond(
          message: 'ترحيب', bots: [_bot(enabled: false)]);
      expect(drafts, isEmpty);
    });

    test('بوت بلا قالب من نوع الأمر يسقط — بلا مسودات فارغة', () {
      final sug = _bot(username: 'ideas_bot', templates: [
        const CatalogTemplate.suggestions(['أ', 'ب', 'ج'])
      ]);
      expect(CatalogBotRunner.respond(message: 'ترحيب', bots: [sug]), isEmpty);
    });
  });

  group('تعدد البوتات والإسناد', () {
    test('بوتان مركبان: مسودتان بترتيب التركيب', () {
      final drafts = CatalogBotRunner.respond(message: 'ترحيب', bots: [
        _bot(name: 'الأول', username: 'first_bot'),
        _bot(name: 'الثاني', username: 'second_bot'),
      ]);
      expect(drafts.map((d) => d.username), ['first_bot', 'second_bot']);
    });

    test('بادئة المسودة تحمل اسم البوت واسمه البرمجي — الإسناد الصادق', () {
      final d = CatalogBotRunner.draftText(
          const BotDraft(
              botName: 'المساعد',
              username: 'helper_bot',
              command: 'ترحيب',
              text: 'أهلاً'));
      expect(d, startsWith('🤖 المساعد (helper_bot):'));
      expect(d, contains('أهلاً'));
    });
  });
}
