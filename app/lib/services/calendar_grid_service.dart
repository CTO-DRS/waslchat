/// شبكة التقويم الشهري (المرحلة 9 ب — 0.23.0): حسابات نقية فوق خدمة الهجري
/// المتحققة (HijriService) لبناء شبكة شهر هجري أو ميلادي بأيامها ومواضعها،
/// وتحويل أي يوم إلى رقم يوم قياسي (JDN) يحمل تاريخه المزدوج — كلها
/// بلا شبكة ولا تخزين، ومعايير القبول تتحقق في اختبارات نقية.
import 'hijri_service.dart';

/// شبكة شهر واحد: عدد الفراغات قبل اليوم الأول وصفوف أيام الشهر.
class CalendarGrid {
  const CalendarGrid({
    required this.leadingBlanks,
    required this.days,
    required this.title,
  });

  /// خلايا فارغة قبل اليوم الأول (حسب يوم السبت بداية الأسبوع).
  final int leadingBlanks;

  /// أيام الشهر: (رقم اليوم، رقم اليوم القياسي JDN).
  final List<(int, int)> days;

  /// عنوان الشهر «ربيع الأول 1447هـ» أو «نوفمبر 2026م».
  final String title;

  /// عدد الأسطر التي يشغلها الشهر (7 خلايا للسطر).
  int get rows => (leadingBlanks + days.length + 6) ~/ 7;
}

class CalendarGridService {
  CalendarGridService._();

  /// أيام الأسبوع بالعربي بدايةً بالسبت (العرض بالشبكة).
  static const weekHeader = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

  /// يوم الأسبوع لرقم يوم قياسي: 0 = السبت … 6 = الجمعة.
  /// المعايرة: 1 يناير 2000 سبت وJDN له 2451545 → (2451545+2)%7=0 ✓
  static int weekdayOfJdn(int jdn) => (jdn + 2) % 7;

  /// شبكة شهر هجري: الأرقام الكبيرة هجرية والـJDN يحمل الميلادي المقابل.
  static CalendarGrid hijri(int hy, int hm) {
    final first = HijriService.toGregorian(hy, hm, 1);
    final jdn0 = HijriService.gregorianToJdn(first.year, first.month, first.day);
    final len = HijriService.hijriMonthLength(hy, hm);
    final days = [
      for (var d = 1; d <= len; d++) (d, jdn0 + d - 1),
    ];
    return CalendarGrid(
      leadingBlanks: weekdayOfJdn(jdn0),
      days: days,
      title: '${HijriService.hijriMonths[hm - 1]} ${hy}هـ',
    );
  }

  /// شبكة شهر ميلادي: الأرقام الكبيرة ميلادية والـJDN يحمل الهجري المقابل.
  static CalendarGrid gregorian(int gy, int gm) {
    final jdn0 = HijriService.gregorianToJdn(gy, gm, 1);
    final len = DateTime(gy, gm + 1, 0).day;
    final days = [
      for (var d = 1; d <= len; d++) (d, jdn0 + d - 1),
    ];
    return CalendarGrid(
      leadingBlanks: weekdayOfJdn(jdn0),
      days: days,
      title: '${HijriService.gregorianMonths[gm - 1]} ${gy}م',
    );
  }

  /// تسمية اليوم المتقاطعة لخلية: رقم اليوم المقابل في التقويم الآخر.
  /// في الشهر الهجري يظهر رقم اليوم الميلادي، وفي الميلادي رقم اليوم الهجري.
  static int crossDayHijri(int jdn) {
    final (y, m, d) = HijriService.jdnToGregorian(jdn);
    return d;
  }

  static int crossDayGregorian(int jdn) {
    final (y, m, d) = HijriService.jdnToGregorian(jdn);
    final (hy, hm, hd) = HijriService.toHijri(DateTime(y, m, d));
    return hd;
  }

  /// الشهر الهجري التالي (مع لف السنة).
  static (int, int) hijriNext(int hy, int hm) =>
      hm == 12 ? (hy + 1, 1) : (hy, hm + 1);

  /// الشهر الهجري السابق (مع لف السنة).
  static (int, int) hijriPrev(int hy, int hm) =>
      hm == 1 ? (hy - 1, 12) : (hy, hm - 1);

  /// الشهر الميلادي التالي/السابق (مع لف السنة).
  static (int, int) gregorianNext(int gy, int gm) =>
      gm == 12 ? (gy + 1, 1) : (gy, gm + 1);

  static (int, int) gregorianPrev(int gy, int gm) =>
      gm == 1 ? (gy - 1, 12) : (gy, gm - 1);
}
