/// مساعد الصياغة بأسلوبك (المرحلة 9 ب — 0.23.0)
///
/// يتعلم محلياً من آخر 200 رد **أرسلتها أنت** في هذه المحادثة: مستوى
/// الرسمية (كلمات مجاملات رسمية مقابل عامية)، متوسط طول الرد، معدل
/// الإيموجي، وأشهر البادئات والخواتم في ردودك — ثم يقترح 3 صيغ لما تكتبه
/// (رسمي/ودي/موجز) مرتبة حسب نبرتك الغالبة.
///
/// الصدق التصميمي: هذه قوالب قواعدية تُركَّب من إشارات أسلوبك — وليست نموذج
/// لغة يولّد نصوصاً جديدة. كل شيء يُبنى ويُحسب ويُخزَّن على جهازك حصراً:
/// لا يغادر أي حرف من ردودك، ولا يُرسل ما تكتبه لأي مكان.
import 'local_ai_service.dart';

/// بصمة أسلوب المستخدم المستخلصة من ردوده.
class StyleProfile {
  const StyleProfile({
    required this.formality,
    required this.avgWords,
    required this.emojiRate,
    required this.topOpeners,
    required this.topClosers,
    required this.sampleCount,
  });

  /// 0 = عامي تماماً، 1 = رسمي تماماً، 0.5 = محايد/بلا بيانات كافية.
  final double formality;
  final double avgWords;
  final double emojiRate;
  final List<String> topOpeners;
  final List<String> topClosers;
  final int sampleCount;

  static const StyleProfile neutral = StyleProfile(
    formality: 0.5,
    avgWords: 10,
    emojiRate: 0,
    topOpeners: [],
    topClosers: [],
    sampleCount: 0,
  );
}

/// صيغة مقترحة واحدة.
class StyleDraft {
  const StyleDraft({required this.label, required this.text, required this.hint});

  /// رسمي / ودي / موجز
  final String label;
  final String text;
  final String hint;
}

class StyleAssistService {
  StyleAssistService._();

  static const int learnLimit = 200;

