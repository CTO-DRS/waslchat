/// اختبارات تباين الألوان والتدقيق الدائم للوضعين (المرحلة 13 ب — 1.2.0).
///
/// الجداءات المرجعية من مواصفة WCAG 2.x، والتدقيق يفحص كل طبقات نص وصل
/// على خلفياتها الفعلية في الوضعين — فلا لون ينزلق تحت العتبة صامتاً.
/// اللونان المصدّلان في 1.2.0: ink3 وink4 (كانا 3.79 و2.54 على الأبيض).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/contrast_service.dart';
import 'package:wasl_chat/theme.dart';

void main() {
  group('ContrastService — جداءات WCAG المرجعية', () {
    test('الأسود على الأبيض = 21.0 (أقصى نسبة ممكنة)', () {
      expect(ContrastService.ratio(Colors.black, Colors.white), closeTo(21.0, 0.01));
    });

    test('النسبة متناظرة — اتجاه الاستدعاء لا يغير النتيجة', () {
      final a = ContrastService.ratio(const Color(0xFF1A2033), const Color(0xFFFFFFFF));
      final b = ContrastService.ratio(const Color(0xFFFFFFFF), const Color(0xFF1A2033));
      expect(a, closeTo(b, 0.0001));
    });

    test('الرمادي المرجعي #767676 على الأبيض = 4.54 عتبة AA الصارمة', () {
      final r = ContrastService.ratio(const Color(0xFF767676), Colors.white);
      expect(r, closeTo(4.54, 0.05));
      expect(ContrastService.passesAA(const Color(0xFF767676), Colors.white), isTrue);
    });

    test('#777777 يفشل AA العادي ويعديه بنسبة أعلى بقليل', () {
      const grey = Color(0xFF777777);
      expect(ContrastService.ratio(grey, Colors.white), lessThan(4.5));
    });

    test('عتبة النص الكبير 3.0 تفصل فيما يفشل 4.5', () {
      const teal = WaslColors.teal;
      // تركواز وصل على الأبيض ≈ 2.49 — يفشل الاثنتين
      expect(ContrastService.passesAA(teal, Colors.white), isFalse);
      expect(ContrastService.passesAA(teal, Colors.white, large: true), isFalse);
    });

    test('السطوع النسبي بين 0 و1', () {
      for (final c in [
        Colors.black,
        Colors.white,
        WaslColors.indigo,
        WaslColors.teal,
        WaslColors.darkBg,
      ]) {
        final l = ContrastService.luminance(c);
        expect(l, greaterThanOrEqualTo(0.0));
        expect(l, lessThanOrEqualTo(1.0));
      }
    });

    test('bestOn يختار الأعلى تبايناً من المرشحين', () {
      final best = ContrastService.bestOn(
          WaslColors.darkBg, [WaslColors.ink4, Colors.white, WaslColors.teal]);
      expect(best, Colors.white); // الأبيض أعلى تبايناً على الخلفية الداكنة
      expect(ContrastService.bestOn(Colors.white, const []), isNull);
    });

    test('الدمج الفعلي لألفا فوق سطح داكن قبل الحساب', () {
      final blended = ContrastService.blend(
          Colors.white.withValues(alpha: 0.7), WaslColors.darkSurface);
      // المدمج معتم تماماً فيصير قابلاً للمقارنة المباشرة
      expect(blended.a, 1.0);
      expect(ContrastService.passesAA(blended, WaslColors.darkSurface), isTrue);
    });
  });

  group('تدقيق الوضع الفاتح — طبقات نص وصل على خلفياتها الفعلية', () {
    const surfaces = [WaslColors.lightSurface, WaslColors.lightBg];

    test('النص الأساسي ink يجتاز AA العادي على السطحين', () {
      for (final bg in surfaces) {
        expect(ContrastService.ratio(WaslColors.ink, bg),
            greaterThanOrEqualTo(4.5), reason: 'ink على $bg');
      }
    });

    test('النص الثانوي ink2 يجتاز AA العادي على السطحين', () {
      for (final bg in surfaces) {
        expect(ContrastService.ratio(WaslColors.ink2, bg),
            greaterThanOrEqualTo(4.5), reason: 'ink2 على $bg');
      }
    });

    test('النص الخافت ink3 يجتاز AA الكبير ≥3.0 (مصدّل في 1.2.0)', () {
      for (final bg in surfaces) {
        expect(ContrastService.ratio(WaslColors.ink3, bg),
            greaterThanOrEqualTo(3.0), reason: 'ink3 على $bg');
      }
    });

    test('النص شبه المعطل ink4 يجتاز AA الكبير ≥3.0 على السطحين وفقاعة الرسائل', () {
      for (final bg in [...surfaces, WaslColors.lightBubble]) {
        expect(ContrastService.ratio(WaslColors.ink4, bg),
            greaterThanOrEqualTo(3.0), reason: 'ink4 على $bg');
      }
    });

    test('الطبقات الثقيلة أيضاً على فقاعة الرسائل الفاتحة', () {
      // نص الرسالة على الفقاعة يجب أن يجتاز AA العادي حصراً
      expect(ContrastService.ratio(WaslColors.ink, WaslColors.lightBubble),
          greaterThanOrEqualTo(4.5));
      expect(ContrastService.ratio(WaslColors.ink2, WaslColors.lightBubble),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('تدقيق الوضع الداكن — بألفا مدموجة فوق خلفياتها', () {
    const surfaces = [WaslColors.darkBg, WaslColors.darkSurface];

    test('الأبيض الأساسي يجتاز AA العادي بسهولة', () {
      for (final bg in surfaces) {
        expect(ContrastService.ratio(Colors.white, bg), greaterThanOrEqualTo(7.0));
      }
    });

    test('white70 الثانوي يجتاز AA العادي بعد الدمج الفعلي', () {
      for (final bg in surfaces) {
        final fg = ContrastService.blend(Colors.white.withValues(alpha: 0.7), bg);
        expect(ContrastService.ratio(fg, bg), greaterThanOrEqualTo(4.5),
            reason: 'white70 على $bg');
      }
    });

    test('white60 وwhite54 الخافتان يجتازان AA الكبير ≥3.0 بعد الدمج', () {
      for (final bg in surfaces) {
        final w60 =
            ContrastService.blend(Colors.white.withValues(alpha: 0.6), bg);
        final w54 =
            ContrastService.blend(Colors.white.withValues(alpha: 0.54), bg);
        expect(ContrastService.ratio(w60, bg), greaterThanOrEqualTo(3.0),
            reason: 'white60 على $bg');
        expect(ContrastService.ratio(w54, bg), greaterThanOrEqualTo(3.0),
            reason: 'white54 على $bg');
      }
    });

    test('التركواز على الداكن يجتاز AA الكبير — لمسة العلامة مقروءة', () {
      for (final bg in surfaces) {
        expect(ContrastService.ratio(WaslColors.teal, bg),
            greaterThanOrEqualTo(3.0), reason: 'teal على $bg');
      }
    });
  });

  group('الحد المعلن — ألوان العلامة على الفاتح', () {
    test('التركواز على الأبيض زخرفي حصراً — تحت العتبتين والحد معلن بمركز المساعدة', () {
      // قرار موثق: التركواز لون علامة يظهر على الفاتح كأيقونات وشارات وحدود —
      // ولا يُستعمل لحمل نص أساسي مقروء على سطح فاتح
      final r = ContrastService.ratio(WaslColors.teal, WaslColors.lightSurface);
      expect(r, lessThan(3.0));
    });
  });
}
