/// تذكيرات المناسبات الهجرية العربية (المرحلة 14 ب — 1.4.0): فوق
/// HijriService الحسابية المتحققة (0.16.0) والتقويم المجتمعي (0.23.0).
///
/// المناسبات ثوابت هجرية (رأس السنة ورمضان والعيدان وعرفة) تُحوَّل
/// حسابياً إلى ميلادي لأقرب حدوث قادم — والتذكير **إشعارات محلية مجدولة
/// على جهازك حصراً** بنفس قناة التذكيرات (wasl-reminders) ومفتاح تعطيل
/// واحد يلغي ما جُدول — صفر خادم وصفر ترحيل.
///
/// الصدق التصميمي (يُعرض في الواجهة): التقويم الهجري هنا حسابي (مدنة
/// ثابتة) — **الرؤية الشرعية قد تزيح يوماً** عن الحساب، والتذكير تعرّف
/// لا إفتاء.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hijri_service.dart';

class HijriOccasion {
  const HijriOccasion({
    required this.month,
    required this.day,
    required this.title,
    required this.detail,
  });

  final int month; // الشهر الهجري (ثابت)
  final int day; // اليوم الهجري (ثابت)
  final String title;
  final String detail;
}

/// نتيجة قرب مناسبة: المناسبة وتاريخها الميلادي المحسوب وعدد الأيام.
class HijriOccasionAhead {
  const HijriOccasionAhead({
    required this.occasion,
    required this.gregorian,
    required this.days,
    required this.hijriYear,
  });

  final HijriOccasion occasion;
  final DateTime gregorian; // منتصف الليل المحلي ليوم المناسبة
  final int days; // فرق الأيام عن اليوم (0 = اليوم)
  final int hijriYear; // السنة الهجرية لهذا الحدوث
}

class HijriOccasionsService {
  HijriOccasionsService._();

  /// المناسبات الخمس الثابتة — الشهر واليوم هجريان لا يتغيران.
  static const List<HijriOccasion> occasions = [
    HijriOccasion(
        month: 1,
        day: 1,
        title: 'رأس السنة الهجرية',
        detail: 'مطلع سنة هجرية جديدة — محاسبة ونيّة'),
    HijriOccasion(
        month: 9,
        day: 1,
        title: 'بداية شهر رمضان',
        detail: 'مطلع شهر الصيام — شهر القرآن'),
    HijriOccasion(
        month: 10,
        day: 1,
        title: 'عيد الفطر السعيد',
        detail: 'أول شوال — عيد الفطر'),
    HijriOccasion(
        month: 12, day: 9, title: 'يوم عرفة', detail: 'يوم عرفة — قمة الحج'),
    HijriOccasion(
        month: 12,
        day: 10,
        title: 'عيد الأضحى المبارك',
        detail: 'عاشر ذو الحجة — عيد الأضحى'),
  ];

  /// المناسبات القادمة من الآن بترتيب الأقرب: لكل مناسبة أقرب حدوث
  /// مستقبلي (هذا العام الهجري أو القادم) — واليوم نفسه يُحتسب (days=0).
  static List<HijriOccasionAhead> upcoming({
    required DateTime now,
    int withinDays = 120,
    int limit = 5,
  }) {
    final (hy, _, _) = HijriService.toHijri(now);
    final today = DateTime(now.year, now.month, now.day);
    final out = <HijriOccasionAhead>[];
    for (final o in occasions) {
      DateTime? when;
      int? year;
      for (final y in [hy, hy + 1]) {
        final g = HijriService.toGregorian(y, o.month, o.day);
        final gMid = DateTime(g.year, g.month, g.day);
        if (!gMid.isBefore(today)) {
          when = gMid;
          year = y;
          break;
        }
      }
      if (when == null || year == null) continue;
      final days = when.difference(today).inDays;
      if (days > withinDays) continue;
      out.add(HijriOccasionAhead(
          occasion: o, gregorian: when, days: days, hijriYear: year));
    }
    out.sort((a, b) => a.gregorian.compareTo(b.gregorian));
    return out.take(limit).toList();
  }

  /// وصف القرب بالعربي — نقية.
  static String daysLabel(int days) {
    if (days <= 0) return 'اليوم';
    if (days == 1) return 'غداً';
    if (days == 2) return 'بعد غد';
    return 'بعد $days أيام';
  }

  /// تاريخ المناسبة بصيغته المزدوجة الهجري/ميلادي — نقية.
  static String dateLabel(HijriOccasionAhead a) =>
      '${HijriService.hijriShort(a.gregorian)} — '
      '${a.gregorian.year}-${a.gregorian.month.toString().padLeft(2, '0')}-'
      '${a.gregorian.day.toString().padLeft(2, '0')}';

  /// مفتاح تعليم مناسبة مجدولة — صياغة موحدة (hy-hm-hd).
  static String markerKey(HijriOccasionAhead a) =>
      '${a.hijriYear}-${a.occasion.month}-${a.occasion.day}';
}

/// التخزين المحلي للتذكيرات — أفضل جهد بلا شبكة: مفتاح التفعيل وتعليمات
/// ما جُدول لتفادي التكرار (الصف مستقل بأعضاء ثابتة — لا امتدادات).
class HijriOccasionsStore {
  HijriOccasionsStore._();

  static const String _onKey = 'wasl.hijri.reminders.on.v1';
  static const String _markersKey = 'wasl.hijri.scheduled.v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static Future<bool> enabled() async {
    try {
      return (await _storage.read(key: _onKey)) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool on) async {
    try {
      await _storage.write(key: _onKey, value: on ? '1' : '0');
    } catch (_) {}
  }

  static Future<List<String>> markers() async {
    try {
      final raw = await _storage.read(key: _markersKey);
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveMarkers(List<String> m) async {
    try {
      await _storage.write(key: _markersKey, value: jsonEncode(m));
    } catch (_) {}
  }

  /// لحظة إطلاق التذكير: الثامنة صباحاً بتاريخ المناسبة المحسوب.
  static DateTime fireAtFor(HijriOccasionAhead a) => DateTime(
      a.gregorian.year, a.gregorian.month, a.gregorian.day, 8, 0);
}
