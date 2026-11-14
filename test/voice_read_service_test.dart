import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/voice_read_service.dart';

void main() {
  group('بناء نص القراءة', () {
    test('المحادثة الفردية: بلا تسمية مرسل', () {
      final text = VoiceReadService.buildSpokenText(
        [('صديق', 'السلام عليكم'), ('أنا', 'وعليكم السلام')],
        isGroup: false,
      );
      expect(text.contains('صديق:'), isFalse);
      expect(text.contains('السلام عليكم'), isTrue);
      expect(text.contains('وعليكم السلام'), isTrue);
    });

    test('المجموعة: تسمية المرسل قبل كل رسالة', () {
      final text = VoiceReadService.buildSpokenText(
        [('سارة', 'جاهزون للملخص؟'), ('أنا', 'نعم')],
        isGroup: true,
      );
      expect(text.contains('سارة: جاهزون للملخص؟'), isTrue);
      expect(text.contains('أنا: نعم'), isTrue);
    });

    test('حد 10 رسائل حصراً', () {
      final lines = [for (var i = 0; i < 20; i++) ('م', 'رسالة رقم $i')];
      final text = VoiceReadService.buildSpokenText(lines, isGroup: false);
      // الأولى والأخيرة من الحد العشري فقط
      expect(text.contains('رسالة رقم 0'), isTrue);
      expect(text.contains('رسالة رقم 9'), isTrue);
      expect(text.contains('رسالة رقم 10'), isFalse);
    });

    test('الروابط تُنطق «رابط» ولا عناوينها', () {
      final text = VoiceReadService.buildSpokenText(
        [('م', 'شوف https://example.com/very/long/path?q=1 وانظر')],
        isGroup: false,
      );
      expect(text.contains('example.com'), isFalse);
      expect(text.contains('رابط'), isTrue);
    });

    test('علامات الترميز تُسطّح ولا تُنطق', () {
      final text = VoiceReadService.buildSpokenText(
        [('م', '*مهم جداً* #عاجل _ملاحظة_')],
        isGroup: false,
      );
      expect(text.contains('*'), isFalse);
      expect(text.contains('#'), isFalse);
      expect(text.contains('_'), isFalse);
      expect(text.contains('مهم جداً'), isTrue);
    });

    test('ميتا الملفات (JSON) لا تُنطق إطلاقاً', () {
      final text = VoiceReadService.buildSpokenText(
        [('م', '{"name":"file.pdf","size":123}'), ('م', 'نص عادي')],
        isGroup: false,
      );
      expect(text.contains('file.pdf'), isFalse);
      expect(text.contains('نص عادي'), isTrue);
    });

    test('الرسالة الطويلة تُقص عند 300 حرف', () {
      final long = 'ا' * 500;
      final text = VoiceReadService.buildSpokenText([('م', long)], isGroup: false);
      expect(text.length, lessThan(310));
      expect(text.endsWith('…'), isTrue);
    });

    test('الإيموجي الزخرفية تُحذف من النطق', () {
      final text = VoiceReadService.buildSpokenText(
        [('م', '🎉 مرحبا 🎈 بالعالم 🚀')],
        isGroup: false,
      );
      expect(text.contains('🎉'), isFalse);
      expect(text.contains('مرحبا'), isTrue);
    });
  });
}
