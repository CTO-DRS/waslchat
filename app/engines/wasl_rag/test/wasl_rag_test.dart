/// اختبارات محرك wasl_rag: عقد الإسناد المفروض، ميزانية الحزمة، حرفية
/// «لا أجد»، توقف المجدول على بوابة الجهاز، واستهلاك الموافقة الواحدة.
import 'package:test/test.dart';
import 'package:wasl_rag/wasl_rag.dart';

RagPassage p(String conv, String text, String date, double score) =>
    RagPassage(conversationId: conv, text: text, dateIso: date, score: score);

class _FixedGenerator implements LocalGenerator {
  _FixedGenerator(this.output);
  final GeneratedOutput? output;
  @override
  Future<GeneratedOutput?> generate(RagContextPack pack) async => output;
}

class _ToggleGate implements DeviceGate {
  _ToggleGate(this.allowed);
  bool allowed;
  @override
  bool get allowsProcessing => allowed;
}

void main() {
  group('خط الأنابيب — العقد الصادق', () {
    test('لا مقاطع فوق العتبة: «لا أجد» حرفياً بلا نص ولا ادعاء', () async {
      final pipe = RagPipeline(retrieve: (_) => <RagPassage>[]);
      final a = await pipe.answer('أي سؤال');
      expect(a.state, RagState.notEnough);
      expect(a.text, isNull);
      expect(a.usedPassages, isEmpty);
    });

    test('بلا مولّد: استخلاص معلن المصدر — كل سطر بمصدر محادثته وتاريخه', () async {
      final passages = [
        p('c2', 'اجتماع الخميس الساعة عصراً', '2026-01-02T10:00:00Z', 0.4),
        p('c1', 'سجلنا الموعد أمس', '2026-01-01T09:00:00Z', 0.5),
      ];
      final pipe = RagPipeline(retrieve: (_) => passages);
      final a = await pipe.answer('متى الموعد؟');
      expect(a.state, RagState.extractive);
      final t = a.text!;
      // العرض زمني تصاعدي: أقدم المقاطع أولاً كي يُقرأ السياق كما جرى
      expect(t, contains('سجلنا الموعد أمس [c1 | 2026-01-01T09:00:00Z]'));
      expect(t, contains('اجتماع الخميس الساعة عصراً [c2 | 2026-01-02T10:00:00Z]'));
      expect(t.indexOf('c1'), lessThan(t.indexOf('c2')));
      expect(a.usedPassages.length, 2);
    });

    test('المولّد المسند تُقبل إجابته ومصادره هي المقاطع المُستشهد بها فقط', () async {
      final passages = [
        p('c1', 'نص أول', '2026-01-01T00:00:00Z', 0.5),
        p('c2', 'نص ثانٍ', '2026-01-02T00:00:00Z', 0.4),
      ];
      final pipe = RagPipeline(
        retrieve: (_) => passages,
        generator: _FixedGenerator(
            GeneratedOutput(text: 'الموعد يوم الخميس.', citedIndexes: [1])),
      );
      final a = await pipe.answer('متى الموعد؟');
      expect(a.state, RagState.generated);
      expect(a.text, 'الموعد يوم الخميس.');
      expect(a.usedPassages.map((x) => x.conversationId), ['c2']);
    });

    test('إخراج بلا إسناد يسقط ويعود الاستخلاص — العقد مفروض لا وعد', () async {
      final passages = [p('c1', 'نص أول', '2026-01-01T00:00:00Z', 0.5)];
      final pipe = RagPipeline(
        retrieve: (_) => passages,
        generator: _FixedGenerator(
            GeneratedOutput(text: 'إجابة بلا إسناد', citedIndexes: [])),
      );
      final a = await pipe.answer('سؤال');
      expect(a.state, RagState.extractive, reason: 'بلا إسناد صحيح لا توليد يُعرض');
    });

    test('فهارس خارج الحزمة تُسقط ويبقى الإسناد الصحيح فقط', () async {
      final passages = [p('c1', 'نص أول', '2026-01-01T00:00:00Z', 0.5)];
      final pipe = RagPipeline(
        retrieve: (_) => passages,
        generator: _FixedGenerator(GeneratedOutput(
            text: 'جزئياً مسند', citedIndexes: [0, 5, -1, 99])),
      );
      final a = await pipe.answer('سؤال');
      expect(a.state, RagState.generated);
      expect(a.usedPassages.length, 1);
      expect(a.usedPassages.first.conversationId, 'c1');
    });

    test('المولّد الرافض (null) يعيد الاستخلاص بلا ادعاء توليد', () async {
      final passages = [p('c1', 'نص', '2026-01-01T00:00:00Z', 0.5)];
      final pipe = RagPipeline(
          retrieve: (_) => passages, generator: _FixedGenerator(null));
      final a = await pipe.answer('سؤال');
      expect(a.state, RagState.extractive);
    });
  });

  group('حزمة السياق — الميزانية الصارمة', () {
    test('تنسحب الأضعف صلةً أولاً حتى تحت السقف، والباقي بترتيب زمني', () {
      final passages = [
        p('c1', 'أ' * 300, '2026-01-01T00:00:00Z', 0.9),
        p('c2', 'ب' * 300, '2026-01-02T00:00:00Z', 0.8),
        p('c3', 'ج' * 300, '2026-01-03T00:00:00Z', 0.2), // الأضعف — أول منسحب
      ];
      final pack = RagContextPack(
          question: 'س' * 10, passages: passages, maxChars: 700);
      expect(pack.passages.map((x) => x.conversationId), ['c1', 'c2']);
      final rendered = pack.render();
      expect(rendered.length, lessThanOrEqualTo(pack.maxChars + 40));
      expect(rendered, contains('c1'));
      expect(rendered, isNot(contains('c3')));
    });

    test('الميزانية المتسعة تحمل الجميع بترتيب زمني لا صلة', () {
      final passages = [
        p('c1', 'ثلاثة', '2026-01-03T00:00:00Z', 0.3),
        p('c2', 'اثنان', '2026-01-02T00:00:00Z', 0.9),
      ];
      final pack = RagContextPack(
          question: 'س', passages: passages, maxChars: 4000);
      expect(pack.passages.map((x) => x.conversationId).toList(), ['c2', 'c1']);
    });
  });

  group('مجدول الفهرسة الخلفية — التعثر والاستئناف', () {
    test('بوابة ترفض: يتوقف فوراً بلا معالجة ولا استهلاك طابور', () async {
      final gate = _ToggleGate(false);
      final sch = IndexScheduler(gate: gate, batchSize: 3);
      sch.enqueue(['a', 'b', 'c']);
      var processed = 0;
      await sch.drain((id) async => processed++);
      expect(processed, 0);
      expect(sch.pending, 3);
    });

    test('بوابة تسمح: تُعالج دفعة كاملة وتسأل البوابة بين الدفعات', () async {
      final gate = _ToggleGate(true);
      final sch = IndexScheduler(gate: gate, batchSize: 2);
      sch.enqueue(['a', 'b', 'c']);
      final gateAsks = <bool>[];
      final processed = <String>[];
      // نلفّ drain كي نسجل سؤال البوابة قبل كل دفعة
      await sch.drain((id) async {
        gateAsks.add(gate.allowed);
        processed.add(id);
      });
      expect(processed, ['a', 'b', 'c']);
      expect(sch.pending, 0);
    });

    test('تعثر في المنتصف: يبقى الباقي ويعود التشغيل الثاني يكمل', () async {
      final gate = _ToggleGate(true);
      final sch = IndexScheduler(gate: gate, batchSize: 5);
      sch.enqueue(['a', 'b']);
      var count = 0;
      await sch.drain((id) async {
        count++;
        if (count == 1) gate.allowed = false; // البطارية انخفضت بعد الأول
      });
      expect(sch.pending, 1, reason: 'بقي من حيث توقف');
      gate.allowed = true; // الشاحن وصل — يكمل
      await sch.drain((id) async => count++);
      expect(count, 2);
      expect(sch.pending, 0);
    });

    test('التشغيل المتوازي محظور — استدعاء ثانٍ لا يضاعف المعالجة', () async {
      final gate = _ToggleGate(true);
      final sch = IndexScheduler(gate: gate, batchSize: 5);
      sch.enqueue(['a']);
      final second = sch.drain((id) async {});
      await sch.drain((id) async {});
      await second;
      expect(sch.pending, 0);
    });

    test('المكررات تُقصى من الطابور', () {
      final sch = IndexScheduler(gate: _ToggleGate(true));
      sch.enqueue(['a', 'a', 'b']);
      expect(sch.pending, 2);
    });
  });

  group('الموافقة الصريحة لمرة واحدة', () {
    test('منحة واحدة تُستهلك بالاستخدام ثم تعود إلى عدم المنح', () {
      final c = OneShotConsent();
      expect(c.isGranted, isFalse);
      expect(c.consume(), isFalse);
      c.grant();
      expect(c.isGranted, isTrue);
      expect(c.consume(), isTrue, reason: 'المنحة الأولى صالحة للاستهلاك');
      expect(c.consume(), isFalse, reason: 'لا ملخصان بمنحة واحدة');
      expect(c.isGranted, isFalse);
    });
  });
}
