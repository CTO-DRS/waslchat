/// كتالوج البوتات المجتمعية — خدمة التطبيق (1.21.0): قواعد نقية بلا شبكة
/// ولا واجهة — تُختبَر حصرياً في `bot_catalog_service_test.dart`.
/// (نسخة التطبيق من جوهر المحرك النقي الثالث عشر `engines/wasl_bots`
/// وفق عادة المحركات — المحركات لقطات مجمّدة من كود التطبيق لا العكس.)
///
/// القواعد الصادقة (موثقة من عقد البوتات القائم E2EE_PLAN §8-و):
/// - **نطاق التركيب**: قنوات المجتمعات وغرفها حصراً (محتواها صريح
///   بالتصميم) — الغرفة الجماعية المشفرة طرف-لطرف مرفوضة صادقاً لأن
///   البوت يقرأ نصاً مشفراً لا يفكه أبداً (لا يملك المفاتيح).
/// - **لا صلاحية جديدة**: حد معلن 3 بوتات كتالوج لكل غرفة، والتكرار
///   مرفوض، والبيان يجب أن يجتاز فحص الصيغة كاملاً.
/// - **التعطيل يقطع الرندر**: البوت المعطّل لا يولّد نصاً — الصمت صادق
///   لا قائمة ميتة تتصرف.
/// - الفشل يعيد أسبابه مجمعة لا أولها — بلا استثناءات مسربة.
library;

// ————— نسخة التطبيق من أنواع المحرك النقي —————

enum CatalogTemplateType { welcome, attendance, suggestions }

/// قالب جاهز — كل نوع بحقله وحدوده المعلنة نفسها في المحرك.
class CatalogTemplate {
  const CatalogTemplate.welcome(this.messages)
      : type = CatalogTemplateType.welcome,
        sessions = const [],
        prompts = const [];

  const CatalogTemplate.attendance(this.sessions)
      : type = CatalogTemplateType.attendance,
        messages = const [],
        prompts = const [];

  const CatalogTemplate.suggestions(this.prompts)
      : type = CatalogTemplateType.suggestions,
        messages = const [],
        sessions = const [];

  final CatalogTemplateType type;
  final List<String> messages;
  final List<(String, String)> sessions;
  final List<String> prompts;

  /// حدود القالب — نفس أرقام المحرك حرفياً.
  List<String> validate() {
    final reasons = <String>[];
    switch (type) {
      case CatalogTemplateType.welcome:
        if (messages.isEmpty || messages.length > 3) {
          reasons.add('قوالب الترحيب من 1 إلى 3 رسائل لا ${messages.length}');
        }
        for (final m in messages) {
          if (m.trim().isEmpty || m.length > 200) {
            reasons.add('رسالة ترحيب فارغة أو أطول من 200 حرف');
          }
        }
      case CatalogTemplateType.attendance:
        if (sessions.isEmpty || sessions.length > 2) {
          reasons.add('قوالب الحضور من 1 إلى 2 جلسة لا ${sessions.length}');
        }
        final time = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
        for (final (start, end) in sessions) {
          if (!time.hasMatch(start) || !time.hasMatch(end)) {
            reasons.add('أوقات الحضور يجب أن تكون HH:mm صحيحة');
          } else if (start.compareTo(end) >= 0) {
            reasons.add('بداية جلسة الحضور يجب أن تسبق نهايتها');
          }
        }
      case CatalogTemplateType.suggestions:
        if (prompts.length < 3 || prompts.length > 5) {
          reasons.add('قوالب الاقتراحات من 3 إلى 5 عناصر لا ${prompts.length}');
        }
        for (final p in prompts) {
          if (p.trim().isEmpty || p.length > 80) {
            reasons.add('اقتراح فارغ أو أطول من 80 حرفاً');
          }
        }
    }
    return reasons;
  }

  String? renderWelcome(String recipientName) =>
      type == CatalogTemplateType.welcome
          ? messages
              .map((m) => m.replaceAll('{name}', recipientName))
              .join('\n')
          : null;

  /// رندر الحضور — نفس شكل المحرك النقي حرفياً
  String? renderAttendance() => type == CatalogTemplateType.attendance
      ? sessions.map((s) => 'الحضور: ${s.$1}–${s.$2}').join(' ، ')
      : null;

  /// رندر الاقتراحات — نفس شكل المحرك النقي حرفياً
  List<String>? renderSuggestions() => type == CatalogTemplateType.suggestions
      ? List<String>.from(prompts)
      : null;
}

/// بيان بوت كتالوج — نسخة التطبيق من بيان المحرك (بلا JSON: الواجهة
/// تمرر القوالب المفكولة، والتحقق النصي في المحرك).
class CatalogBotManifest {
  CatalogBotManifest({
    required this.username,
    required this.displayName,
    required this.templates,
  });

  final String username;
  final String displayName;
  final List<CatalogTemplate> templates;