  static final RegExp _emoji = RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F900}-\u{1F9FF}\u{2764}\u{1F600}-\u{1F64F}]',
      unicode: true);

  /// كلمات رسمية ترفع مؤشر الرسمية (مطبَّعة).
  static const _formalMarkers = <String>[
    'تفضل', 'تفضلوا', 'حضرات', 'من فضلك', 'رجاء', 'عفوا', 'تكرم', 'تكرموا',
    'تحياتي', 'شاكر', 'شاكرا', 'ممتن', 'ممتنين', 'ارجو', 'نرجو', 'حضراتكم',
    'فائق', 'احترام', 'ان وجدت', 'بكل احترام', 'وفقكم الله', 'جزيل الشكر',
  ];

  /// كلمات عامية تكسر الرسمية (مطبَّعة).
  static const _casualMarkers = <String>[
    'هههه', 'ههه', 'هلا', 'شلون', 'شخبارك', 'ابغى', 'ابي', 'وش', 'ويش',
    'كذا', 'عشان', 'طيب', 'ياخذنك', 'ماشي', 'تمام', 'اوك', 'زين', 'كفو',
    'دحين', 'هسه', 'حلو', 'خلاص', 'يلا',
  ];

  static String _norm(String s) => LocalAiService.normalize(s);

  /// بناء البصمة من آخر [learnLimit] رد أرسلته — نصوص فارغة تُهمل،
  /// وبأقل من 5 ردود تعيد البصمة المحايدة (لا تعلم من عينة ناقصة).
  static StyleProfile learn(List<String> myMessages) {
    final texts = myMessages
        .map((m) => m.trim())
        .where((t) => t.isNotEmpty)
        .take(learnLimit)
        .toList();
    if (texts.length < 5) return StyleProfile.neutral;

    // الرسمية: نصيب الكلمات الرسمية من مجموع علامتي النبرة
    var formal = 0, casual = 0;
    var totalWords = 0;
    var emojiMsgs = 0;
    final openers = <String, int>{};
    final closers = <String, int>{};
    for (final t in texts) {
      final n = _norm(t);
      for (final m in _formalMarkers) {
        if (n.contains(m)) formal++;
      }
      for (final m in _casualMarkers) {
        if (n.contains(m)) casual++;
      }
      final words =
          n.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toList();
      totalWords += words.length;
      if (_emoji.hasMatch(t)) emojiMsgs++;
      if (words.length >= 1) {
        final op = words.take(2).join(' ');
        if (op.length >= 3) openers[op] = (openers[op] ?? 0) + 1;
      }
      if (words.length >= 2) {
        final cl = words.sublist(words.length - 2).join(' ');
        if (cl.length >= 3) closers[cl] = (closers[cl] ?? 0) + 1;
      }
    }
    final tone = formal + casual;
    final top = (Map<String, int> m) {
      final entries = m.entries.where((e) => e.value >= 2).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return entries.take(3).map((e) => e.key).toList();
    };

    return StyleProfile(
      formality: tone == 0 ? 0.5 : formal / tone,
      avgWords: totalWords / texts.length,
      emojiRate: emojiMsgs / texts.length,
      topOpeners: top(openers),
      topClosers: top(closers),
      sampleCount: texts.length,
    );
  }

  /// اقتراح 3 صيغ لما تكتبه — الترتيب حسب نبرتك: الرسمي أولاً إن كنت
  /// رسمياً (formality > 0.6) وإلا الودي أولاً. التلميح الفارغ يعطي
  /// صيغ بداية عامة من أسلوبك.
  static List<StyleDraft> drafts(String hint, {StyleProfile? profile}) {
    final p = profile ?? StyleProfile.neutral;
    final h = hint.trim();
    final formalFirst = p.formality > 0.6;

    final formal = _formalDraft(h, p);
    final friendly = _friendlyDraft(h, p);
    final brief = _briefDraft(h);
    final list = <StyleDraft>[formal, friendly, brief];
    if (!formalFirst) {
      // الودي أولاً ثم الرسمي
      return [friendly, formal, brief];
    }
    return list;
  }

  static String _cleanHint(String h) {
    var out = h.replaceAll(RegExp(r'\s+'), ' ').trim();
    // إزالة تحيات مكررة سيبني عليها القالب
    for (final g in const ['سلام', 'مرحبا', 'هلا', 'اهلا', 'صباح الخير', 'مساء الخير']) {
      final ng = _norm(g);
      if (out.toLowerCase().startsWith(ng) || _norm(out).startsWith(ng)) {
        out = out.substring(
            out.length <= g.length ? out.length : _stripPrefixLen(out, g));
        break;
      }
    }
    return out.trim();
  }

  static int _stripPrefixLen(String text, String greeting) {
    // أطول بادئة شائعة نصياً بين النص والتلميح (تقريب كافٍ للقوالب)
    final idx = text.toLowerCase().indexOf(greeting.toLowerCase());
    if (idx >= 0) {
      var end = idx + greeting.length;
      while (end < text.length && '،,. '.contains(text[end])) {
        end++;
      }
      return end;
    }
    return text.length;
  }

  static StyleDraft _formalDraft(String h, StyleProfile p) {
    final clean = _cleanHint(h);
    if (clean.isEmpty) {
      return const StyleDraft(
          label: 'رسمي',
          text: 'تحية طيبة، أود المتابعة معك في الموضوع عندما يتيسر لك.',
          hint: '');
    }
    final closer = p.topClosers.isNotEmpty ? '' : '، وشاكر لك تعاونك';
    return StyleDraft(
        label: 'رسمي',
        text: 'من فضلك، $clean$closer.',
        hint: clean);
  }

  static StyleDraft _friendlyDraft(String h, StyleProfile p) {
    final clean = _cleanHint(h);
    final opener = p.topOpeners.isNotEmpty ? '${p.topOpeners.first}، ' : '';
    var text = clean.isEmpty ? 'هلا! شلون نرتب الموضوع؟' : '$opener$clean';
    if (clean.isNotEmpty && p.emojiRate >= 0.3 && !_emoji.hasMatch(text)) {
      text += ' 🙂';
    }
    return StyleDraft(label: 'ودي', text: text, hint: clean);
  }

  static StyleDraft _briefDraft(String h) {
    var clean = _cleanHint(h);
    if (clean.isEmpty) return const StyleDraft(label: 'موجز', text: 'نكمل الموضوع لاحقاً؟', hint: '');
    // الموجز يقلم الجمل الثانوية بعد الفواصل والـ«و» الثقيلة ويقص الطول
    clean = clean.split(RegExp(r'[،,]')).first.trim();
    if (clean.length > 80) clean = '${clean.substring(0, 78)}…';
    return StyleDraft(label: 'موجز', text: clean, hint: clean);
  }

  /// نص الإفصاح المعروض داخل ورقة الصياغة حرفياً.
  static const String disclosure =
      'الصياغة تتعلم من آخر 200 رد أرسلتها في هذه المحادثة — على جهازك حصراً '
      'ولا يغادر أي حرف، وقوالبها من أسلوبك لا نموذج لغة سحابي';
}
