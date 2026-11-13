// اختبارات خدمة «إرسال ملاحظات» (ترحيل 029 — 0.19.0) — نقية بلا شبكة.
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/feedback_service.dart';

void main() {
  group('فئات الملاحظة مطابقة لقيد الخادم في ترحيل 029', () {
    test('أربع فئات بمعرفات مطابقة لقيد category حرفياً', () {
      expect(FeedbackService.categories.length, 4);
      expect(
        FeedbackService.categories.map((c) => c.$1).toSet(),
        {'bug', 'idea', 'privacy', 'other'},
      );
    });

    test('تسمية عربية لكل فئة، والمعرف الغريب يعود «أخرى» (المحلل الدفاعي)', () {
      expect(FeedbackService.categoryLabel('bug'), 'خلل أو خطأ');
      expect(FeedbackService.categoryLabel('idea'), 'فكرة أو تحسين');
      expect(FeedbackService.categoryLabel('privacy'), 'ملاحظة خصوصية');
      expect(FeedbackService.categoryLabel('other'), 'أخرى');
      expect(FeedbackService.categoryLabel('unknown_x'), 'أخرى');
      expect(FeedbackService.categoryLabel(''), 'أخرى');
    });

    test('الأيقونات والألوان معرفة لكل الفئات (لا null ولا أيقونة غريبة)', () {
      for (final c in FeedbackService.categories) {
        expect(c.$3.codePoint, greaterThan(0));
        expect(c.$4.toARGB32(), isNonZero);
      }
    });
  });

  group('تنظيف النص قبل الإرسال', () {
    test('إزالة محارف التحكم غير المرئية دون لمس الكلام', () {
      final s = FeedbackService.sanitize('مرحبا\u0000 بك\u007F في\u0007 وصل');
      expect(s, contains('مرحبا'));
      expect(s, contains('وصل'));
      expect(s.contains('\u0000'), isFalse);
      expect(s.contains('\u007F'), isFalse);
    });

    test('تقليص المسافات الطويلة والأسطر الفارغة المتتالية', () {
      expect(FeedbackService.sanitize('سطر  \u00A0 واحد'),
          'سطر واحد');
      expect(FeedbackService.sanitize('أ\n\n\n\nب'), 'أ\n\nب');
    });

    test('قص النص الطويل إلى حد الخادم 1500 حرفاً بالضبط بعد القص', () {
      final long = 'ن' * 1700;
      final s = FeedbackService.sanitize(long);
      expect(s.length, 1500);
    });

    test('إزالة الفراغات الطرفية', () {
      expect(FeedbackService.sanitize('  ملاحظة سليمة  '), 'ملاحظة سليمة');
    });
  });

  group('التحقق المحلي قبل أي طلب شبكي', () {
    test('أقصر من 5 أحرف مرفوضة برسالة عربية تحدد الحد', () {
      expect(FeedbackService.validationError('أب ج'),
          'اكتب ملاحظة من 5 أحرف على الأقل');
    });

    test('نص فراغات فقط يرفض بعد التنظيف (لا يمر للخادم)', () {
      expect(FeedbackService.validationError('     \n\t  '), isNotNull);
    });

    test('خمسة أحرف بالضبط مقبولة', () {
      expect(FeedbackService.validationError('مشكلة'), isNull);
    });

    test('الحد الأعلى 1500 مقبول (لا رسالة خطأ)', () {
      expect(FeedbackService.validationError('ك' * 1500), isNull);
    });

    test('حدود الخدمة مطابقة لحدود الخادم في ترحيل 029', () {
      expect(FeedbackService.minLen, 5);
      expect(FeedbackService.maxLen, 1500);
      expect(FeedbackService.limitPerHour, 5);
    });
  });

  group('تفسير أخطاء الخادم بالعربية', () {
    test('حد الإغراق من مُحفّز ترحيل 029 يفسَّر برسالة صادقة', () {
      final hint = FeedbackService.sendErrorHint(
          Exception('FEEDBACK_RATE_LIMITED'));
      expect(hint, isNotNull);
      expect(hint, contains('ملاحظات كثيرة'));
    });

    test('خطأ قيد طول الجدول يفسَّر برسالة الحدود', () {
      expect(
          FeedbackService.sendErrorHint(
              Exception('new row violates row-level security policy "app_feedback_body_check"')),
          isNotNull);
      expect(
          FeedbackService.sendErrorHint(
              Exception('feedback body check failed')),
          isNotNull);
    });

    test('الأخطاء الغريبة لا تُفسَّر ولا تُخفى (null والواجهة تعرض الرسالة العامة)', () {
      expect(FeedbackService.sendErrorHint(Exception('network unreachable')), isNull);
      expect(FeedbackService.sendErrorHint(Exception('JWT expired')), isNull);
    });
  });
}
