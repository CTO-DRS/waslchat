import 'dart:convert';

/// مشاركة الموقع المشفّرة (بند المرحلة 1 — 0.4.6).
///
/// المحتوى كله داخل التشفير بين الطرفين: رسالة `type='location'` تحمل
/// JSON مشفّراً بالإحداثيات والدقة. الخادم يرى النوع فقط — لا بيانات
/// وصفية جديدة (مثل الاستطلاعات، ومعاينة القائمة نص عام «📍 موقع»).
///
/// خصوصية العرض: الفقاعة ترسم خريطتها محلياً (بلا بلاطات من مزوّد
/// خارجي) — فتح الخرائط الخارجي فعل صريح من المستخدم يسلّم الإحداثيات
/// لتطبيق الخرائط الذي اختاره. موثّق في TRANSPARENCY.md §1.
class LocationService {
  LocationService._();

  static const String tag = 'wasl-location-v1';

  /// دقة الإحداثيات: 6 كسور عشرية (~0.11 م) — أقصى ما يفيد ولن يزيد
  static const int precision = 6;

  /// حدّ الترميز قبل التشفير (حد التشفير 2900 بايت نصاً صريحاً)
  static const int maxPlainBytes = 2400;

  /// يرمّي [ArgumentError] عند أي تجاوز — ورقة الموقع تتحقق قبل الإرسال
  /// وهذه طبقة ثانية تمنع محتوى فاسداً.
  static String encode({
    required double lat,
    required double lng,
    double? accuracyM,
    String? label,
  }) {
    final la = _clamp(lat, -90, 90);
    final lo = _clamp(lng, -180, 180);
    final l = label?.trim() ?? '';
    if (l.length > maxLabelLen) throw ArgumentError('location label length');
    if (accuracyM != null && (accuracyM < 0 || accuracyM > 100000)) {
      throw ArgumentError('location accuracy');
    }
    return jsonEncode({
      't': tag,
      'la': _round(la),
      'lo': _round(lo),
      if (accuracyM != null) 'ac': accuracyM.round(),
      if (l.isNotEmpty) 'l': l,
    });
  }

  static LocationContent? decode(String plain) {
    try {
      final m = jsonDecode(plain);
      if (m is! Map || m['t'] != tag) return null;
      final la = m['la'];
      final lo = m['lo'];
      if (la is! num || lo is! num) return null;
      if (la < -90 || la > 90 || lo < -180 || lo > 180) return null;
      final ac = m['ac'];
      if (ac != null && (ac is! num || ac < 0 || ac > 100000)) return null;
      final l = m['l'];
      if (l != null && (l is! String || l.length > maxLabelLen)) return null;
      return LocationContent(
        lat: la.toDouble(),
        lng: lo.toDouble(),
        accuracyM: ac == null ? null : (ac as num).toDouble(),
        label: l is String && l.isNotEmpty ? l : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// هل يمرّ المحتوى حدّ البايتات قبل التشفير؟
  static bool withinLimit(String plain) =>
      utf8.encode(plain).length <= maxPlainBytes;

  /// رابط geo: القياسي — يفتح تطبيق الخرائط الذي اختاره الجهاز
  static String geoUri(double lat, double lng) =>
      'geo:$lat,$lng?q=$lat,$lng';

  static const int maxLabelLen = 80;

  static double _round(double v) {
    final f = _pow10;
    return (v * f).roundToDouble() / f;
  }

  static double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  static const double _pow10 = 1000000;
}

class LocationContent {
  const LocationContent({
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.label,
  });

  final double lat;
  final double lng;

  /// دقة القراءة بالمتر (اختيارية — تُعرض «±‎15 م»)
  final double? accuracyM;

  /// وصف اختياري للنقطة (مستقبلاً: نقطة مختارة على خريطة)
  final String? label;

  String get geoUri => LocationService.geoUri(lat, lng);
}
