/// اختبارات فهم الأوامر الصوتية النقية (المرحلة 13 ب — 1.2.0 — تغطية يتيمة).
///
/// كل الاختبارات على `VoiceCommandsService.parse` حصراً: التطبيع العربي
/// المتسامح فوق محرك LocalAiService، والأوامر السبعة بأولويتها، والرفض
/// الصادق لكلام لا يُفهم — بلا مايك ولا خدمة تعرف.
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/voice_commands_service.dart';

void main() {
  group('parse — الأوامر السبعة بأشكالها', () {
    test('افتح المحادثات بأشكالها المنطوقة', () {
      for (final s in ['افتح المحادثات', 'المحادثات', 'افتح الشات']) {
        final c = VoiceCommandsService.parse(s);
        expect(c?.action, 'tab:0', reason: '«$s» يجب أن يفتح المحادثات');
      }
    });

    test('المجتمعات بأشكالها', () {
      for (final s in ['افتح المجتمعات', 'المجتمعات', 'المجتمع']) {
        expect(VoiceCommandsService.parse(s)?.action, 'tab:1');
      }
    });

    test('القنوات بأشكالها — القناه بلا همزة تفهم', () {
      expect(VoiceCommandsService.parse('افتح القنوات')?.action, 'tab:2');
      expect(VoiceCommandsService.parse('القناه')?.action, 'tab:2');
    });

    test('المكالمات وأشكال الاتصالات', () {
      expect(VoiceCommandsService.parse('افتح المكالمات')?.action, 'tab:3');
      expect(VoiceCommandsService.parse('الاتصالات')?.action, 'tab:3');
    });

    test('الإعدادات بأشكالها المنطوقة', () {
      expect(VoiceCommandsService.parse('افتح الاعدادات')?.action, 'tab:4');
      expect(VoiceCommandsService.parse('الضبط')?.action, 'tab:4');
    });

    test('وصل الذكاء بأسمائه الثلاثة', () {
      for (final s in ['وصل اي', 'الذكاء', 'المساعد']) {
        expect(VoiceCommandsService.parse(s)?.action, 'ai', reason: '«$s»');
      }
    });

    test('محادثة جديدة أو رسالة جديدة', () {
      expect(VoiceCommandsService.parse('محادثه جديده')?.action, 'newchat');
      expect(VoiceCommandsService.parse('رساله جديده')?.action, 'newchat');
    });

    test('الأوامر تعيد تسمياتها العربية للعرض', () {
      expect(VoiceCommandsService.parse('المحادثات')?.label, 'المحادثات');
      expect(VoiceCommandsService.parse('الذكاء')?.label, 'وصل AI');
    });
  });

  group('parse — التسامح والرفض الصادق', () {
    test('التشكيل والهمزات لا تكسر الفهم (تطبيع المحرك)', () {
      expect(VoiceCommandsService.parse('افْتَحِ المُحَادَثَات')?.action, 'tab:0');
      expect(VoiceCommandsService.parse('الإعدادات')?.action, 'tab:4');
    });

    test('عبارات مطولة تحوي الأمر داخلها تفهم', () {
      expect(
          VoiceCommandsService.parse('ممكن تفتح لي المحادثات لو سمحت')?.action,
          'tab:0');
    });

    test('الأولوية ترتب: النص المتضمن أكثر من مفتاح يقرر الترتيب الموثق', () {
      // «المحادثات» تفحص أولاً حتى لو ذكر النص «القنوات» بعدها
      final c = VoiceCommandsService.parse('المحادثات والقنوات');
      expect(c?.action, 'tab:0');
    });

    test('كلام عشوائي لا أمر فيه يعيد null بلا اختراع', () {
      expect(VoiceCommandsService.parse('الجو حلو اليوم'), isNull);
      expect(VoiceCommandsService.parse('كذا كذا'), isNull);
    });

    test('الفارغ وبعد التطبيع الفارغ يعيدان null', () {
      expect(VoiceCommandsService.parse(''), isNull);
      expect(VoiceCommandsService.parse('   '), isNull);
      expect(VoiceCommandsService.parse('؟؟؟'), isNull);
    });
  });
}
