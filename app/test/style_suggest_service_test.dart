/// اختبارات خانة النموذج المحلي للصياغة (1.18.0): البوابة تقرر قبل الحماس —
/// بلا مولد أو بند لم يقاس أو مؤجل → الصياغة الإحصائية كما هي بإعلان صادق؛
/// المولد المسموح فقط يمر عبر تحقق الصياغات (فريدة وغير فارغة وبحد الثلاثة).
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/style_assist_service.dart';
import 'package:wasl_chat/services/style_suggest_service.dart';

class _StubGenerator implements LocalStyleGenerator {
  _StubGenerator(this.output);
  final List<String>? output;
  @override
  Future<List<String>?> suggest(StyleBrief brief) async => output;
}

void main() {
  setUp(() {
    // كل اختبار يبدأ بسجل نظيف — لا تسرب أحكام بين الاختبارات
    StyleSuggestService.ledger.resetForTests();
  });

  group('البوابة تقرر قبل الحماس', () {
    test('بلا مولد: إحصائي كما هو بثلاث صياغات معلنة', () async {
      final r = await StyleSuggestService.suggest('أعتذر عن التأخير');
      expect(r.state, StyleSuggestState.statistical);
      expect(r.drafts, isNotEmpty);
      expect(r.disclosure, contains('إحصائية'));
      expect(r.disclosure, isNot(contains('مولدة')));
    });

    test('مولد مربوط وبند لم يقاس أصلاً: مؤجل بالبوابة — لا شحن بلا قياس', () async {
      final r = await StyleSuggestService.suggest(
        'أعتذر عن التأخير',
        generator: _StubGenerator(['صيغة أولى', 'صيغة ثانية', 'صيغة ثالثة']),
      );
      expect(r.state, StyleSuggestState.gateDeferred);
      expect(r.drafts, isNotEmpty, reason: 'الإحصائي يبقى المتاح');
      expect(r.disclosure, contains('مؤجلة'));
      expect(r.disclosure, contains('القياس'));
    });

    test('مولد مربوط وبند مؤجل بالقياس: مؤجل أيضاً', () async {
      StyleSuggestService.ledger.declare(GateResult(
        feature: StyleSuggestService.feature,
        verdict: GateVerdict.deferred,
        reasons: ['الإنتاجية 8 رمز/ثانية تحت العتبة المعلنة 20'],
        measurement: FieldMeasurement(
          feature: StyleSuggestService.feature,
          tokensPerSec: 8,
          ttftMs: 4000,
          batteryPctDrainPerMin: 2.0,
          thermalThrottled: true,
          deviceRamMb: 4096,
        ),
      ));
      final r = await StyleSuggestService.suggest(
        'سؤال',
        generator: _StubGenerator(['أ', 'ب', 'ج']),
      );
      expect(r.state, StyleSuggestState.gateDeferred);
    });

    test('بند اجتاز قياسه: الاقتراحات المولدة تُعرض بأسلوبها المعلن', () async {
      StyleSuggestService.ledger.declare(GateResult(
        feature: StyleSuggestService.feature,
        verdict: GateVerdict.pass,
        reasons: const [],
        measurement: FieldMeasurement(
          feature: StyleSuggestService.feature,
          tokensPerSec: 26,
          ttftMs: 1400,
          batteryPctDrainPerMin: 0.4,
          thermalThrottled: false,
          deviceRamMb: 6144,
        ),
      ));
      final r = await StyleSuggestService.suggest(
        'أعتذر عن التأخير',
        generator: _StubGenerator(['أعتذر لكم عن التأخير', 'آسف على التأخر', 'أعتذر، تأخرت عن الموعد']),
      );
      expect(r.state, StyleSuggestState.generated);
      expect(r.drafts.length, 3);
      expect(r.drafts.every((d) => d.label == 'بأسلوبك (محلي)'), isTrue);
      expect(r.drafts.first.text, 'أعتذر لكم عن التأخير');
      expect(r.disclosure, contains('اجتاز قياسه'));
    });

    test('مولد يرفض (null) بعد اجتياز البوابة: يعود الإحصائي بلا ادعاء', () async {
      StyleSuggestService.ledger.declare(GateResult(
        feature: StyleSuggestService.feature,
        verdict: GateVerdict.pass,
        reasons: const [],
        measurement: FieldMeasurement(
          feature: StyleSuggestService.feature,
          tokensPerSec: 26,
          ttftMs: 1400,
          batteryPctDrainPerMin: 0.4,
          thermalThrottled: false,
          deviceRamMb: 6144,
        ),
      ));
      final r = await StyleSuggestService.suggest(
          'سؤال', generator: _StubGenerator(null));
      expect(r.state, StyleSuggestState.statistical);
    });
  });

  group('تحقق الصياغات المولدة', () {
    GateResult makePass() => GateResult(
          feature: StyleSuggestService.feature,
          verdict: GateVerdict.pass,
          reasons: const [],
          measurement: FieldMeasurement(
            feature: StyleSuggestService.feature,
            tokensPerSec: 26,
            ttftMs: 1400,
            batteryPctDrainPerMin: 0.4,
            thermalThrottled: false,
            deviceRamMb: 6144,
          ),
        );

    setUp(() => StyleSuggestService.ledger.declare(makePass()));

    test('الفراغات والمكررات تُسقط ويمتد الحد إلى ثلاثة', () async {
      final r = await StyleSuggestService.suggest(
        'سؤال',
        generator: _StubGenerator([
          'صيغة فريدة',
          'صيغة فريدة', // مكرر — يسقط
          '  ', // فارغ — يسقط
          'صيغة أخرى',
          'صيغة ثالثة',
          'رابعة فوق الحد', // يتجاوز الثلاثة — يسقط
        ]),
      );
      expect(r.state, StyleSuggestState.generated);
      expect(r.drafts.length, 3);
      expect(r.drafts.map((d) => d.text).toList(),
          ['صيغة فريدة', 'صيغة أخرى', 'صيغة ثالثة']);
    });

    test('بلا أي صياغة صالحة: يعود الإحصائي بلا ادعاء توليد', () async {
      final r = await StyleSuggestService.suggest(
          'سؤال', generator: _StubGenerator(['', '  ', '']));
      expect(r.state, StyleSuggestState.statistical);
    });
  });

  group('حزمة التغذية StyleBrief', () {
    test('الأسلوب والسياق والسقف: السياق يُقص من الأقدم ويبقى الأحدث', () {
      final brief = StyleBrief(
        hint: 'ما رأيك؟',
        profile: const StyleProfile(
          formality: 0.2,
          avgWords: 6.5,
          emojiRate: 0.3,
          topOpeners: ['طيب'],
          topClosers: ['شكراً'],
          sampleCount: 42,
        ),
        recentContext: [
          'رسالة قديمة جداً ' * 30, // كبيرة — تسقط بالسقف
          'أهلاً',
          'كيف الشغل؟',
        ],
        maxChars: 300,
      );
      expect(brief.context, ['أهلاً', 'كيف الشغل؟'],
          reason: 'الأحدث يبقى والقديم الثقيل يسقط');
      final rendered = brief.render();
      expect(rendered, contains('ما رأيك؟'));
      expect(rendered, contains('20%')); // الرسمية كما قاست
      expect(rendered, contains('30%')); // الإيموجي كما قاست
      expect(rendered, contains('42 رسالة'));
      expect(rendered, contains('طيب'));
      expect(rendered, contains('كيف الشغل؟'));
    });

    test('بلا بيانات أسلوب: يعلن صراحة «بلا بيانات كافية» لا يخترع', () {
      final brief = StyleBrief(hint: 'س', profile: StyleProfile.neutral);
      expect(brief.render(), contains('بلا بيانات كافية'));
    });
  });
}
