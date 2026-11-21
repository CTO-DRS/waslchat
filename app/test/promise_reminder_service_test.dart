// اختبارات التذكيرات الذكية من الرسائل (المرحلة 9 ب — 0.23.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/promise_reminder_service.dart';

// 2026-11-14 سبت
final _now = DateTime(2026, 11, 14, 12, 30);

void main() {
  group('كشف الموعد', () {
    test('«اتفقنا الخميس 8» — يوم أسبوع وساعة مساءً بثقة عالية', () {
      final p = PromiseReminderService.detect('m1', 'اتفقنا الخميس 8 مساءً', _now)!;
      expect(p.dayWord, 'الخميس');
      // من السبت للخميس: 5 أيام
      expect(p.dayOffset, 5);
      expect(p.hour, 20);
      expect(p.isEvening, true);
      expect(p.confidence, 0.9);
      expect(p.describe(), contains('الخميس'));
      expect(p.describe(), contains('مساءً'));
    });

    test('«بكرة الساعة 10:30» — إزاحة غد والساعة مع الدقيقة', () {
      final p = PromiseReminderService.detect('m2', 'بكرة الساعة 10:30 إن شاء الله', _now)!;
      expect(p.dayOffset, 1);
      expect(p.hour, 10);
      expect(p.minute, 30);
      expect(p.confidence, 0.9);
    });

    test('«نلتقي بعد غدا المغرب» — إزاحة يومين وفترة المغرب 18', () {
      final p = PromiseReminderService.detect('m3', 'نلتقي بعد غدا المغرب', _now)!;
      expect(p.dayOffset, 2);
      expect(p.hour, 18); // «المغرب» وحدها تعطي الساعة الافتراضية
      expect(p.isEvening, true);
      expect(p.confidence, 0.9);
    });

    test('«سأرسل لك الملف الساعة 4 عصرا» — فعل وساعة وفترة نهارية', () {
      final p = PromiseReminderService.detect('m4', 'سأرسل لك الملف الساعة 4 عصرا', _now)!;
      expect(p.hour, 16);
      expect(p.isEvening, false);
      expect(p.confidence, 0.6);
    });

    test('الرسالة بلا فعل وعد لا تقترح شيئاً ولو بها وقت', () {
      expect(PromiseReminderService.detect('m5', 'الاجتماع يوم الخميس جميل', _now), isNull);
    });

    test('فعل بلا وقت ولا يوم يعيد null (لا اقتراح ضبابي)', () {
      expect(PromiseReminderService.detect('m6', 'اتفقنا على هذا', _now), isNull);
    });

    test('ساعة مستحيلة (25) تُسقط ولا تُخترع', () {
      final p = PromiseReminderService.detect('m7', 'اتفقنا الخميس الساعة 25', _now)!;
      expect(p.hour, isNull);
      expect(p.confidence, 0.7); // اليوم فقط
    });

    test('التطبيع يعمل: همزات وتشكيل لا تكسر الكشف — والوقت الغامض لا يُخترع', () {
      final p = PromiseReminderService.detect('m8', 'اتَّفقنا الأَحد 9 م', _now)!;
      expect(p.dayWord, 'الاحد');
      expect(p.dayOffset, 1);
      expect(p.hour, isNull); // «9 م» بلا فترة مفهومة — لا ساعة مُختلقة
      expect(p.confidence, 0.7);
    });
  });

  group('المسح والاستبعاد', () {
    test('المرتفع ثقة أولاً والحد 3', () {
      final hits = PromiseReminderService.scan([
        ('a', 'اتفقنا الخميس 8 مساءً'),
        ('b', 'بكرة الساعة 10:30 ان شاء الله'),
        ('c', 'نلتقي بعد غدا المغرب'),
        ('d', 'سأرسل الملف الساعة 4 عصرا'),
        ('e', 'موعدنا الجمعة 9 الليل'),
      ], _now);
      expect(hits.length, 3);
      expect(hits.first.messageId, 'a');
    });

    test('المستبعدَين سلفاً لا يعودان', () {
      final hits = PromiseReminderService.scan([
        ('a', 'اتفقنا الخميس 8 مساءً'),
        ('b', 'بكرة الساعة 10:30 ان شاء الله'),
      ], _now,
          dismissed: {'a'});
      expect(hits.map((h) => h.messageId), ['b']);
    });
  });

  group('تحويل التاريخ', () {
    test('resolveDate يحسب التاريخ القادم من الإزاحة والساعة', () {
      final p = PromiseReminderService.detect('x', 'اتفقنا الخميس 8 مساءً', _now)!;
      final d = PromiseReminderService.resolveDate(p, _now)!;
      // السبت 14 + 5 = الخميس 19 نوفمبر 2026 الساعة 20:00
      expect(d, DateTime(2026, 11, 19, 20, 0));
    });

    test('بلا يوم ولا ساعة لا يُؤرَّخ (null بصدق)', () {
      final p = DetectedPromise(messageId: 'y', text: '', confidence: 0.5);
      expect(PromiseReminderService.resolveDate(p, _now), isNull);
    });

    test('الإزاحة صفر = اليوم نفسه', () {
      final p = PromiseReminderService.detect('z', 'اتفقنا اليوم الساعة 9 مساءً', _now)!;
      final d = PromiseReminderService.resolveDate(p, _now)!;
      expect(d, DateTime(2026, 11, 14, 21, 0));
    });
  });

  group('الإفصاح', () {
    test('نص الإفصاح يذكر الجهاز والإشعار المحلي', () {
      expect(PromiseReminderService.disclosure, contains('جهازك'));
      expect(PromiseReminderService.disclosure, contains('محلي'));
    });
  });
}
