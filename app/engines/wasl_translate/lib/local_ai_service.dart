/// وصل AI المحلي (المرحلة 5 — v0.14.0): محرّك خفيف يعمل **على الجهاز بالكامل**
/// بلا أي اتصال شبكي أو إرسال للخادم — يقدّم:
/// 1) الردود الذكية: تصنيف نية الرسالة الأخيرة من قاموس عربي مدمج (سلام، شكر،
///    سؤال موعد/مكان، دعوة، اعتذار…) واقتراح 3 ردود قصيرة جاهزة.
/// 2) الملخص المحلي: تلخيص استخلاصي (extractive) لأسطر محادثة — يرتّب الأسطر
///    بكثافة كلماتها المعنوية ويعيد أهمها بترتيبها الأصلي.
/// الصدق التصميمي: هذا محرّك إحصائي قواعدي خفيف (ليس نموذج لغة ضخماً) — لا يفهم
/// المعنى العميق، لكنه لا يغادر جهازك أبداً: كل ما يحدث هنا يحدث محلياً.
class LocalAiService {
  LocalAiService._();

  // ---------- التطبيع العربي (نفس روح wasl_norm_ar على الخادم) ----------
  static final RegExp _diacritics =
      RegExp('[\u064B-\u0652\u0670\u0640\u06D6-\u06ED]');

  /// تطبيع نص عربي للمطابقة: حذف التشكيل والتطويل، توحيد الألف والهمزات،
  /// الهاء المربوطة، الألف المقصورة، الواو والياء.
  static String normalize(String s) {
    var out = s.toLowerCase();
    out = out.replaceAll(_diacritics, '');
    out = out
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    return out;
  }

