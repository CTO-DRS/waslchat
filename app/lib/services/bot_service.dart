import '../config.dart';

/// البوتات وواجهة المطوّرين (المرحلة 4).
///
/// كل بوت مستخدم auth حقيقي فصار عضواً عادياً في المحادثات بصلاحيات RLS
/// نفسها. رمز الواجهة `wasl_…` يظهر مرة واحدة عند الإنشاء/التجديد ويُخزَّن
/// مُجزّأً SHA-256 في الخادم. الويب هوك يُوقَّع HMAC-SHA256 بسرّ مستقل
/// يقرؤه المالك من شاشة البوتات.
///
/// حدود صادقة (موثقة في E2EE_PLAN §8-و):
/// - المحادثات مع البوتات مباشرةً غير مشفرة طرف-لطرف — البوت يقرأ نصها عبر
///   واجهته، فلا نزوّر وعداً لا يمكن الوفاء به.
/// - في المجموعات الخاصة المشفرة يصل الويب هوك نصاً مشفراً لا يفكه البوت
///   أبداً (لا يملك مفاتيح) — البوتات تعمل فعلياً في القنوات وغرف المجتمعات
///   (محتواها صريح بالتصميم).
class BotService {
  BotService._();

  /// الحد الأقصى لعدد البوتات لكل مالك (خطة مجانية — حد معلن)
  static const maxPerOwner = 10;

  /// حد الإغراق في الواجهة البرمجية (رسالة/دقيقة لكل بوت) — يفرضه الخادم
  static const rateLimitPerMinute = 20;

  /// اسم مستخدم البوت: مثل أسماء المستخدمين + لا بد أن ينتهي بـ_bot
  static final RegExp usernameFormat = RegExp(r'^[a-z0-9_]{4,20}_bot$');

  static final RegExp tokenFormat = RegExp(r'^wasl_[0-9a-f]{48}$');
  static final RegExp webhookFormat = RegExp(r'^https?://\S+$');

  static String normalizeUsername(String raw) {
    var u = raw.trim().toLowerCase();
    if (u.startsWith('@')) u = u.substring(1);
    return u.replaceAll(RegExp('[^a-z0-9_]'), '_');
  }

  /// الصيغة كما يقبلها الخادم حرفياً في bot_create (ترحيل 025):
  /// lower + trim + إسقاط @ من البداية — بلا استبدال للأحرف (المسافة تُرفض)
  static String serverForm(String raw) {
    var u = raw.trim().toLowerCase();
    if (u.startsWith('@')) u = u.substring(1);
    return u;
  }

  /// رسالة خطأ عربية لاسم البوت، أو null إن سليم
  /// (تُطابق قرار الخادم في bot_create: يطبّع الحالة ثم يفحص الصيغة —
  /// فالمسافات والرموز تُرفض وليست تُستبدل، والحروف الكبيرة تُطبَّع وتُقبل)
  static String? usernameError(String raw) {
    final u = serverForm(raw);
    if (!u.endsWith('_bot')) return 'اسم البوت يجب أن ينتهي بـ_bot';
    if (!usernameFormat.hasMatch(u)) {
      return '4–20 حرفاً إنجليزياً صغيراً ورقماً وشرطة سفلية، وينتهي بـ_bot';
    }
    return null;
  }

  /// رسالة خطأ عربية لرابط الويب هوك، أو null إن سليماً (أو فارغاً)
  static String? webhookError(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return null;
    if (!webhookFormat.hasMatch(u)) return 'الرابط يجب أن يبدأ بـ http:// أو https://';
    return null;
  }

  static bool isValidToken(String t) => tokenFormat.hasMatch(t);

  // ---------- استدعاءات الخادم ----------

