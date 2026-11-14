// اختبارات شبكة التقويم الشهري (المرحلة 9 ب — 0.23.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/calendar_grid_service.dart';
import 'package:wasl_chat/services/hijri_service.dart';

void main() {
  group('يوم الأسبوع من JDN', () {
    test('معايرة معروفة: 1 يناير 2000 سبت', () {
      final jdn = HijriService.gregorianToJdn(2000, 1, 1);
      expect(CalendarGridService.weekdayOfJdn(jdn), 0); // السبت
    });

    test('2026-11-14 سبت (معايرة ثانية مستقلة)', () {
      final jdn = HijriService.gregorianToJdn(2026, 11, 14);
      expect(CalendarGridService.weekdayOfJdn(jdn), 0);
    });

    test('اليوم التالي يحرك الفهرس دورياً', () {
      final jdn = HijriService.gregorianToJdn(2026, 11, 15); // الأحد
      expect(CalendarGridService.weekdayOfJdn(jdn), 1);
      final jdnF = HijriService.gregorianToJdn(2026, 11, 20); // الجمعة
      expect(CalendarGridService.weekdayOfJdn(jdnF), 6);
    });
  });

  group('شبكة شهر هجري', () {
    test('العنوان بصيغة «الشهر السنةهـ» وعدد الأيام بطول الشهر', () {
      final g = CalendarGridService.hijri(1448, 6); // جمادى الآخرة
      expect(g.title, 'جمادى الآخرة 1448هـ');
      expect(g.days.length, HijriService.hijriMonthLength(1448, 6));
    });

    test('الفراغات الأولى تساوي يوم السبت-الأسبوع لأول الشهر', () {
      final g = CalendarGridService.hijri(1448, 6);
      final firstJdn = g.days.first.$2;
      expect(g.leadingBlanks, CalendarGridService.weekdayOfJdn(firstJdn));
    });

    test('أيام الشهر متتالية JDN ومعايرتها على الهجري', () {
      final g = CalendarGridService.hijri(1448, 6);
      for (var i = 0; i < g.days.length - 1; i++) {
        expect(g.days[i + 1].$2 - g.days[i].$2, 1);
      }
      // اليوم الأول فعلاً 1 جمادى الآخرة 1448
      final jdn = g.days.first.$2;
      final greg = HijriService.jdnToGregorian(jdn);
      final (hy, hm, hd) = HijriService.toHijri(DateTime(greg.$1, greg.$2, greg.$3));
      expect((hy, hm, hd), (1448, 6, 1));
    });

    test('الصفوف تغطي كل الخلايا', () {
      final g = CalendarGridService.hijri(1448, 6);
      expect(g.leadingBlanks + g.days.length, lessThanOrEqualTo(g.rows * 7));
      expect(g.rows * 7 - (g.leadingBlanks + g.days.length), lessThan(7));
    });

    test('الشهور المتتالية تلتف سنةً', () {
      expect(CalendarGridService.hijriNext(1448, 12), (1449, 1));
      expect(CalendarGridService.hijriPrev(1448, 1), (1447, 12));
      expect(CalendarGridService.hijriNext(1448, 3), (1448, 4));
    });
  });

  group('شبكة شهر ميلادي', () {
    test('نوفمبر 2026: 30 يوماً وتسمية صحيحة', () {
      final g = CalendarGridService.gregorian(2026, 11);
      expect(g.title, 'نوفمبر 2026م');
      expect(g.days.length, 30);
      expect(g.days.first.$1, 1);
      expect(g.days.last.$1, 30);
    });

    test('أول نوفمبر 2026 أحد (فراغات = 1)', () {
      final g = CalendarGridService.gregorian(2026, 11);
      expect(g.leadingBlanks, 1); // السبت فارغ ثم الأحد 1
    });

    test('يوم معين يحمل JDN صحيحاً: 14 نوفمبر 2026', () {
      final g = CalendarGridService.gregorian(2026, 11);
      final cell = g.days.firstWhere((d) => d.$1 == 14);
      expect(cell.$2, HijriService.gregorianToJdn(2026, 11, 14));
      // والهجري المقابل من الخدمة المتحققة
      expect(CalendarGridService.crossDayGregorian(cell.$2),
          HijriService.toHijri(DateTime(2026, 11, 14)).$3);
    });

    test('الأشهر الميلادية تلتف سنةً', () {
      expect(CalendarGridService.gregorianNext(2026, 12), (2027, 1));
      expect(CalendarGridService.gregorianPrev(2026, 1), (2025, 12));
    });
  });
}
