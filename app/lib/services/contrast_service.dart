/// تباين الألوان (المرحلة 13 ب — 1.2.0): حساب WCAG 2.x نقي — نسبة التباين
/// بين لونين وقرار عتبة AA (4.5:1 للنص العادي، 3.0:1 للنص الكبير والمكوّنات
/// والرسوم الدلالية) — والتدقيق الدائم في `contrast_audit_test` يفحص الوضعين
/// الفاتح والداكن مع كل بناء فلا لون ينزلق تحت العتبة صامتاً.
import 'package:material_ui/material_ui.dart';

class ContrastService {
  ContrastService._();

  /// عتبة النص العادي AA (وAAA يكون 7.0)
  static const aaNormal = 4.5;

  /// عتبة النص الكبير (≥18pt أو ≥14pt عريض) والمكوّنات والرسوم
  static const aaLarge = 3.0;

  /// عتبة AAA للنص العادي
  static const aaaNormal = 7.0;

  /// السطوع النسبي WCAG — عبر computeLuminance المدمج (نفس الصيغة المعيارية
  /// 0.2126R + 0.7152G + 0.0722B مع إخطار أُسّي sRGB)
  static double luminance(Color c) => c.computeLuminance();

  /// نسبة التباين WCAG بين لونين — من 1.0 إلى 21.0، متناظرة
  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// هل يجتاز [fg] على [bg] عتبة AA؟ [large] للنص الكبير والمكوّنات
  static bool passesAA(Color fg, Color bg, {bool large = false}) =>
      ratio(fg, bg) >= (large ? aaLarge : aaNormal);

  /// هل يجتاز AAA للنص العادي؟
  static bool passesAAA(Color fg, Color bg) => ratio(fg, bg) >= aaaNormal;

  /// أفضل لون نص من المرشحين على الخلفية (الأعلى تبايناً) — null إن قائمة فارغة
  static Color? bestOn(Color bg, List<Color> candidates) {
    Color? best;
    var bestRatio = -1.0;
    for (final c in candidates) {
      final r = ratio(c, bg);
      if (r > bestRatio) {
        bestRatio = r;
        best = c;
      }
    }
    return best;
  }

  /// دمج لون شفاف فوق خلفية فعلية (white70 فوق سطح داكن مثلاً) — يلزمه
  /// التدقيق لأن ألفا تُحسب قبل السطوع
  static Color blend(Color fg, Color bg) => Color.alphaBlend(fg, bg);
}
