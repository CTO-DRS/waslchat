/// البحث الذكي في الرسائل (المرحلة 5 — v0.14.0): يعمل **محلياً بالكامل**
/// على نصوص الرسائل التي فك التطبيق تشفيرها على جهازك — لا يُرسل أي شيء.
///
/// ما الذي يجعله «ذكياً» عن البحث البسيط بالاحتواء؟
/// 1) تطبيع عربي كامل: تجاهل التشكيل والتطويل وتوحيد الألف والهمزات
///    (أ إ آ → ا) والهاء المربوطة (ة → ه) والألف المقصورة (ى → ي) —
///    فـ«مُحَمَّد» و«محمد» و«أحمد»/«احمد» متكافئة.
/// 2) تسامح الأخطاء: مسافة تحرير Damerau–Levenshtein تحدّ بعتبة حسب طول
///    الكلمة (كلمة 4+ أحرف تسامح خطأً واحداً، 7+ تسامح اثنين) — فـ«شكرا jazila»
///    مع حرف ناقص تُجَد.
/// 3) توسيع بالمرادفات الشائعة في الدردشة العربية (متى/امتى/وقت…) — بحث
///    «بالمعنى القريب» بلا نموذج سحابي ولا مفهرسة خارجية.
/// 4) ترتيب النتائج بالنقاط: مطابقة تامة > بادئة > مرادف > خطأ مكتبي.
class SmartSearchService {
  SmartSearchService._();

  /// تطبيع عربي للمطابقة (نفس روح wasl_norm_ar على الخادم).
  static String normalize(String s) {
    var out = s.toLowerCase();
    out = out.replaceAll(RegExp('[\u064B-\u0652\u0670\u0640\u06D6-\u06ED]'), '');
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

  /// مرادفات شائعة بالدردشة: كل مجموعة مفاتيح تُوسَّع لبقية مجموعتها.
  static const _synonymGroups = <List<String>>[
    ['متى', 'امتى', 'وقت', 'موعد', 'الساعه'],
    ['شكرا', 'مشكور', 'يعطيك العافيه', 'جزاك الله'],
    ['الان', 'حالا', 'فورا', 'دحين', 'هسه'],
    ['امس', 'البارحه', 'قبل يوم'],
    ['غدا', 'بكره', 'المانح', 'المانحة'],
    ['وين', 'اين', 'مكان', 'موقع', 'عنوان'],
    ['باس', 'سعر', 'كم', 'تكلفه'],
    ['صورة', 'صوره', 'بيك', 'تصويره'],
    ['ملف', 'دوك', 'مستند', 'ورق'],
    ['اجتماع', 'ميعاد', 'لقاء'],
    ['سلام', 'مرحبا', 'هلا', 'اهلا'],
  ];

  static final Map<String, Set<String>> _synonyms = _buildSynonyms();
  static Map<String, Set<String>> _buildSynonyms() {
    final m = <String, Set<String>>{};
    for (final group in _synonymGroups) {
      final norm = group.map(normalize).toSet();
      for (final w in norm) {
        m.putIfAbsent(w, () => <String>{}).addAll(norm);
      }
    }
    return m;
  }

  /// مسافة Damerau–Levenshtein (بالتبديل المجاور) بين كلمتين مطبَّعتين.
  static int editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final n = a.length, m = b.length;
    // مصفوفة كاملة (n+1)x(m+1) — الكلمات قصيرة فلا مشكلة أداء
    final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = _min3(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
        // تبديل حرفين متجاورين (Damerau)
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          final t = d[i - 2][j - 2] + 1;
          if (t < v) v = t;
        }
        d[i][j] = v;
      }
    }
    return d[n][m];
  }

  static int _min3(int x, int y, int z) => x < y ? (x < z ? x : z) : (y < z ? y : z);

  /// عتبة تسامح حسب طول الكلمة المطبَّعة.
  static int _tolerance(String word) {
    if (word.length >= 7) return 2;
    if (word.length >= 4) return 1;
    return 0;
  }

  /// هل الكلمة (المطبَّعة) تطابق الهدف؟ يعيد نوع المطابقة أو null.
  /// exact: تامة | prefix: بادئة | fuzzy: ضمن عتبة الخطأ | synonym: مرادف
  static String? matchToken(String word, String target) {
    final w = normalize(word);
    final t = normalize(target);
    if (t.isEmpty || w.isEmpty) return null;
    if (w == t) return 'exact';
    if (w.startsWith(t) || t.startsWith(w)) return 'prefix';
    if (tolerantEquals(w, t)) return 'fuzzy';
    if ((_synonyms[t] ?? const {}).contains(w)) return 'synonym';
    return null;
  }

  /// تطابق متسامح ضمن عتبة طول الكلمة الأطول.
  static bool tolerantEquals(String a, String b) {
    final tol = _tolerance(a.length >= b.length ? a : b);
    if (tol == 0) return false;
    return editDistance(a, b) <= tol;
  }

  /// نقاط استعلام داخل نص رسالة — صفر = لا يطابق.
  /// الاستعلام متعدد الكلمات: يكفي أن تطابق كلماته المهمة (كل كلمة ≥3 أحرف).
  static double score(String messageText, String query) {
    final q = query.trim();
    if (q.isEmpty) return 0;
    final qWords = normalize(q)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    if (qWords.isEmpty) return 0;
    final mWords = normalize(messageText)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    // مطابقة العبارة الكاملة أولوية قصوى
    final nMessage = normalize(messageText);
    final nQuery = normalize(q);
    if (nMessage.contains(nQuery)) return 100;
    var total = 0.0;
    var matched = 0;
    for (final qw in qWords) {
      var best = 0.0;
      for (final mw in mWords) {
        final kind = matchToken(mw, qw);
        if (kind == null) continue;
        final s = switch (kind) {
          'exact' => 10.0,
          'prefix' => 7.0,
          'fuzzy' => 5.0,
          _ => 3.0, // synonym
        };
        if (s > best) best = s;
      }
      if (best > 0) {
        matched++;
        total += best;
      } else if (qw.length >= 3) {
        return 0; // كلمة مهمة بلا أي مطابقة → لا نتيجة
      }
    }
    if (matched == 0) return 0;
    return total;
  }

  /// هل يطابق النص الاستعلام؟ (اختصار للفلترة)
  static bool matches(String messageText, String query) =>
      score(messageText, query) > 0;

  /// أطوال المقاطع المطابقة داخل النص لإبرازها (بنصه الأصلي غير المطبَّع).
  /// يعيد قائمة (بداية، طول) على النص الأصلي.
  static List<(int, int)> highlightSpans(String original, String query) {
    final qWords = normalize(query)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    if (qWords.isEmpty) return const [];
    final spans = <(int, int)>[];
    final wordRe = RegExp(r'\S+', unicode: true);
    for (final m in wordRe.allMatches(original)) {
      final w = m.group(0)!;
      for (final qw in qWords) {
        final kind = matchToken(w, qw);
        if (kind != null) {
          spans.add((m.start, w.length));
          break;
        }
      }
    }
    return spans;
  }

  /// تسمية عربية لما يفعله البحث الذكي (لعرضها في الواجهة).
  static const String capabilityHint =
      'بحث ذكي: يتجاهل التشكيل والهمزات ويسامح الأخطاء المطبعية ويوسّع بالمرادفات';
}
