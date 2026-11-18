import 'package:test/test.dart';
import 'package:wasl_voice_waves/speaking_detector.dart';
import 'package:wasl_voice_waves/stats_levels.dart';

void main() {
  final t0 = DateTime(2026, 11, 18, 10, 0, 0);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('استخلاص مستوى الصوت', () {
    test('المعياري audioLevel من الوارد يفوز', () {
      final lv = extractAudioLevel([
        ('media-source', {'audioLevel': 0.9}),
        ('inbound-rtp', {'audioLevel': 0.1}),
      ]);
      expect(lv, closeTo(0.1, 0.0001));
    });

    test('مقياس الإرث 0..32767 يوحَّد', () {
      final lv = extractAudioLevel([
        ('ssrc', {'audioInputLevel': 16384}),
      ]);
      expect(lv, closeTo(0.5, 0.001));
    });

    test('totalAudioEnergy يقارب المتوسط', () {
      final lv = extractAudioLevel([
        ('inbound-rtp', {'totalAudioEnergy': 0.4, 'totalSamplesDuration': 2.0}),
      ]);
      expect(lv, closeTo(0.2, 0.0001));
    });

    test('بلا مستوى → null صادق بلا ادعاء', () {
      expect(extractAudioLevel([
        ('inbound-rtp', {'kind': 'audio'}),
      ]), isNull);
      expect(extractAudioLevel(const []), isNull);
    });

    test('التشبع يقف عند 1 والقيم غير المنطقية تُسقط', () {
      expect(extractAudioLevel([
        ('ssrc', {'audioInputLevel': 90000}),
      ]), 1);
      expect(extractAudioLevel([
        ('media-source', {'audioLevel': -2}),
      ]), isNull);
    });
  });

  group('كاشف يتحدث بهسترة', () {
    test('الصمت لا يبدأ وفوق العتبة يبدأ فوراً', () {
      final d = SpeakingDetector();
      expect(d.update(0.001, at(0)), isFalse);
      expect(d.update(0.06, at(100)), isTrue);
    });

    test('الحد الأدنى للكلام يمنع الرمش', () {
      final d = SpeakingDetector();
      d.update(0.06, at(0));
      expect(d.update(0.001, at(200)), isTrue);
      expect(d.update(0.001, at(1000)), isTrue);
    });

    test('التوقف يتطلب صمتاً متواصلاً', () {
      final d = SpeakingDetector(minSpeech: Duration.zero);
      d.update(0.06, at(0));
      d.update(0.001, at(10));
      expect(d.update(0.001, at(200)), isTrue);
      expect(d.update(0.001, at(470)), isFalse);
    });

    test('الهسترة بين العتبتين تبقي الحالة', () {
      final d = SpeakingDetector(minSpeech: Duration.zero);
      d.update(0.06, at(0));
      d.update(0.030, at(10));
      expect(d.update(0.030, at(1000)), isTrue);
    });

    test('التصفير يعيد الصمت', () {
      final d = SpeakingDetector();
      d.update(0.08, at(0));
      d.reset();
      expect(d.speaking, isFalse);
    });

    test('عتبة البدء أعلى من التوقف — تأكيد محمي', () {
      expect(
        () => SpeakingDetector(startLevel: 0.01, stopLevel: 0.05),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