  static Future<List<Map<String, dynamic>>> list() async {
    final data = await supabase.rpc('my_bots');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// إنشاء بوت — يعيد (معرّف البوت، رمز الواجهة الذي يظهر مرة واحدة)
  static Future<(String, String)> create({
    required String name,
    required String username,
    String? description,
    String? webhookUrl,
  }) async {
    final r = await supabase.rpc('bot_create', params: {
      'p_name': name.trim(),
      'p_username': normalizeUsername(username),
      'p_description': (description ?? '').trim().isEmpty
          ? null
          : description!.trim(),
      'p_webhook_url': (webhookUrl ?? '').trim().isEmpty
          ? null
          : webhookUrl!.trim(),
    });
    final rows = List<Map<String, dynamic>>.from(r as List);
    if (rows.isEmpty) throw StateError('bot_create: empty');
    return (rows.first['bot_id'] as String, rows.first['token'] as String);
  }

  /// تجديد رمز الواجهة — يعيد الرمز الجديد (يظهر مرة واحدة)
  static Future<String> resetToken(String botId) async {
    return await supabase.rpc('bot_token_reset', params: {'p_bot': botId}) as String;
  }

  /// ضبط رابط الويب هوك (نص فارغ = مسح). يعيد السر الجديد عند الضبط أو null.
  static Future<String?> setWebhook(String botId, String url) async {
    return await supabase.rpc('bot_set_webhook',
        params: {'p_bot': botId, 'p_url': url.trim()}) as String?;
  }

  static Future<void> setActive(String botId, bool on) async {
    await supabase.rpc('bot_set_active', params: {'p_bot': botId, 'p_on': on});
  }

  /// حذف البوت نهائياً مع رسائله وعضوياته (حذف متسلسل من الخادم)
  static Future<void> remove(String botId) async {
    await supabase.rpc('bot_delete', params: {'p_bot': botId});
  }

  /// إضافة البوت إلى محادثة جماعية/قناة أنت مشرفها
  static Future<void> addToChat(String botId, String convId) async {
    await supabase.rpc('bot_add_to_chat',
        params: {'p_bot': botId, 'p_conv': convId});
  }

  static Future<void> removeFromChat(String botId, String convId) async {
    await supabase.rpc('bot_remove_from_chat',
        params: {'p_bot': botId, 'p_conv': convId});
  }

  /// بدء محادثة مباشرة مع البوت (تُفتح غير مشفرة — بصدق)
  static Future<String> startChat(String botId) async {
    return await supabase.rpc('bot_start_chat', params: {'p_bot': botId}) as String;
  }

  /// محادثات البوت (للمالك)
  static Future<List<Map<String, dynamic>>> chats(String botId) async {
    final data = await supabase.rpc('bot_chats', params: {'p_bot': botId});
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// إحصاءات البوت لصاحبه (المرحلة 15 ج — 1.7.0، ترحيل 039): ما يمكن قراءته
  /// فعلاً من الجداول القائمة — رسائل ونشاط ووصول ومقترحات — بلا تخزين جديد
  static Future<BotStats> stats(String botId) async {
    final r = await supabase.rpc('bot_stats', params: {'p_bot': botId});
    return BotStats.fromRow(Map<String, dynamic>.from(r as Map));
  }

  /// ترجمة أخطاء الخادم إلى عربية
  static String errorLabel(Object e) {
    final s = e.toString();
    if (s.contains('bot limit')) {
      return 'الحد الأقصى $maxPerOwner بوتات لكل حساب';
    }
    if (s.contains('bad bot username')) {
      return 'اسم البوت غير صالح — إنجليزي صغير وأرقام وشرطة سفلية وينتهي بـ_bot';
    }
    if (s.contains('bad name')) return 'اكتب اسم البوت (حتى 60 حرفاً)';
    if (s.contains('bad description')) return 'الوصف طويل — حتى 300 حرف';
    if (s.contains('bad webhook url')) {
      return 'رابط الويب هوك يجب أن يبدأ بـ http:// أو https://';
    }
    if (s.contains('username taken')) return 'هذا الاسم محجوز أو مستخدم';
    if (s.contains('not your bot')) return 'هذا ليس بوتك';
    if (s.contains('admins only')) return 'إضافة البوت لمشرفي المحادثة فقط';
    if (s.contains('use bot_start_chat')) {
      return 'البوت يُضاف للمجموعات — للمحادثة المباشرة اضغط «محادثة البوت»';
    }
    if (s.contains('not allowed')) return 'لا يمكن إضافة بوت لسحابتك الشخصية';
    if (s.contains('bot not found')) return 'البوت غير موجود أو معطّل';
    if (s.contains('not found')) return 'غير موجود';
    return 'تعذّر تنفيذ العملية';
  }
}

/// لوحة إحصاءات البوت النقية (المرحلة 12 ب — 0.29.0 وتوسعة المرحلة 15 ج — 1.7.0):
/// تعرض صاحب البوت ما يمكن قراءته فعلاً عن بوتيه — الحالة والويب هوك
/// والمحادثات المرتبطة وعمر البوت، ومع ترحيل 039: الرسائل المرسلة ونشاط
/// آخر 24 ساعة والوصول المقاس وحالة المقترحات — بإفصاح صادق بلا اختراع.
class BotStatsView {
  BotStatsView._();

  /// عمر البوت بنص عربي مختصر: «اليوم»، «قبل 5 أيام»، «قبل 3 أسابيع»، «قبل 4 أشهر»
  static String ageText(String? iso, DateTime now) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    final days = now.difference(d).inDays;
    if (days <= 0) return 'اليوم';
    if (days == 1) return 'قبل يوم';
    if (days < 7) return 'قبل $days أيام';
    final weeks = days ~/ 7;
    if (weeks < 5) {
      return weeks == 1 ? 'قبل أسبوع' : 'قبل $weeks أسابيع';
    }
    final months = days ~/ 30;
    if (months < 12) {
      return months == 1 ? 'قبل شهر' : 'قبل $months أشهر';
    }
    final years = days ~/ 365;
    return years == 1 ? 'قبل سنة' : 'قبل $years سنوات';
  }

  /// سطر حالة الويب هوك الصادق
  static String webhookLabel(Map<String, dynamic> bot) {
    final url = (bot['webhook_url'] ?? '') as String;
    return url.isEmpty
        ? 'غير موصول — الرسائل لا تُرسل لأي خادم'
        : 'موصول — تصله الرسائل موقّعة HMAC';
  }

  /// سطر عدد المحادثات المرتبطة — صادق بالأعداد
  static String chatCountLabel(int chats) {
    if (chats == 0) return 'لا محادثات مرتبطة بعد';
    if (chats == 1) return 'محادثة واحدة مرتبطة';
    return '$chats محادثات مرتبطة';
  }

  /// إفصاح اللوحة الثابت — يظهر كما هو في الشاشة
  static const disclosure =
      'هذه اللوحة تعرض ما يمكن قراءته فعلاً عن بوتك من الخادم — بلا تخمين ولا أرقام مكتوظة: '
      'الرسائل المرسلة والنشاط الأخير والوصول المقاس وحالة المقترحات من ترحيل 039، '
      'ورموز ردود الويب هوك تفصلها بيئة بوتك نفسها ولا يراها الخادم.';
}

/// إحصاءات البوت كما تعود من `bot_stats` (ترحيل 039) — تحليل دفاعي:
/// أي غرابة أو حقل ناقص يهبط صفراً صادقاً لا رقماً مكتوظاً
class BotStats {
  const BotStats({
    required this.totalMessages,
    required this.messages24h,
    required this.lastMessageAtIso,
    required this.conversations,
    required this.membersReached,
    required this.proposalsPending,
    required this.proposalsApproved,
    required this.proposalsRejected,
  });

