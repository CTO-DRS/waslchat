// اختبارات المحرك الهجري — حالات مأخوذة حرفياً من اختبارات التطبيق (phase5_test)
// فتوقعاتها مثبتة بمراجعة يدوية وتقويم محقق.
import 'package:test/test.dart';
import 'package:wasl_hijri/hijri_service.dart';

void main() {
  group('تحويل ميلادي إلى هجري', () {
    test('حالات مرجعية مثبتة عبر قرون', () {
      expect(HijriService.toHijri(DateTime(2008, 1, 10)), (1429, 1, 1));
      expect(HijriService.toHijri(DateTime(2026, 11, 13)), (1448, 6, 2));
      expect(HijriService.toHijri(DateTime(2026, 1, 1)), (1447, 7, 12));
      expect(HijriService.toHijri(DateTime(2024, 1, 1)), (1445, 6, 19));
      expect(HijriService.toHijri(DateTime(2025, 6, 26)), (1446, 12, 29));
      expect(HijriService.toHijri(DateTime(2030, 3, 10)), (1451, 11, 5));
      expect(HijriService.toHijri(DateTime(1999, 12, 31)), (1420, 9, 23));
      expect(HijriService.toHijri(DateTime(2026, 3, 1)), (1447, 9, 12));
    });

    test('التحويل ذهاباً وإياباً عبر قرون', () {
      for (final y in [1990, 2000, 2010, 2020, 2026, 2040]) {
        for (final m in [1, 4, 8, 12]) {
          final g = DateTime(y, m, 15);
          final (hy, hm, hd) = HijriService.toHijri(g);
          final back = HijriService.toGregorian(hy, hm, hd);
          expect(back.year, y, reason: 'سنة \$y/\$m');
          expect(back.month, m, reason: 'سنة \$y/\$m');
          expect(back.day, 15, reason: 'سنة \$y/\$m');
        }
      }
    });

    test('طول الشهور والسنوات الكبيسة', () {
      expect(HijriService.hijriMonthLength(1447, 1), 30);
      expect(HijriService.hijriMonthLength(1447, 2), 29);
      expect(HijriService.isHijriLeap(1447), isTrue);
      expect(HijriService.hijriMonthLength(1447, 12), 30);
      var foundNonLeap = false;
      for (var y = 1440; y <= 1470; y++) {
        if (!HijriService.isHijriLeap(y)) {
          expect(HijriService.hijriMonthLength(y, 12), 29);
          foundNonLeap = true;
        }
      }
      expect(foundNonLeap, isTrue);
    });

    test('أسماء الشهور الاثنا عشر بالترتيب', () {
      expect(HijriService.hijriMonths.length, 12);
      expect(HijriService.hijriMonths.first, contains('محرم'));
    });
  });
}
