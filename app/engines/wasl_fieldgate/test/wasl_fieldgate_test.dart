/// اختبارات بوابة القياس الميداني: العتبات قبل القياس، الحكم الثنائي بأسباب
/// مجتمعة، منع قلب المؤجل منشوراً، وتقرير الشفافية بأرقام القياس الحرفية.
import 'package:test/test.dart';
import 'package:wasl_fieldgate/wasl_fieldgate.dart';

FieldMeasurement m({
  String feature = 'llm_suggestions',
  int tokensPerSec = 25,
  int ttftMs = 1500,
  double battery = 0.5,
  bool thermal = false,
  int ram = 6144,
  Map<String, String> notes = const {},
}) =>
    FieldMeasurement(
      feature: feature,
      tokensPerSec: tokensPerSec,
      ttftMs: ttftMs,
      batteryPctDrainPerMin: battery,
      thermalThrottled: thermal,
      deviceRamMb: ram,
      notes: notes,
    );

void main() {
  group('الحكم بالعتبات المعلنة', () {
    test('قياس فوق كل العتبات: يجتاز بلا أسباب', () {
      final r = FieldGate.judge(m(), FeatureThresholds.defaults('llm_suggestions'));
      expect(r.verdict, GateVerdict.pass);
      expect(r.reasons, isEmpty);
      expect(r.shippable, isTrue);
    });

    test('عتبة القياس نفسها من أرقام الخارطة: 20 رمز/ث وأول رمز 2000 م.ث', () {
      final t = FeatureThresholds.defaults('llm_suggestions');
      expect(t.minTokensPerSec, 20);
      expect(t.maxTtftMs, 2000);
      expect(t.minDeviceRamMb, 4096);
    });

    test('الحد الأدنى بالضبط يجتاز (المساواة تعبر لا تفشل)', () {
      final r = FieldGate.judge(
        m(tokensPerSec: 20, ttftMs: 2000, battery: 1.0, ram: 4096),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.verdict, GateVerdict.pass);
    });

    test('الإنتاجية تحت العتبة: سبب صريح بالرقمين معاً', () {
      final r = FieldGate.judge(
        m(tokensPerSec: 12),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.verdict, GateVerdict.deferred);
      expect(r.reasons.length, 1);
      expect(r.reasons.first, contains('12'));
      expect(r.reasons.first, contains('20'));
    });

    test('زمن أول رمز فوق السقف: سبب صريح', () {
      final r = FieldGate.judge(
        m(ttftMs: 3100),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.reasons.first, contains('3100'));
      expect(r.reasons.first, contains('2000'));
    });

    test('استنزاف البطارية فوق السقف: سبب صريح', () {
      final r = FieldGate.judge(
        m(battery: 2.5),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.reasons.first, contains('2.5'));
    });

    test('تعثر حراري: سبب صريح — ويُسمح فقط حين تعلن العتبات سماحه', () {
      final r = FieldGate.judge(
        m(thermal: true),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.verdict, GateVerdict.deferred);
      expect(r.reasons.first, contains('حراري'));
      final lenient = FeatureThresholds.defaults('whisper_transcribe')
          .copyWith(allowThermalThrottle: true);
      final r2 = FieldGate.judge(
          m(feature: 'whisper_transcribe', thermal: true), lenient);
      expect(r2.verdict, GateVerdict.pass);
    });

    test('ذاكرة تحت الحد: سبب صريح', () {
      final r = FieldGate.judge(
        m(ram: 3072),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.reasons.first, contains('3072'));
    });

    test('فشل متعدد: كل الأسباب تجمع لا أولها', () {
      final r = FieldGate.judge(
        m(tokensPerSec: 8, ttftMs: 4500, battery: 3.0, ram: 2048),
        FeatureThresholds.defaults('llm_suggestions'),
      );
      expect(r.verdict, GateVerdict.deferred);
      expect(r.reasons.length, 4);
    });

    test('عتبات بند آخر على قياس بند: خطأ صريح لا حكم خاطئ', () {
      expect(
        () => FieldGate.judge(
            m(feature: 'neural_translate'),
            FeatureThresholds.defaults('llm_suggestions')),
        throwsArgumentError,
      );
    });
  });

  group('سجل الحكم — منع قلب المؤجل منشوراً', () {
    test('بند لم يقاس أصلاً: لا يجوز شحنه', () {
      final ledger = GateLedger();
      expect(ledger.canShip('whisper_transcribe'), isFalse);
      expect(ledger.latest('whisper_transcribe'), isNull);
    });

    test('حكم مؤجل يحجب الشحن حتى قياس جديد يجتاز', () {
      final ledger = GateLedger();
      ledger.declare(FieldGate.judge(
          m(tokensPerSec: 10), FeatureThresholds.defaults('llm_suggestions')));
      expect(ledger.canShip('llm_suggestions'), isFalse);
      ledger.declare(FieldGate.judge(
          m(tokensPerSec: 26), FeatureThresholds.defaults('llm_suggestions')));
      expect(ledger.canShip('llm_suggestions'), isTrue,
          reason: 'الحكم الجديد بقياس جديد كامل يحل محل القديم');
    });

    test('عكسه أيضاً: قياس جديد فاشل يلغي إذن شحن سابق', () {
      final ledger = GateLedger();
      ledger.declare(FieldGate.judge(
          m(feature: 'neural_translate'),
          FeatureThresholds.defaults('neural_translate')));
      expect(ledger.canShip('neural_translate'), isTrue);
      ledger.declare(FieldGate.judge(m(
              feature: 'neural_translate', tokensPerSec: 5, ttftMs: 9000),
          FeatureThresholds.defaults('neural_translate')));
      expect(ledger.canShip('neural_translate'), isFalse);
    });

    test('قائمة المؤجلين تعكس السجل الحالي', () {
      final ledger = GateLedger();
      ledger.declare(FieldGate.judge(
          m(feature: 'a'), FeatureThresholds.defaults('a')));
      ledger.declare(FieldGate.judge(
          m(feature: 'b', tokensPerSec: 1),
          FeatureThresholds.defaults('b')));
      ledger.declare(FieldGate.judge(
          m(feature: 'c', tokensPerSec: 1),
          FeatureThresholds.defaults('c')));
      expect(ledger.deferredFeatures, ['b', 'c']);
    });
  });

  group('تقرير الشفافية', () {
    test('الأرقام تظهر كما قست حرفياً والمؤجل بعلامته وسببه', () {
      final passed = FieldGate.judge(
          m(feature: 'llm_suggestions', tokensPerSec: 24, notes: {'النموذج': 'Qwen3-0.6B Q4_K_M'}),
          FeatureThresholds.defaults('llm_suggestions'));
      final failed = FieldGate.judge(
          m(feature: 'whisper_transcribe', tokensPerSec: 6, ttftMs: 5200, battery: 2.2, thermal: true, ram: 3800),
          FeatureThresholds.defaults('whisper_transcribe'));
      final report = TransparencyReport.render(
        [passed, failed],
        measuredAtIso: '2026-11-20T10:00:00Z',
        deviceSummary: 'أندرويد 4GB RAM',
      );
      expect(report, contains('2026-11-20T10:00:00Z'));
      expect(report, contains('أندرويد 4GB RAM'));
      expect(report, contains('24 رمز/ث'));
      expect(report, contains('1500 م.ث'));
      expect(report, contains('يجتاز'));
      expect(report, contains('Qwen3-0.6B Q4_K_M'));
      expect(report, contains('مؤجل'));
      expect(report, contains('5200'));
      expect(report, contains('سبب التأجيل'));
      expect(report, contains('حراري'));
    });

    test('بلا بنود مقيسة: التقرير يعلن ذلك صادقاً', () {
      final report = TransparencyReport.render(
        [],
        measuredAtIso: '2026-11-20T10:00:00Z',
        deviceSummary: 'أندرويد 4GB RAM',
      );
      expect(report, contains('لا بنود مقيسة بعد'));
      expect(report, contains('مؤجلة'));
    });
  });
}
