/// محرك RAG صفر شبكة — المحرك النقي التاسع من محركات وصل (المرحلة 19 — 1.17.0).
///
/// العقد الصادق حرفياً من GRAND_PLAN_3 «اسأل وصل» بالاسترجاع والتوليد المحليين:
/// الاسترجاع المحلي القائم يصير مصدر مقاطع للنموذج المحلي، وكل إجابة **تُعلن
/// مصدرها** — وهنا كعقد مفروض آلياً لا كوعد: إخراج المولّد بلا إسناد مقاطع
/// صحيحة **يسقط** ولا يُعرض، ويعود الاستخلاص المعلن المصدر (سياسة 1.3.0)،
/// وبلا ما يكفي تُعاد حالة «لا أجد» حرفياً. المحرك بلا شبكة إطلاقاً: الاسترجاع
/// دالة تُحقن (التطبيق يمرر خدمته القائمة) والمولّد واجهة تُحقن (تملأ عند ربط
/// النموذج المحلي في 1.18.0) — فالبنية كاملة الآن والسلوك اليومي بلا تغيير.
library;

/// مقطع مسترجَع محلياً بمصدره — الإسناد أساس العقد.
class RagPassage {
  const RagPassage({
    required this.conversationId,
    required this.text,
    required this.dateIso,
    required this.score,
  });

  final String conversationId;
  final String text;
  final String dateIso;

  /// نقاط الصلة كما قاسها الاسترجاع المحلي (تُعرض كما هي بلا تزيين)
  final double score;
}

/// إخراج مولّد محلي مع إسناده — بلا إسناد صحيح لا يُقبل.
class GeneratedOutput {
  const GeneratedOutput({required this.text, required this.citedIndexes});

  final String text;

  /// فهارس المقاطع التي بنى عليها الإجابة (ترتيب حزمة السياق)
  final List<int> citedIndexes;
}

/// واجهة المولّد المحلي — خانة النموذج (تملأ في 1.18.0 بقياس ميداني).
/// إعادة null = رفض المولّد أو عدم جاهزيته: فلا يُدّعى توليد.
abstract class LocalGenerator {
  Future<GeneratedOutput?> generate(RagContextPack pack);
}

/// حزمة السياق المقدمة للمولّد — ميزانية أحرف صارمة منسحبة من الأضعف صلةً.
class RagContextPack {
  RagContextPack({required this.question, required List<RagPassage> passages, int maxChars = 1200})
      : _maxChars = maxChars {
    // الميزانية: نتناول بالصلة التنازلية ثم نمسح النص المنسحب من الحزمة
    final ordered = [...passages]..sort((a, b) => b.score.compareTo(a.score));
    var used = question.length;
    for (final p in ordered) {
      final cost = p.text.length + p.conversationId.length + p.dateIso.length + 8;
      if (used + cost > _maxChars) break;
      used += cost;
      this.passages.add(p);
    }
    // الحزمة تعرض للعرض بنفس ترتيب الزمن الأصلي كي تُقرأ كما جرى فعلاً
    this.passages.sort((a, b) => a.dateIso.compareTo(b.dateIso));
  }

  final String question;
  final List<RagPassage> passages = <RagPassage>[];
  final int _maxChars;

  /// عدد الأحرف المسموح لحزمة واحدة (للعرض والاختبار)
  int get maxChars => _maxChars;

  /// نص السياق الموحد الذي يقرؤه أي مولّد — كل مقطع بسطر مصدره.
  String render() {
    final sb = StringBuffer('السؤال: $question\n');
    for (final p in passages) {
      sb.writeln('— [${p.conversationId} | ${p.dateIso}] ${p.text}');
    }
    return sb.toString();
  }
}

/// حالة الإجابة الصادقة: لا يكفي، أو استخلاص معلن المصدر، أو توليد محلي مسند.
enum RagState { notEnough, extractive, generated }

/// إجابة RAG كاملة — مصادرها جزء من بنيتها لا نصاً مجاوراً.
class RagAnswer {
  const RagAnswer({
    required this.state,
    required this.question,
    this.text,
    this.usedPassages = const <RagPassage>[],
  });

  final RagState state;
  final String question;
  final String? text;
  final List<RagPassage> usedPassages;
}

/// خط أنابيب «اسأل وصل» RAG: استرجاع محقون → حزمة ميزانية → مولّد محقون
/// → تحقق إسناد إلزامي → إجابة صادقة.
class RagPipeline {
  RagPipeline({required this.retrieve, this.generator, this.maxChars = 1200});

  /// الاسترجاع المحلي — التطبيق يمرر خدمته القائمة (0.22.0/1.3.0) بعتبتها المعلنة
  final List<RagPassage> Function(String question) retrieve;

