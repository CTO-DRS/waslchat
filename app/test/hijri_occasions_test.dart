// اختبارات المناسبات الهجرية (المرحلة 14 ب — 1.4.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/hijri_occasions_service.dart';
import 'package:wasl_chat/services/hijri_service.dart';

void main() {
  group('الثوابت والتكامل مع HijriService', () {
    test('خمس مناسبات ثابتة بلا تكرار (شهر، يوم)', () {
      expect(HijriOccasionsService.occasions.length, 5);
      final keys = HijriOccasionsService.occasions
          .map((o) => '${o.month}-${o.day}')
          .toSet();
      expect(keys.length, 5);
      // البنود الموثقة حصراً: الرأس ورمضان والعيدان وعرفة
      final titles = HijriOccasionsService.occasions.map((o) => o.title).join();
      expect(titles, contains('رمضان'));
      expect(titles, contains('الفطر'));
      expect(titles, contains('الأضحى'));
      expect(titles, contains('السنة الهجرية'));
      expect(titles, contains('عرفة'));
    });

    test('كل مناسبة تتحول حسابياً وتدور إلى نفس اليوم الهجري (تكامل)', () {
      final (hy, _, _) = HijriService.toHijri(DateTime(2026, 11, 16));
      for (final o in HijriOccasionsService.occasions) {
        final g = HijriService.toGregorian(hy, o.month, o.day);
        final back = HijriService.toHijri(g);
        expect(back.$1, hy);
        expect(back.$2, o.month);
        expect(back.$3, o.day);
      }
    });

    test('مناسبة الشهر الطويل والقفزي لا تنفجر (12 شهراً مقبولة)', () {
      // كل الأشهر المستخدمة (1، 9، 10، 12) صالحة في التقويم الحسابي
      for (final o in HijriOccasionsService.occasions) {
        expect(o.month, inInclusiveRange(1, 12));
        expect(o.day, inInclusiveRange(1, 30));
      }
    });
  });

  group('القادمة والترتيب', () {
    test('كل القادمة مستقبلية (أو اليوم) ومرتبة تصاعدياً وبالحد', () {
      final now = DateTime(2026, 11, 16, 14, 30);
      final r = HijriOccasionsService.upcoming(now: now, withinDays: 120, limit: 5);
      expect(r, isNotEmpty);
      final today = DateTime(now.year, now.month, now.day);
      for (var i = 0; i < r.length; i++) {
        expect(r[i].gregorian.isBefore(today), isFalse);
        expect(r[i].days, r[i].gregorian.difference(today).inDays);
        expect(r[i].days, inInclusiveRange(0, 120));
        if (i > 0) {
          expect(
              r[i].gregorian.isBefore(r[i - 1].gregorian), isFalse);
        }
      }
      expect(r.length, lessThanOrEqualTo(5));
    });

    test('الحد الزمني الضيق يقطع البعيد ولا يُخترع اقتراب', () {
      final now = DateTime(2026, 11, 16, 14, 30);
      final wide = HijriOccasionsService.upcoming(now: now, withinDays: 120, limit: 5);
      final narrow = HijriOccasionsService.upcoming(now: now, withinDays: 10, limit: 5);
      expect(narrow.length, lessThanOrEqualTo(wide.length));
      for (final a in narrow) {
        expect(a.days, lessThanOrEqualTo(10));
      }
    });

    test('تحديد — نفس اللحظة تعطي نفس القائمة (لا عشوائية)', () {
      final now = DateTime(2026, 3, 1, 9, 0);
      final a = HijriOccasionsService.upcoming(now: now);
      final b = HijriOccasionsService.upcoming(now: now);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].gregorian, b[i].gregorian);
        expect(a[i].occasion.title, b[i].occasion.title);
      }
    });

    test('رمضان داخل النافذة في بداية السنة الميلادية (قرب طبيعي)', () {
      // 1 يناير 2026: رمضان 1447 قادم خلال ~50 يوماً حسب المدنة — لا
      // نتوقع تاريخاً واقعياً محدداً (الرؤية قد تزيح) بل نتحقق وجوده
      // ضمن النافذة المفتوحة ودقته الحسابية
      final r = HijriOccasionsService.upcoming(
          now: DateTime(2026, 1, 1), withinDays: 120, limit: 5);
      final ramadan =
          r.where((a) => a.occasion.month == 9 && a.occasion.day == 1).toList();
      expect(ramadan.length, 1);
      final back = HijriService.toHijri(ramadan.first.gregorian);
      expect(back.$2, 9);
      expect(back.$3, 1);
    });
  });

  group('الصياغة العربية', () {
    test('daysLabel: اليوم وغداً وبعد غد والعدد', () {
      expect(HijriOccasionsService.daysLabel(0), 'اليوم');
      expect(HijriOccasionsService.daysLabel(-1), 'اليوم');
      expect(HijriOccasionsService.daysLabel(1), 'غداً');
      expect(HijriOccasionsService.daysLabel(2), 'بعد غد');
      expect(HijriOccasionsService.daysLabel(30), 'بعد 30 أيام');
    });

    test('التاريخ المزدوج يحمل الشهرين الهجري والميلادي', () {
      final (hy, _, _) = HijriService.toHijri(DateTime(2026, 11, 16));
      final g = HijriService.toGregorian(hy, 9, 1);
      final a = HijriOccasionAhead(
          occasion: HijriOccasionsService.occasions[1],
          gregorian: g,
          days: 5,
          hijriYear: hy);
      final label = HijriOccasionsService.dateLabel(a);
      expect(label, contains('-'));
      expect(HijriOccasionsService.markerKey(a), '$hy-9-1');
    });
  });
}
