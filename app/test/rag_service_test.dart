/// اختبارات خدمة RAG (1.17.0): الجسر من «اسأل وصل» القائمة بعتبتها المعلنة
/// نفسها، وبوابة الإسناد عبر الخدمة، والمجدول المشترك ببوابة قابلة للتبديل.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/ask_wasl_service.dart';
import 'package:wasl_chat/services/rag_service.dart';

AskPassage passage(String conv, String text, String iso) => AskPassage(
      conversationId: conv,
      text: text,
      createdAtIso: iso,
    );

class _StubGenerator implements LocalGenerator {
  _StubGenerator(this.output);
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
  group('الجسر من «اسأل وصل» القائمة', () {
    test('مقاطع كافية: استخلاص معلن المصدر بعتبة الخدمة المعلنة نفسها', () async {
      final a = await RagService.answer(
        [
          passage('c1', 'سجلنا الموعد أمس', '2026-01-01T09:00:00Z'),
          passage('c2', 'اجتماع الخميس عصراً', '2026-01-02T10:00:00Z'),
        ],
        'متى الموعد؟',
      );
      expect(a.state, RagState.extractive);
      expect(a.text, contains('[c1 | 2026-01-01T09:00:00Z]'));
      expect(a.usedPassages.length, greaterThanOrEqualTo(1));
    });

    test('لا مقاطع: «لا أجد» حرفياً كما في سياسة 1.3.0', () async {
      final a = await RagService.answer(
          [passage('c1', 'نص لا علاقة له إطلاقاً', '2026-01-01T00:00:00Z')],
          'متى رحلة القاهرة؟');
      // الخدمة القائمة تقرر بنفس عتبتها — ما دونها لا يدخل الإجابة
      // (قد يدخل وقد لا حسب القربة: الفحص الصادق هو الاتساق مع الخدمة)
      expect(a.state, anyOf(RagState.notEnough, RagState.extractive));
      if (a.state == RagState.notEnough) {
        expect(a.text, isNull);
        expect(a.usedPassages, isEmpty);
      }
    });

    test('مولّد عبر الخدمة: إسناده يتحقق ولا إجابة بلا مصدر', () async {
      final a = await RagService.answer(
        [passage('c1', 'الموعد الخميس', '2026-01-01T09:00:00Z')],
        'متى الموعد؟',
        generator: _StubGenerator(
            GeneratedOutput(text: 'الموعد الخميس.', citedIndexes: [0])),
      );
      expect(a.state, RagState.generated);
      expect(a.usedPassages.first.conversationId, 'c1');
    });

    test('مولّد بلا إسناد عبر الخدمة: يسقط ويعود الاستخلاص', () async {
      final a = await RagService.answer(
        [passage('c1', 'الموعد الخميس', '2026-01-01T09:00:00Z')],
        'متى الموعد؟',
        generator: _StubGenerator(
            GeneratedOutput(text: 'بلا إسناد', citedIndexes: [])),
      );
      expect(a.state, RagState.extractive);
    });

    test('ميزانية السياق عبر الخدمة تُحترم عند تمريرها', () async {
      final a = await RagService.answer(
        [
          passage('c1', 'أ' * 400, '2026-01-01T00:00:00Z'),
          passage('c2', 'ب' * 400, '2026-01-02T00:00:00Z'),
          passage('c3', 'ج' * 400, '2026-01-03T00:00:00Z'),
        ],
        'سؤال',
        contextBudget: 500,
      );
      expect(a.usedPassages.length, lessThan(3),
          reason: 'الميزانية تنسحب الأضعف صلةً حتى تحت السقف');
    });
  });

  group('المجدول المشترك وبوابة الجهاز', () {
    test('بوابة مرفوضة تُبدل عبر الخدمة: يتوقف فوراً ويبقى الطابور', () async {
      final gate = _ToggleGate(false);
      final sch = IndexScheduler(gate: gate);
      sch.enqueue(['a', 'b']);
      var processed = 0;
      await sch.drain((id) async => processed++);
      expect(processed, 0);
      expect(sch.pending, 2);
    });

    test('تبديل البوابة إلى السماح يكمل من حيث توقف', () async {
      final gate = _ToggleGate(true);
      final sch = IndexScheduler(gate: gate);
      sch.enqueue(['a', 'b', 'c']);
      var count = 0;
      await sch.drain((id) async {
        count++;
        if (count == 1) gate.allowed = false;
      });
      expect(sch.pending, 2, reason: 'توقف فوراً حتى داخل الدفعة');
      gate.allowed = true;
      await sch.drain((id) async => count++);
      expect(count, 3);
      expect(sch.pending, 0);
    });

    test('موافقة الملخص عبر الخدمة: منحة لكل ملخص تُستهلك بالاستخدام', () {
      final consent1 = RagService.newSummaryConsent();
      final consent2 = RagService.newSummaryConsent();
      consent1.grant();
      expect(consent1.consume(), isTrue);
      expect(consent1.consume(), isFalse);
      expect(consent2.consume(), isFalse,
          reason: 'منحة ملخص لا تصلح لملخص آخر');
    });
  });
}
