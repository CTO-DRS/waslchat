/// التقويم الهجري والميلادي (المرحلة 5 — v0.14.0): تحويل دقيق يعمل محلياً
/// بلا شبكة وفق **التقويم الهجري الجدولي المدني** القياسي (نفسه المستخدم في
/// ICU ومكتبات التقويم القياسية): السنوات الكبيسة إحدى عشرة في كل ثلاثين
/// (11y+14) mod 30 < 11، الشهور الفردية 30 يوماً والزوجية 29 عدا ذي الحجة
/// في السنة الكبيسة.
/// الصدق التصميمي: هذا تقويم **حسابي** — قد يخالف الرؤية الشرعية (أم القرى)
/// يوماً واحداً في بعض الشهور، لذا تُعرض التواريخ بصفة «هـ» حسابية لا رسمية.
class HijriService {
  HijriService._();

  /// عهد التقويم: رقم اليوم القياسي (JDN الظهيرة) لـ1 محرم سنة 1هـ
  /// = 19 يوليو 622م (ميلادي مطلق).
  static const int _epochJdn = 1948440;

  /// مواضع السنوات الكبيسة داخل دورة الثلاثين (11 سنة كبيسة).
  static const _leapPositions = [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29];

  static bool isHijriLeap(int hy) => (11 * hy + 14) % 30 < 11;

  /// طول الشهر الهجري: الفردي 30، الزوجي 29، عدا ذو الحجة في الكبيسة 30.
  static int hijriMonthLength(int hy, int hm) {
    if (hm.isOdd) return 30;
    if (hm == 12 && isHijriLeap(hy)) return 30;
    return 29;
  }

  /// عدد السنوات الكبيسة من 1هـ حتى [n]هـ.
  static int _leapCount(int n) {
    if (n <= 0) return 0;
    final q = n ~/ 30, r = n % 30;
    var c = 11 * q;
    for (final s in _leapPositions) {
      if (s <= r) c++;
    }
    return c;
  }

  /// الأيام قبل بداية السنة الهجرية [hy].
  static int _daysBeforeYear(int hy) => 354 * (hy - 1) + _leapCount(hy - 1);

  // ---------- ميلادي ← JDN ← هجري ----------

  /// رقم اليوم القياسي (JDN الظهيرة) لتاريخ ميلادي.
  static int gregorianToJdn(int gy, int gm, int gd) {
    final a = (14 - gm) ~/ 12;
    final yy = gy + 4800 - a;
    final mm = gm + 12 * a - 3;
    return gd + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - yy ~/ 100 + yy ~/ 400 - 32045;
  }

  /// تاريخ ميلادي من رقم اليوم القياسي.
  static (int, int, int) jdnToGregorian(int jdn) {
    final a = jdn + 32044;
    final b = (4 * a + 3) ~/ 146097;
    final c = a - 146097 * b ~/ 4;
    final d = (4 * c + 3) ~/ 1461;
    final e = c - 1461 * d ~/ 4;
    final mm = (5 * e + 2) ~/ 153;
    final day = e - (153 * mm + 2) ~/ 5 + 1;
    final month = mm + 3 - 12 * (mm ~/ 10);
    final year = 100 * b + d - 4800 + mm ~/ 10;
    return (year, month, day);
  }

  /// تحويل تاريخ ميلادي إلى هجري: (السنة، الشهر، اليوم).
  static (int, int, int) toHijri(DateTime g) {
    final days = gregorianToJdn(g.year, g.month, g.day) - _epochJdn;
    var y = (days * 30 + 3) ~/ 10631;
    if (y < 1) y = 1;
    while (_daysBeforeYear(y) > days) {
      y--;
    }
    while (_daysBeforeYear(y + 1) <= days) {
      y++;
    }
    var rem = days - _daysBeforeYear(y);
    var m = 1;
    while (m <= 12 && rem >= hijriMonthLength(y, m)) {
      rem -= hijriMonthLength(y, m);
      m++;
    }
    return (y, m, rem + 1);
  }

  /// تحويل تاريخ هجري إلى ميلادي (للاختبار وعرض المدى).
  static DateTime toGregorian(int hy, int hm, int hd) {
    var jdn = _epochJdn + _daysBeforeYear(hy) + hd - 1;
    for (var m = 1; m < hm; m++) {
      jdn += hijriMonthLength(hy, m);
    }
    final (y, m, d) = jdnToGregorian(jdn);
    return DateTime(y, m, d);
  }

  /// أسماء الأشهر الهجرية.
  static const hijriMonths = [
    'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر',
    'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان',
    'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
  ];

  /// أسماء الأشهر الميلادية العربية.
  static const gregorianMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// «1448هـ» بصيغة مختصرة.
  static String hijriShort(DateTime g) {
    final (hy, hm, hd) = toHijri(g);
    return '$hd ${hijriMonths[hm - 1]} ${hy}هـ';
  }

  /// «20 نوفمبر 2026م · 2 جمادى الآخرة 1448هـ» — السطر المزدوج للأحداث.
  static String formatBoth(DateTime g) {
    final h = hijriShort(g);
    final m = '${g.day} ${gregorianMonths[g.month - 1]} ${g.year}م';
    return '$m · $h';
  }
}
