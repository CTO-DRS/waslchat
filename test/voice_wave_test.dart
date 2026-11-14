import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/voice_room_logic.dart';

/// اختبارات نقية لمؤشر «يتحدث» بموجات حية (المرحلة 11 أ — 0.26.0) —
/// بلا شبكة ولا WebRTC: المعايرة والعتبات والتباين والتنعيم وتحليل
/// الإحصاءات كلها قرارات محلية تُثبت هنا قبل أي اتصال حقيقي.
void main() {
  group('معايرة أرضية الضوضاء', () {
    test('الغرفة الهادئة: ضوضاء منخفضة لا تُشعل الموجة أبداً', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.01);
      }
      expect(w.speaking, isFalse);
      for (var i = 0; i < 5; i++) {
        w.add(0.015);
      }
      expect(w.speaking, isFalse);
    });

    test('أرضية الضوضاء لا تهبط تحت الحد الأدنى الصارم', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.0); // صمت تام — الأرضية تظل فوق الحد الأدنى
      }
      // عينات أعلى قليلاً من الصفر لكن تحت الحد الأدنى تظل هادئة
      for (var i = 0; i < 5; i++) {
        w.add(0.013);
      }
      expect(w.speaking, isFalse);
    });

    test('غرفة مزعجة: أرضية عالية تعاير العتبة فوقها فلا تشعل بالهمس', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.2); // ضجيج خلفي ثابت
      }
      w.add(0.22); // همس فوق الضجيج بقليل
      expect(w.speaking, isFalse);
    });
  });

  group('الإشعال والإخماد', () {
    test('صوت واضح يُشعل الموجة فوراً', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.02);
      }
      w.add(0.5);
      expect(w.speaking, isTrue);
    });

    test('الصمت بعد الكلام لا يُخمده فوراً — مهلة تراجع 400ms', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.02);
      }
      w.add(0.5);
      expect(w.speaking, isTrue);
      w.add(0.0); // أول عينة صمت — ما زالت مشتعلة (منع الوميض)
      expect(w.speaking, isTrue);
    });

    test('إعادة الضبط تمحو المعايرة والحالة', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.3);
      }
      w.reset();
      expect(w.speaking, isFalse);
      expect(w.level, 0);
    });
  });

  group('تنعيم المستوى المعروض', () {
    test('المستوى يصعد نحو العينة ولا يقفز إليها فوراً — موجة سلسة', () {
      final w = SpeakingWave();
      for (var i = 0; i < 8; i++) {
        w.add(0.02);
      }
      final before = w.level;
      w.add(1.0);
      expect(w.level, greaterThan(before));
      expect(w.level, lessThan(1.0)); // لم يقفز إلى القمة مباشرة
    });

    test('المستوى لا يتجاوز النطاق 0..1 مهما كانت العينات', () {
      final w = SpeakingWave();
      for (var i = 0; i < 20; i++) {
        w.add(1.0);
      }
      expect(w.level, lessThanOrEqualTo(1.0));
    });
  });

  group('دفاعية العينات', () {
    test('null و NaN والقيم خارج النطاق تُتجاهل بلا استثناء وبلا أثر', () {
      final w = SpeakingWave();
      w.add(null);
      w.add(double.nan);
      w.add(-0.5);
      w.add(2.0);
      expect(w.speaking, isFalse);
      expect(w.level, 0);
    });
  });

  group('أعمدة الموجة للعرض', () {
    test('المستوى صفر: أعمدة منخفضة كلها بالحد الأدنى', () {
      final bars = waveBars(0);
      expect(bars.length, 4);
      for (final b in bars) {
        expect(b, lessThanOrEqualTo(0.2));
      }
    });

    test('المستوى الأقصى: أعمدة واضحة لا تتجاوز 1', () {
      final bars = waveBars(1);
      for (final b in bars) {
        expect(b, greaterThan(0.3));
        expect(b, lessThanOrEqualTo(1.0));
      }
    });

    test('مستويات متتالية تعطي بارتفاعات متفاوتة — شكل موجة لا خط مسطح', () {
      final low = waveBars(0.1);
      final high = waveBars(0.9);
      expect(high.reduce((a, b) => a + b), greaterThan(low.reduce((a, b) => a + b)));
    });
  });

  group('تحليل المستوى الصوتي من إحصاءات الاتصال', () {
    test('audioLevel المباشر يُقرأ كما هو', () {
      expect(audioLevelFromStats({'audioLevel': 0.65}), closeTo(0.65, 0.0001));
    });

    test('البديل من المواصفة: totalAudioEnergy / totalSamplesDuration', () {
      expect(
        audioLevelFromStats({'totalAudioEnergy': 0.3, 'totalSamplesDuration': 1.5}),
        closeTo(0.2, 0.0001),
      );
    });

    test('المدة صفر أو غائبة → null لا قسمة على صفر', () {
      expect(
        audioLevelFromStats({'totalAudioEnergy': 0.3, 'totalSamplesDuration': 0}),
        isNull,
      );
      expect(audioLevelFromStats({'totalAudioEnergy': 0.3}), isNull);
    });

    test('أي غرابة → null: نص وقيم خارج النطاق وخريطة فارغة', () {
      expect(audioLevelFromStats({'audioLevel': 'x'}), isNull);
      expect(audioLevelFromStats({'audioLevel': 1.7}), isNull);
      expect(audioLevelFromStats({'audioLevel': -0.2}), isNull);
      expect(audioLevelFromStats(<dynamic, dynamic>{}), isNull);
    });
  });
}
