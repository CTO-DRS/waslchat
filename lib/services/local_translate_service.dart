/// الترجمة المحلية الأساسية (المرحلة 9 ب — 0.23.0): محرك قاموسي عربي↔إنجليزي
/// **على الجهاز بلا شبكة إطلاقاً** — عبارات شائعة في المراسلة أولاً (الأطول
/// تطابقاً) ثم كلمات مفردة (مع حذف «ال» التعريف في الطريق العربي)، وما لا
/// يعرفه القاموس يبقى كما هو ويُعلن.
///
/// الصدق التصميمي: هذه ترجمة قاموسية أساسية لا تفهم تركيب الجملة ولا
/// الصرف العميق — للترجمة الأعمق يبقى المسار السحابي (Gemini) بموافقته
/// الصريحة كما هو. تُعلن نسبة التغطية مع كل نتيجة ولا تُدّعي كمالاً.
/// صفر شبكة وصفر طرف ثالث في هذا المسار — لا يغادر أي حرف.
import 'local_ai_service.dart';

class LocalTranslation {
  const LocalTranslation({
    required this.text,
    required this.translatedTokens,
    required this.totalTokens,
  });

  final String text;
  final int translatedTokens;
  final int totalTokens;

  /// نسبة الوحدات التي عرفها القاموس (0..1).
  double get coverage =>
      totalTokens == 0 ? 0 : translatedTokens / totalTokens;

  /// تغطية ضعيفة → الواجهة تعلن أن الترجمة قد تكون ناقصة.
  bool get low => coverage < 0.5;
}

class LocalTranslateService {
  LocalTranslateService._();

  /// عبارات شائعة بالمراسلة (تُطبَّع مفاتيحها عند البناء).
  static const _phrasesRaw = <String, String>{
    'صباح الخير': 'Good morning',
    'مساء الخير': 'Good evening',
    'كيف حالك': 'How are you',
    'كيف الحال': 'How are you',
    'شلونك': 'How are you',
    'بخير والحمد لله': "I'm fine, thank God",
    'الحمد لله بخير': "I'm fine, thank God",
    'شكرا جزيلا': 'Thank you very much',
    'جزاك الله خير': 'May God reward you',
    'من فضلك': 'Please',
    'عفوا': "You're welcome",
    'مع السلامة': 'Goodbye',
    'إلى اللقاء': 'See you',
    'تصبح على خير': 'Good night',
    'أين أنت': 'Where are you',
    'متى نلتقي': 'When do we meet',
    'متى الموعد': 'When is the appointment',
    'في أي وقت': 'At what time',
    'أنا في الطريق': "I'm on my way",
    'انتظر قليلا': 'Wait a moment',
    'لا أعرف': "I don't know",
    'لا مشكلة': 'No problem',
    'بعد قليل': 'In a little while',
    // المرحلة 14 أ (1.3.0): توسعة الكتالوج — تحيات ومواعيد وأرقام وتعبيرات
    // متكررة في المراسلة العربية
    'سلام عليكم': 'Peace be upon you',
    'وعليكم السلام': 'Peace be upon you too',
    'أهلا وسهلا': 'Welcome',
    'مساء النور': 'Good evening to you too',
    'إن شاء الله': 'God willing',
    'ما شاء الله': 'What God has willed',
    'بحمد الله': 'By Gods grace',
    'كل عام وأنتم بخير': 'May you be well every year',
    'رمضان كريم': 'Ramadan Kareem',
    'عيد سعيد': 'Happy Eid',
    'ألف مبروك': 'Congratulations',
    'مبارك عليك': 'Congratulations on this',
    'أنتظر ردك': 'Awaiting your reply',
    'أخبرني عند الوصول': 'Tell me when you arrive',
    'لا تنسى': "Don't forget",
    'في أقرب وقت': 'As soon as possible',
    'على مهلك': 'Take your time',
    'سوف أتأخر': "I'll be late",
    'أنا مشغول الآن': "I'm busy now",
    'أنا في السوق': "I'm at the market",
    'أنا واصلت': "I've arrived",
    'أين أنت الآن': 'Where are you now',
    'اتصل بي': 'Call me',
    'أرسل لي الموقع': 'Send me the location',
    'كم الساعة': 'What time is it',
    'في أي ساعة': 'At what hour',
    'بعد ساعة': 'In an hour',
    'الأسبوع القادم': 'Next week',
    'نهاية الأسبوع': 'Weekend',
    'أوافقك الرأي': 'I agree with you',
  };

