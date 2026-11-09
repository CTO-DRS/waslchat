import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات الوسائط على الجهاز (0.4.8 — بند المرحلة 1).
///
/// التنزيل التلقائي للفيديو قرار محلي بحت: لا يُرفع الإعداد للخادم
/// ولا يعلمه الطرف الآخر. النطاق الصادق: يُطبَّق على الفيديو الذي يصل
/// وأنت في المحادثة المفتوحة — التنزيل في الخلفية لكل المحادثات يحتاج
/// جدولة خلفية ويؤجَّل لإصدار لاحق. رسائل «عرض مرة واحدة» لا تُنزَّل
/// تلقائياً أبداً (استخدام صريح مقصود).
enum AutoDownloadRule {
  /// لا تنزيل تلقائي — بالضغط فقط
  never,

  /// تلقائي على واي-فاي فقط (الافتراضي)
  wifi,

  /// تلقائي على واي-فاي والبيانات الخلوية
  always,
}

class MediaPrefs {
  MediaPrefs._();

  static const String autoDownloadKey = 'video_auto_download';

  /// القاعدة الحالية (الافتراضي: واي-فاي فقط — نفس سلوك واتساب الافتراضي)
  static final ValueNotifier<AutoDownloadRule> autoDownload =
      ValueNotifier(AutoDownloadRule.wifi);

  /// تحميل القاعدة من الجهاز (آمن للاستدعاء المتكرر)
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(autoDownloadKey);
      if (v != null) autoDownload.value = ruleFromString(v) ?? AutoDownloadRule.wifi;
    } catch (_) {}
  }

  /// حفظ القاعدة على الجهاز
  static Future<void> setRule(AutoDownloadRule rule) async {
    autoDownload.value = rule;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(autoDownloadKey, rule.name);
    } catch (_) {}
  }

  /// من اسم مخزّن إلى قاعدة (null إن كان مجهولاً — إصدارات قديمة مثلاً)
  static AutoDownloadRule? ruleFromString(String v) {
    for (final r in AutoDownloadRule.values) {
      if (r.name == v) return r;
    }
    return null;
  }

  /// القرار الصافي: هل تسمح القاعدة بالتنزيل الآن؟
  /// علىWifi يعني واي-فاي أو إيثرنت — البيانات الخلوية ليست واي-فاي.
  static bool allows(AutoDownloadRule rule, {required bool onWifi}) {
    switch (rule) {
      case AutoDownloadRule.never:
        return false;
      case AutoDownloadRule.wifi:
        return onWifi;
      case AutoDownloadRule.always:
        return true;
    }
  }

  /// نص القاعدة للعرض في الإعدادات
  static String label(AutoDownloadRule rule) {
    switch (rule) {
      case AutoDownloadRule.never:
        return 'بالضغط فقط';
      case AutoDownloadRule.wifi:
        return 'واي-فاي فقط';
      case AutoDownloadRule.always:
        return 'دائماً (حتى البيانات)';
    }
  }

  /// شرح القاعدة الصادق للعرض تحت الاختيار
  static String description(AutoDownloadRule rule) {
    switch (rule) {
      case AutoDownloadRule.never:
        return 'لا شيء يُنزَّل إلا حين تضغط على الفيديو نفسه';
      case AutoDownloadRule.wifi:
        return 'يُنزَّل تلقائياً وأنت في المحادثة المفتوحة على واي-فاي — على البيانات بالضغط فقط';
      case AutoDownloadRule.always:
        return 'يُنزَّل تلقائياً في المحادثة المفتوحة حتى على البيانات الخلوية (يراقب باقتك)';
    }
  }
}
