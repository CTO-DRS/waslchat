import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/call_quality_service.dart';

/// اختبارات نقية لخدمة جودة المكالمة والرن فوق القفل (المرحلة 11 أ — 0.26.0) —
/// بلا شبكة ولا WebRTC: التصنيف وجهاز الاستقرار والتكييف وتحليل الإحصاءات
/// وقرار العرض وحارس الاستئناف كلها قرارات محلية تُثبت هنا قبل أي اتصال حقيقي.
void main() {
  group('التصنيف القاعدي', () {
    test('حدود ممتازة: RTT 100 وجيتر 40 وفقدان 1% تظل ممتازة', () {
      final l = classifySample(const QualitySample(
          rttMs: 100, jitterMs: 40, lossRate: 0.01));
      expect(l, CallQualityLevel.excellent);
    });

    test('تجاوز العتبات يهبط بالمستوى الصادق', () {
      expect(
        classifySample(const QualitySample(rttMs: 101)),
        CallQualityLevel.good,
      );
      expect(
        classifySample(const QualitySample(rttMs: 251)),
        CallQualityLevel.weak,
      );
      expect(
        classifySample(const QualitySample(rttMs: 501)),
        CallQualityLevel.poor,
      );
      // الجيتر وحده يهبط
      expect(
        classifySample(const QualitySample(jitterMs: 81)),
        CallQualityLevel.poor,
      );
      // الفقدان وحده يهبط
      expect(
        classifySample(const QualitySample(lossRate: 0.09)),
        CallQualityLevel.poor,
      );
      expect(
        classifySample(const QualitySample(lossRate: 0.05)),
        CallQualityLevel.weak,
      );
    });

    test('عيّنة فارغة تماماً (بلا أي قياس) تعيد التصنيف المحايد', () {
      final l = classifySample(const QualitySample());
      expect(l, CallQualityLevel.good); // لا تخمين بالعتبات — محايد
    });
  });

  group('تحليل إحصاءات getStats الخام', () {
    test('زوج مرشّح ناجح يعطي RTT بالمللي ثانية (من الثواني)', () {
      final s = parseQualitySample([
        (
          'candidate-pair',
          {'state': 'succeeded', 'currentRoundTripTime': 0.15}
        ),
      ]);
      expect(s.rttMs, closeTo(150, 0.001));
    });

    test('زوج غير ناجح يُتجاهل ولا يفسّر RTT', () {
      final s = parseQualitySample([
        (
          'candidate-pair',
          {'state': 'failed', 'currentRoundTripTime': 0.15}
        ),
      ]);
      expect(s.rttMs, isNull);
    });

    test('inbound-rtp يعطي جيتراً ونسبة فقدان ومستوى صوتي', () {
      final s = parseQualitySample([
        (
          'inbound-rtp',
          {
            'jitter': 0.03,
            'packetsLost': 5,
            'packetsReceived': 95,
            'audioLevel': 0.7,
          }
        ),
      ]);
      expect(s.jitterMs, closeTo(30, 0.001));
      expect(s.lossRate, closeTo(0.05, 0.0001));
      expect(s.audioLevel, closeTo(0.7, 0.0001));
    });

    test('totalAudioEnergy/totalSamplesDuration بديل صادق للمستوى', () {
      final s = parseQualitySample([
        (
          'inbound-rtp',
          {'totalAudioEnergy': 0.4, 'totalSamplesDuration': 2.0}
        ),
      ]);
      expect(s.audioLevel, closeTo(0.2, 0.0001));
    });

    test('أي غرابة لا ترمي استثناءً: قيم نصية وأنواع غريبة وخريطة فارغة', () {
      final s = parseQualitySample([
        ('candidate-pair', {'currentRoundTripTime': 'not-a-number'}),
        ('weird-type', {'audioLevel': 999}),
        ('inbound-rtp', {'audioLevel': -3}),
        ('inbound-rtp', <dynamic, dynamic>{}),
      ]);
      expect(s.rttMs, isNull);
      expect(s.audioLevel, isNull);
      expect(s.empty, isTrue);
    });

    test('النطاق المسموح للمستوى الصوتي 0..1 حصراً', () {
      final s = parseQualitySample([
        ('inbound-rtp', {'audioLevel': 1.5}),
        ('media-source', {'audioLevel': 0.5}),
      ]);
      expect(s.audioLevel, closeTo(0.5, 0.0001));
    });
  });

  group('جهاز الاستقرار (hysteresis)', () {
    CallQualityGate gateWith(List<QualitySample> samples) {
      final g = CallQualityGate();
      for (final s in samples) {
        g.add(s);
      }
      return g;
    }

    test('يؤسس المستوى من أول عينتين متطابقتين لا من واحدة', () {
      final g = CallQualityGate();
      expect(g.add(const QualitySample(rttMs: 60)), isNull);
      expect(g.add(const QualitySample(rttMs: 60)), CallQualityLevel.excellent);
    });

    test('عينة ضعيفة وحيدة لا تُسقط ممتازاً — لا وميض', () {
      final g = gateWith([
        const QualitySample(rttMs: 60),
        const QualitySample(rttMs: 60),
      ]);
      expect(g.current, CallQualityLevel.excellent);
      final after = g.add(const QualitySample(rttMs: 600)); // poor وحده
      expect(after, CallQualityLevel.excellent);
    });

    test('عينتان متتاليتان تتحركان الشارة خطوة واحدة كحد أقصى', () {
      final g = gateWith([
        const QualitySample(rttMs: 60),
        const QualitySample(rttMs: 60),
        const QualitySample(rttMs: 600), // weak وحدها لا تُسقط
        const QualitySample(rttMs: 600), // متتالية: خطوة إلى جيد
      ]);
      expect(g.current, CallQualityLevel.good);
      g.add(const QualitySample(rttMs: 600));
      expect(g.current, CallQualityLevel.weak);
      g.add(const QualitySample(rttMs: 600));
      expect(g.current, CallQualityLevel.poor);
    });

    test('التحسن يحتاج عينتين متتاليتين كذلك', () {
      final g = gateWith([
        const QualitySample(rttMs: 600),
        const QualitySample(rttMs: 600),
        const QualitySample(rttMs: 600),
        const QualitySample(rttMs: 60),
      ]);
      expect(g.current, CallQualityLevel.poor);
      g.add(const QualitySample(rttMs: 60));
      expect(g.current, CallQualityLevel.weak);
    });

    test('إعادة الضبط تمحو كل شيء — لا ذاكرة', () {
      final g = gateWith([
        const QualitySample(rttMs: 600),
        const QualitySample(rttMs: 600),
        const QualitySample(rttMs: 600),
      ]);
      g.reset();
      expect(g.current, isNull);
      expect(g.add(const QualitySample(rttMs: 600)), isNull);
    });

    test('عيّنة فارغة لا تلمس المستوى ولا الذاكرة', () {
      final g = gateWith([
        const QualitySample(rttMs: 60),
        const QualitySample(rttMs: 60),
      ]);
      expect(g.add(const QualitySample()), CallQualityLevel.excellent);
    });
  });

  group('التكييف الصادق', () {
    test('مرئية ضعيفة وكاميرا تعمل → ملاحظة فقط لا إطفاء', () {
      expect(
        decideAdaptation(CallQualityLevel.weak,
            isVideo: true, cameraOn: true, alreadyAdapted: false),
        CallAdaptation.noteOnly,
      );
    });

    test('مرئية ضعيفة وكاميرا مقفلة أصلاً → ملاحظة تبقى مفيدة بلا إطفاء', () {
      expect(
        decideAdaptation(CallQualityLevel.weak,
            isVideo: true, cameraOn: false, alreadyAdapted: false),
        CallAdaptation.noteOnly,
      );
    });

    test('مرئية سيئة وكاميرا تعمل → إطفاء الكاميرا مرة واحدة', () {
      expect(
        decideAdaptation(CallQualityLevel.poor,
            isVideo: true, cameraOn: true, alreadyAdapted: false),
        CallAdaptation.dimCamera,
      );
      // وبعد التكيف لا قرار آخر أبداً — الإعادة بيد المستخدم
      expect(
        decideAdaptation(CallQualityLevel.poor,
            isVideo: true, cameraOn: true, alreadyAdapted: true),
        CallAdaptation.none,
      );
    });

    test('صوتية سيئة → ملاحظة فقط، الصوت لا يُطفأ أبداً', () {
      expect(
        decideAdaptation(CallQualityLevel.poor,
            isVideo: false, cameraOn: false, alreadyAdapted: false),
        CallAdaptation.noteOnly,
      );
    });

    test('كل ملاحظة لها نص صادق ولا نص لـ none', () {
      expect(adaptationNote(CallAdaptation.none), isNull);
      expect(adaptationNote(CallAdaptation.noteOnly), isNotNull);
      expect(adaptationNote(CallAdaptation.dimCamera), contains('كاميرتك'));
    });
  });

  group('قرار عرض المكالمة الواردة', () {
    test('التطبيق أمام المستخدم → شاشة التطبيق كما اليوم', () {
      expect(
        decidePresentation(appResumed: true),
        CallAlertPresentation.inAppScreen,
      );
    });

    test('التطبيق بالخلفية أو ميت → إشعار ملء الشاشة يرن فوق القفل', () {
      expect(
        decidePresentation(appResumed: false),
        CallAlertPresentation.fullScreenNotification,
      );
    });
  });

  group('إعداد إشعار الرن وحارس الاستئناف', () {
    test('نص الإشعار صادق بالنوع والاسم', () {
      expect(CallAlert.body(callerName: 'سالم', video: false),
          'سالم يتصل بك صوتياً');
      expect(CallAlert.body(callerName: 'سالم', video: true),
          'سالم يتصل بك مرئياً');
    });

    test('معرّف الإشعار مستقر لنفس المحادثة ومختلف لغيرها', () {
      final a = CallAlert.notifId('conv-1');
      expect(CallAlert.notifId('conv-1'), a);
      expect(CallAlert.notifId('conv-2'), isNot(a));
    });

    test('حارس الاستئناف: رنّة حية أنا المستدعى داخل المهلة فقط', () {
      expect(
        CallAlert.resumeEligible(
            status: 'ringing', iAmCallee: true, age: const Duration(seconds: 10)),
        isTrue,
      );
      // ليست رنّة
      expect(
        CallAlert.resumeEligible(
            status: 'answered', iAmCallee: true, age: const Duration(seconds: 1)),
        isFalse,
      );
      // أنا الطالب
      expect(
        CallAlert.resumeEligible(
            status: 'ringing', iAmCallee: false, age: const Duration(seconds: 1)),
        isFalse,
      );
      // انتهت مهلة الرنين
      expect(
        CallAlert.resumeEligible(
            status: 'ringing',
            iAmCallee: true,
            age: const Duration(seconds: 50)),
        isFalse,
      );
      // عمر سالب (ساعة الجهاز) لا يقبل
      expect(
        CallAlert.resumeEligible(
            status: 'ringing',
            iAmCallee: true,
            age: const Duration(seconds: -5)),
        isFalse,
      );
    });
  });

  group('تسميات الشارة', () {
    test('كل مستوى له تسمية وأيقونة ولون — بلا فراغ', () {
      for (final l in CallQualityLevel.values) {
        expect(CallQualityView.label(l), isNotEmpty);
        // الوصول لقيم العناصر يثبت أنها مبنية بلا استثناء
        expect(CallQualityView.icon(l), isNotNull);
        expect(CallQualityView.color(l), isNotNull);
      }
      expect(CallQualityView.label(CallQualityLevel.poor), 'الشبكة ضعيفة');
      expect(CallQualityView.label(CallQualityLevel.excellent), 'الشبكة ممتازة');
    });
  });
}
