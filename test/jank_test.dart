import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/jank_service.dart';

/// اختبارات نقية لقياس السقوط الإطاري (المرحلة 13 أ — 1.1.0) — بلا رسم
/// ولا Binding: المخزن النقي حصراً. العقد: نافذة متدحرجة بسقف 600،
/// عتبة التعثر 32 مللي ثانية معلنة، إحصاء صادق بلا عينات مخترعة،
/// وتدوير كامل ينجو من التخزين.
void main() {
  group('الإدخال والتصنيف', () {
    test('عتبة التعثر 32ms معلنة ومثبتة: 32 ليس متعثراً و33 كذلك هو', () {
      final s = JankStore()..addFrame(32)..addFrame(33);
      expect(s.isJanky(32), isFalse);
      expect(s.isJanky(33), isTrue);
      expect(s.jankyCount, 1);
    });

    test('الإحصاءات الأربع صادقة: متوسط وذروة وأسوأ ونسبة', () {
      final s = JankStore()..addFrame(10)..addFrame(20)..addFrame(40)..addFrame(40);
      expect(s.avgMs(), 27); // (10+20+40+40)~/4
      expect(s.worstMs(), 40);
      expect(s.jankyCount, 2);
      expect(s.jankRatioPercent(), 50);
    });

    test('الفراغ صادق: صفر بلا ادعاء بلا عينات', () {
      final s = JankStore();
      expect(s.avgMs(), 0);
      expect(s.worstMs(), 0);
      expect(s.percentile(0.95), 0);
      expect(s.jankRatioPercent(), 0);
    });

    test('العينات الغريبة تُسقط: السالبة بلا اختراع والعالية بمسقف 10 ثوانٍ', () {
      final s = JankStore()..addFrame(-5)..addFrame(999999)..addFrame(15);
      expect(s.frames.length, 2);
      expect(s.worstMs(), 10000); // مُسقف لا مؤثر
      expect(s.frames.contains(15), isTrue);
    });
  });

  group('النافذة المتدحرجة والترتيب', () {
    test('السقف 600 إطار: الأحدث يبقى والأقدم يُخلى بالترتيب', () {
      final s = JankStore();
      for (var i = 0; i < 610; i++) {
        s.addFrame(i);
      }
      expect(s.frames.length, 600);
      expect(s.frames.first, 609); // الأحدث أولاً
      expect(s.frames.last, 10); // أقدم عشرين بقيت
      expect(s.frames.contains(9), isFalse);
    });

    test('المئين حتمي بأقرب ترتيب صاعد', () {
      final s = JankStore()..addFrame(100)..addFrame(20)..addFrame(60);
      expect(s.percentile(0.95), 100);
      expect(s.percentile(0.0), 20);
    });
  });

  group('التخزين والتدوير', () {
    test('encode → decode ينجو بالنافذة نفسها', () {
      final s = JankStore()..addFrame(8)..addFrame(50)..addFrame(16);
      final back = JankStore.decode(s.encode());
      expect(back.frames, s.frames);
      expect(back.jankyCount, 1);
    });

    test('نص فارغ أو مشوه يعيد مخزناً فارغاً بلا استثناء', () {
      expect(JankStore.decode(null).frames, isEmpty);
      expect(JankStore.decode('').frames, isEmpty);
      expect(JankStore.decode('a,b,c').frames, isEmpty);
      expect(JankStore.decode('12,بيانات,40').frames.length, 2);
    });

    test('reset يفرّغ كل شيء', () {
      final s = JankStore()..addFrame(40)..addFrame(10);
      s.reset();
      expect(s.frames, isEmpty);
      expect(s.jankyCount, 0);
    });
  });
}