  /// المولّد المحلي — null اليوم (السلوك استخلاصي كما هو)، يُملأ عند ربط النموذج
  final LocalGenerator? generator;

  /// ميزانية أحرف حزمة السياق
  final int maxChars;

  /// الإجابة الكاملة — لا مسار يعلن معرفة بلا مصدر.
  Future<RagAnswer> answer(String question) async {
    final found = retrieve(question);
    if (found.isEmpty) {
      return RagAnswer(state: RagState.notEnough, question: question);
    }
    final pack = RagContextPack(
        question: question, passages: found, maxChars: maxChars);
    final gen = generator;
    if (gen != null) {
      final out = await gen.generate(pack);
      if (out != null && out.text.trim().isNotEmpty) {
        // العقد: الإسناد يتحقق — فهرس خارج الحزمة يُسقط، وإجابة بلا أي إسناد
        // صحيح تسقط كلياً ويعود الاستخلاص المعلن المصدر
        final cited = <RagPassage>[];
        for (final i in out.citedIndexes) {
          if (i >= 0 && i < pack.passages.length) {
            cited.add(pack.passages[i]);
          }
        }
        if (cited.isNotEmpty) {
          return RagAnswer(
            state: RagState.generated,
            question: question,
            text: out.text,
            usedPassages: cited,
          );
        }
      }
    }
    // الاستخلاص: أسطر المقاطع نفسها بترتيب زمني — مصدر كل سطر من بنية المقطع
    final lines = pack.passages
        .map((p) => '${p.text} [${p.conversationId} | ${p.dateIso}]')
        .join('\n');
    return RagAnswer(
      state: RagState.extractive,
      question: question,
      text: lines,
      usedPassages: pack.passages,
    );
  }
}

/// بوابة الجهاز للفهرسة الخلفية — حقنة الاختبار/التطبيق (البطارية الحقيقية
/// تربط عند قرار اعتمادية أصلية موثق في GRAND_PLAN_3).
abstract class DeviceGate {
  bool get allowsProcessing;
}

class AlwaysAllowGate implements DeviceGate {
  @override
  bool get allowsProcessing => true;
}

/// مجدول الفهرسة الخلفية بأولوية منخفضة (1.17.0): دفعات صغيرة بين مقاطع،
/// **يتوقف فوراً** حين ترفض بوابة الجهاز (بطارية منخفضة/حرارة)، ويكمل من حيث
/// توقف حين تسمح — بلا أي عمل شبكة: الفهرسة نصوص محلية حصراً.
class IndexScheduler {
  IndexScheduler({required this.gate, this.batchSize = 20});

  final DeviceGate gate;

  /// حجم الدفعة الواحدة قبل إعادة سؤال البوابة — «أولوية منخفضة» ملموسة
  final int batchSize;

  final List<String> _queue = <String>[];
  bool _running = false;

  /// مازال في الطابور بانتظار معالجة (بما فيه المتعثر مؤقتاً)
  int get pending => _queue.length;

  /// إضافة معرفات للفهرسة (تُقصى المكررة)
  void enqueue(Iterable<String> ids) {
    for (final id in ids) {
      if (!_queue.contains(id)) _queue.add(id);
    }
  }

  /// معالجة الطابور: البوابة تُسأل قبل كل عنصر لا بين الدفعات فقط — الرفض
  /// (بطارية منخفضة/حرارة) يوقف **فوراً** بلا استهلاك، والاستدعاء القادم
  /// يكمل من حيث توقف.
  Future<void> drain(Future<void> Function(String id) indexOne) async {
    if (_running) return; // تشغيل واحد في كل لحظة
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        if (!gate.allowsProcessing) return; // توقف نهاراً كما وثقت الخارطة
        final batch = _queue.take(batchSize).toList();
        for (final id in batch) {
          if (!gate.allowsProcessing) return; // حتى داخل الدفعة — فورية
          await indexOne(id);
          _queue.remove(id);
        }
      }
    } finally {
      _running = false;
    }
  }
}

/// موافقة صريحة لمرة واحدة على توليد ملخص محلي — «بموافقة صريحة في كل مرة»
/// حرفياً: المنحة تُستهلك بالاستخدام الواحد فلا يُولَّد ملخصان بمنحة واحدة.
class OneShotConsent {
  bool _granted = false;

  void grant() => _granted = true;

  bool get isGranted => _granted;

  /// استهلاك المنحة: true مرة واحدة إن كانت ممنوحة، ثم false حتى منحة جديدة
  bool consume() {
    final ok = _granted;
    _granted = false;
    return ok;
  }
}
