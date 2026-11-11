import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// فحص «تحديث متوفر»: يقرأ آخر إصدار من الخادم (ترحيل 016) ويقارنه
/// بإصدار هذا التطبيق المعروف في AppConfig.
class UpdateService {
  /// يعيد صف الإصدار الأحدث إن كان أعلى من الإصدار الحالي، وإلا null.
  static Future<Map<String, dynamic>?> check() async {
    try {
      final row = await supabase.rpc('latest_app_version').single();
      final build = switch (row['build']) {
        final int b => b,
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      };
      if (build > AppConfig.appBuild) return row;
    } catch (_) {
      // الخادم غير متاح أو لم يُشغَّل الترحيل بعد: تجاهل بهدوء
    }
    return null;
  }

  static Future<void> openDownload() async {
    final uri = Uri.parse(AppConfig.apkUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}
