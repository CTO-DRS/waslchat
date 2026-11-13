import '../config.dart';

/// إحصاءات المشاهدة للقنوات الكبيرة (المرحلة 4).
///
/// كل عضو قناة يسجَّل مشاهدته لكل منشور مرة واحدة (صف في message_views)،
/// والعدّاد يظهر لكل أعضاء القناة تحت كل منشور، وإحصاءات موسعة (المتوسط
/// والإجمالي وآخر 30 منشوراً) تقرؤها إدارة القناة فقط من الخادم.
class ChannelStatsService {
  ChannelStatsService._();

  /// تسجيل مشاهدتي لهذه المنشورات (يستدعى عند عرضها في شاشة القناة)
  static Future<void> trackViews(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      await supabase.rpc('channel_track_views', params: {'p_ids': messageIds});
    } catch (_) {
      // بلا ترحيل 025: تجاهل صامت — العدّاد ميزة إضافية لا تعطيل للعرض
    }
  }

  /// عدّادات المشاهدة لرسائل دفعة واحدة: message_id -> عدد المشاهدات
  static Future<Map<String, int>> counts(List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    try {
      final data = await supabase.rpc('channel_view_counts',
          params: {'p_ids': messageIds});
      final map = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(data as List)) {
        map[row['message_id'] as String] = (row['views'] as num?)?.toInt() ?? 0;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// إحصاءات القناة الكاملة (لمشرفيها): أول صف يحمل الإجماليات والبقية منشورات
  static Future<List<Map<String, dynamic>>> stats(String convId) async {
    final data =
        await supabase.rpc('channel_stats', params: {'p_conv': convId});
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ---------- مساعدات عرض نقية (مُختبَرة) ----------

  /// تنسيق الأعداد العربية: 999 / 1.2 ألف / 3.4 مليون
  static String formatCount(num n) {
    if (n < 0) return '0';
    if (n < 1000) return n.round().toString();
    if (n < 1000000) {
      final v = n / 1000;
      return '${_trim(v)} ألف';
    }
    final m = n / 1000000;
    return '${_trim(m)} مليون';
  }

  /// قصّ الصفر الزائد: 1.0 -> 1 ، 1.25 -> 1.3 (منزلة واحدة تكفي للعدّادات)
  static String _trim(num v) {
    var s = v.toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  /// سطر المشاهدات تحت المنشور: «1.2 ألف مشاهدة» بجمع عربي سليم
  static String viewsLabel(num views) {
    if (views <= 0) return 'لا مشاهدات';
    if (views == 1) return 'مشاهدة واحدة';
    if (views == 2) return 'مشاهدتان';
    if (views < 11) return '${formatCount(views)} مشاهدات';
    return '${formatCount(views)} مشاهدة';
  }

  /// سطر متوسط المشاهدات في ورقة الإحصاءات
  static String averageLabel(num avg) {
    if (avg <= 0) return 'لا مشاهدات بعد';
    return 'متوسط ${viewsLabel(avg)} للمنشور';
  }
}