  /// هل النص أعلاه عربيّ الغالب؟ (نسبة الحروف العربية على الحروف)
  static bool isMostlyArabic(String s) {
    final letters = s.replaceAll(RegExp(r'[\s\d\p{P}]', unicode: true), '');
    if (letters.isEmpty) return true;
    var arabic = 0;
    for (final r in letters.runes) {
      if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) arabic++;
    }
    return arabic * 2 >= letters.runes.length;
  }

  // ---------- الردود الذكية ----------
  /// قاموس النوايا: لكل نية كلمات مفتاحية (مطبَّعة) وردود مقترحة بالترتيب.
  /// ترتيب القائمة هو ترتيب الأولوية عند تعادل النقاط.
  static const _intents = <_Intent>[
    _Intent('تحية', ['سلام', 'هلا', 'مرحبا', 'اهلا', 'هاي', 'صباح الخير', 'مساء الخير', 'شلونك', 'كيفك', 'كيف حالك', 'اخبارك', 'عامل ايه'],
        ['وعليكم السلام! 👋', 'أهلاً وسهلاً، نورنا', 'هلا والله، شخبارك؟']),
    _Intent('شكر', ['شكرا', 'مشكور', 'يعطيك العافيه', 'جزاك الله', 'ممتن', 'تسلم'],
        ['العفو 🌹', 'في خدمتك دائماً', 'هذا واجبي، لا شكر على واجب']),
    _Intent('اعتذار', ['اسف', 'عذرا', 'اعتذر', 'التقصير', 'ما قصصرت'],
        ['لا عليك أبداً', 'تمام، لا تشغل بالك', 'المهم أنك بخير 🤍']),
    _Intent('مبروك', ['مبروك', 'تهانينا', 'الف مبروك', 'مبارك'],
        ['الله يبارك فيك 🎉', 'تسلم! 🎊', 'ألف مبروك، تستاهل كل خير']),
    _Intent('موعد', ['متى', 'امتى', 'الساعه', 'وقت', 'موعد', 'بكرة', 'اليوم'],
        ['أقترح الساعة 8 مساءً', 'أخبرني الوقت المناسب لك', 'ما عدا ذلك أنا جاهز']),
    _Intent('مكان', ['وين', 'اين', 'مكان', 'وينكم', 'موقع', 'عنوان'],
        ['أرسل لي الموقع وسأصل', 'أنا قريب، قل لي أين', 'نلتقي عند المكان المتفق عليه']),
    _Intent('دعوة', ['نتشرف', 'دعوه', 'عزيمه', 'تعال', 'زورنا', 'نستقبلك', 'حفل', 'عزومة'],
        ['شكراً للدعوة، سأحضر إن شاء الله', 'أخبرني بالوقت والمكان', 'دعوة مقبولة، ودام عزيمتكم 🌟']),
    _Intent('طلب مساعدة', ['ساعدني', 'محتاج', 'ابي', 'ابغى', 'ارجو', 'ممكن', 'لازم', 'أرجو'],
        ['أكيد، كيف أساعدك؟', 'قل لي التفاصيل وأنا حاضر', 'حاضر، في الخدمة']),
    _Intent('اتفاق', ['تمام', 'ماشي', 'اتفقنا', 'اوكي', 'حسنا', 'تم', 'خلص'],
        ['ممتاز 🤝', 'تم، بانتظارك', 'إذن خلنا نبدأ']),
    _Intent('وفاء', ['مع السلامه', 'باي', 'تصبح على خير', 'ليله سعيده', 'اراك'],
        ['مع السلامة 👋', 'إلى اللقاء قريباً', 'تصبح على خير 🌙']),
    _Intent('سؤال', ['هل', 'ليش', 'كيف', 'ماذا', 'وش', 'شنو', 'لماذا', 'من', 'ايه'],
        ['سأتحقق وأرد عليك حالاً', 'سؤال جيد، دعني أفكر', 'أجل نناقشها معاً']),
    _Intent('تعزيز', ['رائع', 'جميل', 'حلو', 'ممتاز', 'زين', 'كفو', 'يعطيك'],
        ['تسلم! 😊', 'يسعدني ذلك', 'كل الزين منك']),
  ];

  /// أقوى نية في رسالة، أو null إن لم تُصنَّف.
  /// الكلمات المفتاحية تُطبَّع مع النص — فتطابق «متى/متي» و«شكراً/شكرا».
  static (String, int)? detectIntent(String message) {
    final n = normalize(message);
    if (n.trim().isEmpty) return null;
    String? best;
    var bestHits = 0;
    for (final intent in _intents) {
      var hits = 0;
      for (final kw in intent.keywords) {
        if (n.contains(normalize(kw))) hits++;
      }
      final isQuestion = message.contains('؟') || message.contains('?');
      final score = hits + (intent.name == 'سؤال' && isQuestion ? 1 : 0);
      if (score > bestHits) {
        bestHits = score;
        best = intent.name;
      }
    }
    if (best == null && (message.contains('؟') || message.contains('?'))) {
      return ('سؤال', 1);
    }
    return best == null ? null : (best, bestHits);
  }

  /// ردود ذكية جاهزة على آخر رسالة وردت (حتى 3 ردود قصيرة).
  /// إن لم تُصنَّف الرسالة تعيد ردوداً محايدة عامة.
  static List<String> smartReplies(String lastIncomingMessage) {
    final detected = detectIntent(lastIncomingMessage);
    if (detected != null) {
      final (name, hits) = detected;
      if (hits > 0) {
        for (final intent in _intents) {
          if (intent.name == name) return List.of(intent.replies);
        }
      }
    }
    // سؤال بعلامة استفهام بلا نية أقوى
    if (lastIncomingMessage.contains('؟') || lastIncomingMessage.contains('?')) {
      return const ['سأتحقق وأرد عليك حالاً', 'سؤال جيد، دعني أفكر', 'أجل نناقشها معاً'];
    }
    // رسالة إخبارية محايدة
    if (lastIncomingMessage.trim().length <= 8) {
      return const ['تمام 👍', 'أوافقك تماماً', 'أخبرني أكثر'];
    }
    return const ['تمام 👍', 'فهمتك، أكمل', 'أخبرني أكثر'];
  }

  // ---------- الملخص المحلي (استخلاصي) ----------
  /// كلمات وظيفية تُهمَل عند الترتيب (عربية شائعة + إنجليزية أساسية).
  static const _stopwords = <String>{
    'في', 'من', 'على', 'الى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'التي', 'الذي',
    'الذين', 'و', 'او', 'ثم', 'لكن', 'ان', 'انني', 'انا', 'انت', 'هو', 'هي',
    'نحن', 'هم', 'كان', 'كانت', 'يكون', 'قد', 'لقد', 'ما', 'لا', 'لم', 'لن',
    'كل', 'بعض', 'غير', 'حتى', 'اذا', 'اذاً', 'كما', 'بين', 'عند', 'عندما',
    'الان', 'فقط', 'جدا', 'ايضا', 'لي', 'لك', 'له', 'لها', 'به', 'بها',
    'هل', 'ايه', 'اي', 'يا', 'واحد', 'اثنين', 'the', 'is', 'a', 'an', 'and',
    'or', 'to', 'of', 'in', 'on', 'at', 'for', 'it', 'i', 'you', 'we', 'they',
  };

  /// هل السطر علامة وسيط لا نصاً؟ ([صورة]، [فيديو]…)
  static bool _isMediaMarker(String line) =>
      RegExp(r'^\S+:\s*\[[^\]]+\]$').hasMatch(line.trim()) ||
      line.trim() == '[صورة]' ||
      line.trim() == '[رسالة صوتية]';

  /// تلخيص محلي لأسطر «الاسم: النص» — يختار أهم الأسطر بترتيبها الأصلي.
  /// [maxLines] أقصى عدد أسطر في الملخص (2–5 حسب طول المحادثة).
  static String summarizeLines(List<String> lines, {int maxLines = 4}) {
    final clean = lines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (clean.isEmpty) return 'لا توجد رسائل لتلخيصها بعد.';
    if (clean.length <= maxLines) {
      return 'النقاط الأساسية:\n' +
          clean.map((l) => '• $l').join('\n');
    }
    // تكرار الكلمات المعنوية عبر المحادثة
    final tf = <String, int>{};
    final tokenOf = <int, List<String>>{};
    for (var i = 0; i < clean.length; i++) {
      final words = normalize(clean[i])
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
          .where((w) => w.length >= 3 && !_stopwords.contains(w))
          .toList();
      tokenOf[i] = words;
      for (final w in words.toSet()) {
        tf[w] = (tf[w] ?? 0) + 1;
      }
    }
    // نقاط كل سطر: مجموع تكرار كلماته (كلمات فريدة لكل سطر) + مكافآت
    final scores = <int, double>{};
    for (var i = 0; i < clean.length; i++) {
      if (_isMediaMarker(clean[i])) {
        scores[i] = -1; // السطور الوسيطية أخفض أولوية
        continue;
      }
      final words = tokenOf[i] ?? const <String>[];
      if (words.isEmpty) {
        scores[i] = 0.5;
        continue;
      }
      var s = 0.0;
      for (final w in words.toSet()) {
        s += tf[w] ?? 0;
      }
      s = s / words.length.clamp(1, 100); // كثافة معتدلة لا طول مطلق
      if (clean[i].contains('؟') || clean[i].contains('?')) s += 0.8;
      if (RegExp(r'\d').hasMatch(clean[i])) s += 0.5;
      scores[i] = s;
    }
    final ranked = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    final keep = ranked.take(maxLines.clamp(2, 5)).toSet();
    final picked = [
      for (var i = 0; i < clean.length; i++)
        if (keep.contains(i)) i,
    ];
    final body = picked.map((i) => '• ${clean[i]}').join('\n');
    return 'النقاط الأساسية:\n$body';
  }
}

class _Intent {
  const _Intent(this.name, this.keywords, this.replies);
  final String name;
  final List<String> keywords;
  final List<String> replies;
}
