/// خدمة «اسأل وصل» RAG — طبقة ربط التطبيق فوق محرك `engines/wasl_rag` النقي
/// (نُسخ جوهره هنا وفق عادة المحركات كما في wasl_model_gate وwasl_model_fetch).
///
/// المرحلة 19 — 1.17.0 حسب GRAND_PLAN_3: الاسترجاع المحلي القائم (البحث
/// الدلالي المتجهي 0.22.0 + «اسأل وصل» الاستخلاصي 1.3.0) يصير مصدر مقاطع
/// لحزمة سياق بميزانية، والمولّد المحلي خانة تُحقن عند ربط النموذج في 1.18.0
/// — وبقاؤها null اليوم يعني أن السلوك استخلاصي معلن المصدر كما هو بلا أي
/// تغيير، مع الفروض الجديدة الآلية: لا إجابة مولدة بلا إسناد صحيح، وفهرسة
/// خلفية تتوقف فوراً على بوابة الجهاز، وموافقة لمرة واحدة لكل ملخص مولد.
///
/// الصدق التصميمي: بوابة البطارية الحقيقية تحتاج اعتمادية أصلية (كود JNI)
/// وهي خلف بوابة القرار الموثقة في GRAND_PLAN_3 — حتى ذلك الحين تُحقن البوابة
/// من الخارج (الاختبارات وطبقة النظام حين تربط)، والافتراضي يسمح.
library;

import 'ask_wasl_service.dart';

// ————— جوهر المحرك النقي (نسخة التطبيق من engines/wasl_rag) —————

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
  final double score;
}

/// إخراج مولّد محلي مع إسناده — بلا إسناد صحيح لا يُقبل.
class GeneratedOutput {
  const GeneratedOutput({required this.text, required this.citedIndexes});

  final String text;
  final List<int> citedIndexes;
}

/// واجهة المولّد المحلي — خانة النموذج (تملأ في 1.18.0 بقياس ميداني).
abstract class LocalGenerator {
  Future<GeneratedOutput?> generate(RagContextPack pack);
}

/// حزمة السياق المقدمة للمولّد — ميزانية أحرف صارمة منسحبة من الأضعف صلةً.
class RagContextPack {
  RagContextPack({required this.question, required List<RagPassage> passages, int maxChars = 1200})
      : _maxChars = maxChars {
    final ordered = [...passages]..sort((a, b) => b.score.compareTo(a.score));
    var used = question.length;
    for (final p in ordered) {
      final cost = p.text.length + p.conversationId.length + p.dateIso.length + 8;
      if (used + cost > _maxChars) break;
      used += cost;
      this.passages.add(p);
    }
    this.passages.sort((a, b) => a.dateIso.compareTo(b.dateIso));
  }

  final String question;
  final List<RagPassage> passages = <RagPassage>[];
  final int _maxChars;

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

enum RagState { notEnough, extractive, generated }

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

class RagPipeline {
  RagPipeline({required this.retrieve, this.generator, this.maxChars = 1200});

  final List<RagPassage> Function(String question) retrieve;
  final LocalGenerator? generator;
  final int maxChars;

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

/// بوابة الجهاز للفهرسة الخلفية — حقنة الاختبار/طبقة النظام.
abstract class DeviceGate {
  bool get allowsProcessing;
}

class AlwaysAllowGate implements DeviceGate {
  @override
  bool get allowsProcessing => true;
}

/// مجدول الفهرسة الخلفية بأولوية منخفضة: البوابة تُسأل قبل كل عنصر —
/// الرفض يوقف فوراً والاستدعاء القادم يكمل من حيث توقف.
class IndexScheduler {
  IndexScheduler({required this.gate, this.batchSize = 20});

  final DeviceGate gate;
  final int batchSize;

  final List<String> _queue = <String>[];
  bool _running = false;

  int get pending => _queue.length;

  void enqueue(Iterable<String> ids) {
    for (final id in ids) {
      if (!_queue.contains(id)) _queue.add(id);
    }
  }

  Future<void> drain(Future<void> Function(String id) indexOne) async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        if (!gate.allowsProcessing) return;
        final batch = _queue.take(batchSize).toList();
        for (final id in batch) {
          if (!gate.allowsProcessing) return;
          await indexOne(id);
          _queue.remove(id);
        }
      }
    } finally {
      _running = false;
    }
  }
}

/// موافقة صريحة لمرة واحدة على توليد ملخص محلي — المنحة تُستهلك بالاستخدام.
class OneShotConsent {
  bool _granted = false;

  void grant() => _granted = true;

  bool get isGranted => _granted;

  bool consume() {
    final ok = _granted;
    _granted = false;
    return ok;
  }
}

// ————— طبقة خدمة التطبيق: الاسترجاع من خدمتنا القائمة + مجدول جاهز —————

class RagService {
  RagService._();

  /// عتبة الصلة نفسها المعلنة في «اسأل وصل» الاستخلاصي — بلا تزيين
  static const double minScore = AskWaslService.minScore;

  /// ميزانية حزمة السياق الافتراضية (أحرف) — سقف صارم يمنع تضخم السياق
  static const int contextBudget = 1200;

  /// المجدول المشترك للفهرسة الخلفية — البوابة تُستبدل من طبقة النظام
  /// (بطارية/حرارة) عند قرار الاعتمادية الأصلية؛ الافتراضي يسمح.
  static IndexScheduler scheduler =
      IndexScheduler(gate: AlwaysAllowGate());

  /// الإجابة الكاملة: استرجاع محلي → ميزانية → مولّد إن وُجد → إسناد متحقق.
  /// [generator] null اليوم فالسلوك استخلاصي معلن المصدر كما هو — وعندما
  /// يُربط النموذج المحلي يمر كل إخراج عبر بوابة الإسناد حصراً.
  static Future<RagAnswer> answer(
    List<AskPassage> passages,
    String question, {
    LocalGenerator? generator,
    int? contextBudget,
  }) {
    final lines = AskWaslService.answer(passages, question);
    final found = lines == null
        ? const <RagPassage>[]
        : lines.lines
            .map((l) => RagPassage(
                  conversationId: l.conversationId,
                  text: l.text,
                  dateIso: l.atIso,
                  score: l.score,
                ))
            .toList();
    final pipe = RagPipeline(
      retrieve: (_) => found,
      generator: generator,
      maxChars: contextBudget ?? RagService.contextBudget,
    );
    return pipe.answer(question);
  }

  /// موافقات الملخصات المولدة — كائن لكل ملخص: منحة تُستهلك بالاستخدام
  /// (الخارطة: «بموافقة صريحة في كل مرة» حرفياً)
  static OneShotConsent newSummaryConsent() => OneShotConsent();
}
