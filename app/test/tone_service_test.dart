import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/tone_service.dart';

void main() {
  group('نغمات وصل شات', () {
    test('النغمة الافتراضية كلاسيكية وكل نغمة لها اسم', () {
      expect(ToneService.defaultTone, 'wasl_classic');
      expect(ToneService.tones.length, greaterThanOrEqualTo(7));
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
    test('كل نغمة جاهزة لها ملف صوت، وكل قطعة استوديو لها ملف', () {
      for (final t in ToneService.builtIn.where((t) => t.id != 'system')) {
        expect(File('android/app/src/main/res/raw/${t.id}.ogg').existsSync(), true,
            reason: t.id);
      }
      for (final p in [...ToneService.studioVoices, ...ToneService.studioMelodies]) {
        expect(File(p.asset).existsSync(), true, reason: p.id);
      }
      final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
      for (final t in ToneService.builtIn.where((t) => t.id != 'system')) {
        expect(keep.contains('@raw/${t.id}'), true, reason: t.id);
      }
    });
  });
}
