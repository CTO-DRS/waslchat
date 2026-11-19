import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/tone_service.dart';

void main() {
  group('نغمات وصل شات', () {
    test('النغمة الافتراضية كلاسيكية وكل نغمة لها اسم', () {
      expect(ToneService.defaultTone, 'wasl_classic');
      expect(ToneService.tones.length, 7);
      for (final t in ToneService.tones) {
        expect(t.label.isNotEmpty, true);
      }
    });
    test('قيمة غير معروفة تعود للافتراضية', () {
      expect(ToneService.normalize(null), 'wasl_classic');
      expect(ToneService.normalize('xyz'), 'wasl_classic');
      expect(ToneService.normalize('wasl_pulse'), 'wasl_pulse');
    });
    test('قناة لكل نغمة، ونغمة الجوال على قناة الرسائل الأصلية', () {
      expect(ToneService.channelId('system'), 'messages');
      expect(ToneService.channelId('wasl_calm'), 'msg_wasl_calm_v1');
      final ids = ToneService.tones.map((t) => ToneService.channelId(t.id)).toSet();
      expect(ids.length, ToneService.tones.length);
    });
  });
}