  /// كلمات مفردة شائعة — الطريق العربي مطبَّع، والإنجليزي بحروف صغيرة.
  static const _wordsArEn = <String, String>{
    'مرحبا': 'Hello', 'اهلا': 'Hello', 'هلا': 'Hi', 'سلام': 'Hello',
    'نعم': 'Yes', 'لا': 'No', 'تمام': 'Okay', 'اتفقنا': 'Agreed',
    'حسنا': 'Alright', 'شكرا': 'Thanks', 'اسف': 'Sorry', 'عذرا': 'Excuse me',
    'اليوم': 'Today', 'بكرة': 'Tomorrow', 'امس': 'Yesterday',
    'الان': 'Now', 'لاحقا': 'Later', 'دائما': 'Always', 'ابدا': 'Never',
    'جميل': 'Beautiful', 'جيد': 'Good', 'سيء': 'Bad', 'كبير': 'Big',
    'صغير': 'Small', 'جديد': 'New', 'قديم': 'Old', 'سريع': 'Fast',
    'بيت': 'House', 'عمل': 'Work', 'مال': 'Money', 'ماء': 'Water',
    'طعام': 'Food', 'عائلة': 'Family', 'صديق': 'Friend', 'وقت': 'Time',
    'ساعة': 'Hour/Clock', 'دقيقة': 'Minute', 'اجتماع': 'Meeting',
    'مشروع': 'Project', 'ملف': 'File', 'صورة': 'Photo', 'رسالة': 'Message',
    'هاتف': 'Phone', 'عنوان': 'Address', 'طريق': 'Road', 'مدينة': 'City',
    'سوق': 'Market', 'مدرسة': 'School', 'جامعة': 'University',
    'طبيب': 'Doctor', 'مستشفى': 'Hospital', 'سيارة': 'Car',
    'مطار': 'Airport', 'تذكرة': 'Ticket', 'سعر': 'Price', 'مساعدة': 'Help',
    'مشكلة': 'Problem', 'سؤال': 'Question', 'جواب': 'Answer',
    'كتاب': 'Book', 'حاسوب': 'Computer', 'انترنت': 'Internet',
    'كلمة': 'Word', 'رقم': 'Number', 'تاريخ': 'Date', 'اسم': 'Name',
    'بلد': 'Country', 'لغة': 'Language', 'عربي': 'Arabic', 'انجليزي': 'English',
    'مع': 'With', 'قبل': 'Before', 'بعد': 'After', 'هنا': 'Here',
    'هناك': 'There',
    // المرحلة 14 أ (1.3.0): أرقام ومواعيد وتعبيرات مراسلة شائعة
    'واحد': 'One', 'اثنان': 'Two', 'ثلاثة': 'Three', 'أربعة': 'Four',
    'خمسة': 'Five', 'ستة': 'Six', 'سبعة': 'Seven', 'ثمانية': 'Eight',
    'تسعة': 'Nine', 'عشرة': 'Ten', 'مئة': 'Hundred', 'الف': 'Thousand',
    'نصف': 'Half', 'ربع': 'Quarter',
    'أول': 'First', 'ثاني': 'Second',
    'صباح': 'Morning', 'مساء': 'Evening', 'ظهر': 'Noon',
    'عصر': 'Afternoon', 'ليل': 'Night', 'ليلة': 'Night',
    'أسبوع': 'Week', 'شهر': 'Month', 'سنة': 'Year', 'عام': 'Year',
    'دقائق': 'Minutes', 'ثانية': 'Second', 'غدا': 'Tomorrow',
    'جمعة': 'Friday', 'سبت': 'Saturday', 'احد': 'Sunday',
    'اكيد': 'Sure', 'طيب': 'Okay', 'خلاص': 'Done', 'زين': 'Nice',
    'حاضر': 'Okay', 'ممكن': 'Can', 'جاهز': 'Ready', 'مشغول': 'Busy',
    'متأخر': 'Late', 'وصلت': 'Arrived', 'قريب': 'Near', 'بعيد': 'Far',
    'انتظر': 'Wait', 'رد': 'Reply', 'أرسل': 'Send',
    'عندي': 'I have', 'أحتاج': 'I need', 'أريد': 'I want',
    'مهم': 'Important', 'عاجل': 'Urgent', 'موعد': 'Appointment',
    'ميعاد': 'Appointment', 'تأكيد': 'Confirmation', 'تعديل': 'Edit',
    'تنبيه': 'Reminder', 'تذكير': 'Reminder', 'هدية': 'Gift',
    'دعوة': 'Invitation', 'حفل': 'Party', 'زواج': 'Wedding',
    'عيد': 'Eid', 'رمضان': 'Ramadan', 'صلاة': 'Prayer', 'مسجد': 'Mosque',
  };