  static final RegExp usernameFormat = RegExp(r'^[a-z0-9_]{4,20}_bot$');

  /// نفس قواعد المحرك: الاسم بصيغة الواجهة القائمة والقوالب ضمن الحدود.
  List<String> validate() {
    final reasons = <String>[];
    if (!usernameFormat.hasMatch(username)) {
      reasons.add('الاسم البرمجي يجب أن ينتهي بـ_bot ويلتزم صيغة الواجهة: '
          '$username');
    }
    if (displayName.trim().isEmpty || displayName.length > 40) {
      reasons.add('اسم العرض فارغ أو أطول من 40 حرفاً');
    }
    if (templates.isEmpty || templates.length > 3) {
      reasons.add('عدد القوالب من 1 إلى 3 لا ${templates.length}');
    }
    final types = templates.map((t) => t.type).toSet();
    if (types.length != templates.length) {
      reasons.add('نوع قالب مكرر في نفس البيان');
    }
    for (final t in templates) {
      reasons.addAll(t.validate());
    }
    return reasons;
  }
}

// ————— الخدمة —————

/// بوت كتالوج مركّب في غرفة — نسخة معتمدة من البيان.
class InstalledCatalogBot {
  InstalledCatalogBot({
    required this.username,
    required this.displayName,
    required this.templates,
    this.enabled = true,
  });

  final String username;
  final String displayName;
  final List<CatalogTemplate> templates;
  bool enabled;
}

/// محصلة أي قاعدة — إما قيمة أو أسباب مجمعة (نمط الألبومات المشتركة).
class CatalogOutcome<T> {
  CatalogOutcome.ok(T this._value) : _reasons = const [];
  CatalogOutcome.refused(this._reasons) : _value = null;

  final T? _value;
  final List<String> _reasons;

  bool get isOk => _value != null;
  bool get isRefused => _reasons.isNotEmpty;
  T get value => _value as T;
  List<String> get reasons => _reasons;
}

class BotCatalogService {
  BotCatalogService._();

  /// الحد المعلن قبل التركيب — أرقام لا وعود
  static const int maxCatalogBotsPerConversation = 3;

  /// تركيب بوت كتالوج في غرفة — كل الشروط تفحص والأسباب تجمع لا أولها
  static CatalogOutcome<InstalledCatalogBot> install({
    required bool isCommunityScope,
    required int installedCount,
    required bool alreadyInstalled,
    required CatalogBotManifest manifest,
  }) {
    final reasons = <String>[];
    if (!isCommunityScope) {
      reasons.add('بوتات الكتالوج في قنوات المجتمعات وغرفها حصراً — '
          'الغرفة المشفرة طرف-لطرف نصها لا يفكه البوت أصلاً');
    }
    if (installedCount >= maxCatalogBotsPerConversation) {
      reasons.add('عدد بوتات الكتالوج $installedCount بلغ الحد '
          '$maxCatalogBotsPerConversation');
    }
    if (alreadyInstalled) {
      reasons.add('البوت مركّب في هذه الغرفة أصلاً — بلا تكرار');
    }
    reasons.addAll(manifest.validate());
    if (reasons.isNotEmpty) return CatalogOutcome.refused(reasons);
    return CatalogOutcome.ok(InstalledCatalogBot(
      username: manifest.username,
      displayName: manifest.displayName,
      templates: manifest.templates,
    ));
  }

  /// إزالة تركيب — دائماً ممكنة لمن يملك الغرفة (بلا صلاحية جديدة)
  static CatalogOutcome<bool> remove({
    required List<InstalledCatalogBot> installed,
    required String username,
  }) {
    final idx = installed.indexWhere((b) => b.username == username);
    if (idx < 0) {
      return CatalogOutcome.refused(['البوت ليس مركّباً في هذه الغرفة']);
    }
    return CatalogOutcome.ok(true);
  }

  /// تعطيل أو تفعيل — الحالة صادقة بالنتيجة
  static CatalogOutcome<bool> setEnabled({
    required InstalledCatalogBot bot,
    required bool enabled,
  }) {
    bot.enabled = enabled;
    return CatalogOutcome.ok(enabled);
  }

  /// رندر قالب الترحيب — المعطّل صامت لا نص من ميت
  static CatalogOutcome<String> renderWelcome({
    required InstalledCatalogBot bot,
    required String recipientName,
  }) {
    if (!bot.enabled) {
      return CatalogOutcome.refused(['البوت معطّل — لا رندر']);
    }
    final t = bot.templates
        .where((t) => t.type == CatalogTemplateType.welcome)
        .toList();
    if (t.isEmpty) {
      return CatalogOutcome.refused(['البوت بلا قالب ترحيب']);
    }
    final text = t.first.renderWelcome(recipientName);
    if (text == null || text.trim().isEmpty) {
      return CatalogOutcome.refused(['قالب الترحيب فارغ']);
    }
    return CatalogOutcome.ok(text);
  }
}
