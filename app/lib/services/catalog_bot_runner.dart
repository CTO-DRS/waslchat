/// عدّاء قوالب البوتات (1.22.0) — الربط الحي الموثق لإصدار 1.21.0:
/// أوامر الغرفة الثلاثة («ترحيب» و«حضور» و«اقتراحات») تحوّل قوالب
/// بوتات الكتالوج المركبة إلى **مسودات جاهزة** يراجعها صاحب الغرفة
/// ويرسلها باسمه — بلا انتحال هوية بوت وبلا ذكاء مزعوم وبلا إرسال
/// تلقائي أبداً.
///
/// العقد الصادق:
/// 1. الأمر نص كامل واحد مطابق حصراً — «مرحبا يا شباب» ليس أمراً ولا
///    يولّد شيئاً: القوالب جاهزة موثقة لا مولدة.
/// 2. المعطّل صامت والبوت بلا قالب من نوع الأمر يسقط — بلا مسودات فارغة.
/// 3. الإسناد الصادق: كل مسودة تحمل اسم البوت واسمه البرمجي في بادئتها
///    عبر `draftText` — القارئ يعرف أنها قالب موثق يرسله صاحب الغرفة.
/// 4. نقية بلا شبكة ولا سياق — تُختبَر في VM مباشرة.
library;

import 'bot_catalog_service.dart';

/// مسودة رد جاهزة من بوت كتالوج مركب
class BotDraft {
  const BotDraft({
    required this.botName,
    required this.username,
    required this.command,
    required this.text,
  });

  final String botName;
  final String username;
  final String command;
  final String text;
}

class CatalogBotRunner {
  CatalogBotRunner._();

  /// أوامر الغرفة الثلاثة — نص كامل مطابق
  static const String welcomeCommand = 'ترحيب';
  static const String attendanceCommand = 'حضور';
  static const String suggestionsCommand = 'اقتراحات';

  /// الأوامر المدعومة لعرضها في الواجهة
  static const List<String> commands = [
    welcomeCommand,
    attendanceCommand,
    suggestionsCommand,
  ];

  /// حساب المسودات لأمر غرفة — فارغة صادقة إن لم يكن النص أمراً
  /// أو لا بوت مركب يملك قالباً من نوعه
  static List<BotDraft> respond({
    required String message,
    required List<InstalledCatalogBot> bots,
  }) {
    final t = message.trim();
    final type = switch (t) {
      welcomeCommand => CatalogTemplateType.welcome,
      attendanceCommand => CatalogTemplateType.attendance,
      suggestionsCommand => CatalogTemplateType.suggestions,
      _ => null,
    };
    if (type == null) return const [];
    final drafts = <BotDraft>[];
    for (final b in bots) {
      if (!b.enabled) continue;
      final tpl = b.templates.where((x) => x.type == type).toList();
      if (tpl.isEmpty) continue;
      final text = switch (type) {
        CatalogTemplateType.welcome => tpl.first.renderWelcome('العضو'),
        CatalogTemplateType.attendance => tpl.first.renderAttendance(),
        CatalogTemplateType.suggestions => tpl.first
            .renderSuggestions()
            ?.map((p) => '• $p')
            .join('\n'),
      };
      if (text == null || text.trim().isEmpty) continue;
      drafts.add(BotDraft(
        botName: b.displayName,
        username: b.username,
        command: t,
        text: text,
      ));
    }
    return drafts;
  }

  /// نص المسودة بإسناده الصادق — يُرسل باسم صاحب الغرفة والقارئ يعرف
  /// أن محتواه قالب موثق من البوت المسمى لا رأي شخصي مفاجئ
  static String draftText(BotDraft d) =>
      '🤖 ${d.botName} (${d.username}):\n${d.text}';
}