  /// عربي ← إنجليزي: مفاتيح مطبَّعة.
  static final Map<String, String> _dictArToEn = {
    for (final e in _wordsArEn.entries)
      LocalAiService.normalize(e.key): e.value,
  };

  /// عبارات عربي ← إنجليزي مرتبة الأطول أولاً بمفاتيح مطبَّعة.
  static final List<MapEntry<String, String>> _phrasesArToEn = _phrasesRaw
      .entries
      .map((e) => MapEntry(LocalAiService.normalize(e.key), e.value))
      .toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));

  /// إنجليزي ← عربي: قاموس عكسي يبني مرة واحدة (أول رأس إنجليزي للكلمة).
  static final Map<String, String> _dictEnToAr = () {
    final m = <String, String>{};
    _wordsArEn.forEach((ar, en) {
      m.putIfAbsent(en.toLowerCase().split('/').first, () => ar);
    });
    _phrasesRaw.forEach((ar, en) {
      m.putIfAbsent(en.toLowerCase(), () => ar);
    });
    return m;
  }();

  /// عبارات إنجليزي ← عربي مرتبة الأطول أولاً (بأحرف صغيرة).
  static final List<MapEntry<String, String>> _phrasesEnToAr = _phrasesRaw
      .entries
      .map((e) => MapEntry(e.value.toLowerCase(), e.key))
      .toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));

  /// نص مطبَّع مع خريطة تحوّل كل فهرس مطبَّع إلى فهرس الأصل — فالتطبيع
  /// (تشكيل وهمزات وتاء) لا يكسر المطابقة والاستبدال يجري على الأصل.
  static (String, List<int>) _normalizeWithMap(String src) {
    final lower = src.toLowerCase();
    final buf = StringBuffer();
    final map = <int>[];
    for (var i = 0; i < lower.length; i++) {
      final c = lower[i];
      if (RegExp('[\u064B-\u0652\u0670\u0640]').hasMatch(c)) continue;
      switch (c) {
        case 'أ' || 'إ' || 'آ' || 'ٱ':
          buf.write('ا');
          break;
        case 'ة':
          buf.write('ه');
          break;
        case 'ى':
          buf.write('ي');
          break;
        case 'ؤ':
          buf.write('و');
          break;
        case 'ئ':
          buf.write('ي');
          break;
        default:
          buf.write(c);
      }
      map.add(i);
    }
    map.add(lower.length); // حارس النهاية
    return (buf.toString(), map);
  }

  /// الترجمة القاموسية: العبارات أولاً (الأطول أولاً وحماية من التداخل)
  /// ثم الكلمات المفردة خارج العبارات حصراً (مع محاولة إسقاط «ال»)،
  /// والعد صادق: كل عبارة = وحدة، وكل كلمة خارجها = وحدة.
  static LocalTranslation translate(String text, {required bool toEnglish}) {
    final src = text.trim();
    if (src.isEmpty) {
      return const LocalTranslation(
          text: '', translatedTokens: 0, totalTokens: 0);
    }
    final dict = toEnglish ? _dictArToEn : _dictEnToAr;
    final phrases = toEnglish ? _phrasesArToEn : _phrasesEnToAr;
    final (norm, map) = _normalizeWithMap(src);

    // القطع المترجمة: (بداية الأصل، نهاية الأصل، الترجمة) — مرتبة لاحقاً
    final pieces = <(int, int, String)>[];
    final covered = List<bool>.filled(norm.length, false);

    // 1) العبارات — الأطول أولاً بلا تداخل
    for (final p in phrases) {
      if (p.key.isEmpty || !norm.contains(p.key)) continue;
      for (final m in RegExp(RegExp.escape(p.key)).allMatches(norm)) {
        var free = true;
        for (var i = m.start; i < m.end; i++) {
          if (covered[i]) {
            free = false;
            break;
          }
        }
        if (!free) continue;
        for (var i = m.start; i < m.end; i++) {
          covered[i] = true;
        }
        pieces.add((map[m.start], map[m.end], p.value));
      }
    }

    // 2) الكلمات المفردة خارج العبارات حصراً
    final wordRe = RegExp(r'[\p{L}\u0600-\u06FF]+', unicode: true);
    for (final m in wordRe.allMatches(norm)) {
      var inPhrase = false;
      for (var i = m.start; i < m.end; i++) {
        if (covered[i]) {
          inPhrase = true;
          break;
        }
      }
      if (inPhrase) continue;
      final w = m.group(0)!;
      var hit = dict[w];
      if (hit == null && w.length >= 5 && w.startsWith('ال')) {
        hit = dict[w.substring(2)]; // العائلة → عائلة، السوق → سوق
      }
      if (hit != null) {
        pieces.add((map[m.start], map[m.end], hit));
      }
    }

    // 3) بناء النتيجة: الأصل بين القطع + الترجمة مكان كل قطعة
    pieces.sort((a, b) => a.$1.compareTo(b.$1));
    final buf = StringBuffer();
    var cursor = 0;
    for (final (s, e, t) in pieces) {
      if (s < cursor) continue; // تداخل نظري محصّن بالعلم أعلاه
      buf.write(src.substring(cursor, s));
      buf.write(t);
      cursor = e;
    }
    if (cursor < src.length) buf.write(src.substring(cursor));

    // 4) العد: القطع المترجمة + الكلمات المكشوفة غير المترجمة (المفردات)
    final coveredWordRe =
        RegExp(r'[\p{L}\u0600-\u06FF]+', unicode: true);
    var uncoveredWords = 0;
    for (final m in coveredWordRe.allMatches(norm)) {
      var inPhrase = false;
      for (var i = m.start; i < m.end; i++) {
        if (covered[i]) {
          inPhrase = true;
          break;
        }
      }
      if (inPhrase) continue;
      uncoveredWords++;
    }
    final translated = pieces.length;
    final total = translated + uncoveredWords;
    return LocalTranslation(
      text: buf.toString(),
      translatedTokens: translated,
      totalTokens: total,
    );
  }

  // ---------- كشف الكتابة (المرحلة 14 أ — 1.3.0) ----------

  /// كشف كتابة النص المعروض صادقاً على مستوى الحروف حصراً: «ar» إذا غلبت
  /// الحروف العربية على اللاتينية، «latin» إذا غلبت اللاتينية، و«other» إن
  /// لم توجد حروف كافية (أرقام ورموز وإيموجي) — كشف كتابة لا لغة أعمق من
  /// حروفها، والواجهة تعلن ذلك ولا تدّعي فهم تركيب.
  static String detectScript(String text) {
    var ar = 0;
    var la = 0;
    for (final r in text.runes) {
      if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) {
        ar++;
      } else if ((r >= 0x0041 && r <= 0x005A) ||
          (r >= 0x0061 && r <= 0x007A)) {
        la++;
      }
    }
    if (ar == 0 && la == 0) return 'other';
    return ar >= la ? 'ar' : 'latin';
  }

  /// حارس صادق للغات السحابية الجديدة (1.3.0): هل رد الخادم طابق اللغة
  /// المطلوبة فعلاً؟ en/fr/tr يُنتظر أنها لاتينية، والأردية تُنتظر حروفاً
  /// أردية مميزة (ے ٹ ڈ ڑ ں ہ ھ پ چ گ ژ ۂ) — إن عاد النص عربياً خالياً من
  /// المميزات الأردية فالخادم القديم لم يُحدَّث بعد، فتعلم الواجهة ذلك بدل
  /// عرض ترجمة خاطئة بصمت. المساران القائمان (ar/en كما كانت) لا يمسّهما الحارس.
  static bool resultMatchesTarget(String result, String target) {
    switch (target) {
      case 'en':
      case 'fr':
      case 'tr':
        return detectScript(result) == 'latin';
      case 'ur':
        if (!RegExp('[\u0600-\u06FF\u0750-\u077F]').hasMatch(result)) {
          return false;
        }
        const marks = 'ےٹڈڑںہھپچگژۂ';
        return result.runes
            .any((r) => marks.contains(String.fromCharCode(r)));
      default:
        return true; // عربي/إنجليزي — المسار القائم كما هو
    }
  }
}