  final int totalMessages;
  final int messages24h;
  final String lastMessageAtIso;
  final int conversations;
  final int membersReached;
  final int proposalsPending;
  final int proposalsApproved;
  final int proposalsRejected;

  static int _int(Object? v) => (v is num && v >= 0) ? v.toInt() : 0;

  factory BotStats.fromRow(Map<String, dynamic> r) => BotStats(
        totalMessages: _int(r['total_messages']),
        messages24h: _int(r['messages_24h']),
        lastMessageAtIso: (r['last_message_at'] as String?) ?? '',
        conversations: _int(r['conversations']),
        membersReached: _int(r['members_reached']),
        proposalsPending: _int(r['proposals_pending']),
        proposalsApproved: _int(r['proposals_approved']),
        proposalsRejected: _int(r['proposals_rejected']),
      );

  /// آخر نشاط بنص عربي مختصر — غياب النشاط يعلن بصدق
  static String lastActivity(String iso, DateTime now) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return 'لا نشاط مسجل بعد';
    final mins = now.difference(d).inMinutes;
    if (mins < 1) return 'الآن';
    if (mins < 60) return 'قبل $mins دقيقة';
    final hours = mins ~/ 60;
    if (hours < 24) return 'قبل $hours ساعة';
    final days = hours ~/ 24;
    return days == 1 ? 'قبل يوم' : 'قبل $days أيام';
  }

  /// سطر الوصول المقاس — مجموع أعضاء محادثات البوت (تقدير صادق معلن)
  static String reachLabel(int n) {
    if (n <= 0) return 'لا وصول بعد';
    return '$n عضواً عبر محادثات بوتك (مجموع الأعضاء — قد يتكرر بين الغرف)';
  }

  /// سطر المقترحات الثلاثة الصادق
  static String proposalsLabel(BotStats s) {
    if (s.proposalsPending == 0 &&
        s.proposalsApproved == 0 &&
        s.proposalsRejected == 0) {
      return 'لا مقترحات بعد — بوتك يرصد ولا يقترح بعد';
    }
    return 'معلقة ${s.proposalsPending} · منفذة ${s.proposalsApproved} · مرفوضة ${s.proposalsRejected}';
  }
}
