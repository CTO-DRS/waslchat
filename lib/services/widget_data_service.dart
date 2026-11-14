/// ويدجت «آخر المحادثات» (المرحلة 8 ب — 0.21.0)
///
/// يكتب آخر 3 محادثات (الاسم + سطر المعاينة المفكوك + الوقت + عدد غير
/// المقروء) في تخزين الويدجت ويطلب تحديثه — كل شيء محلي على جهازك حصراً،
/// والويدجت يقرأ ما كتبت أنت لا ما يرسله أحد.
///
/// التحديث يجري عند فتح القائمة الرئيسية أو العودة من محادثة (السلوك
/// الصادق الموثق): الويدجت لا ينبض بلا فتح تطبيق لأن الهدف هو بلا خدمة
/// خلفية تستهلك بطارية — الصادق أطول عمراً للجهاز.
///
/// أي فشل يهبط للسلوك السابق: بلا ويدجت، ولا يتعطل شيء في التطبيق.
import 'package:home_widget/home_widget.dart';

/// صف جاهز للكتابة
class WidgetRow {
  const WidgetRow(this.title, this.preview, this.time, this.unread);
  final String title;
  final String preview;
  final String time;
  final int unread;
}

class WidgetDataService {
  WidgetDataService._();

  /// اسم مزود الويدجت الأصلي (نفسه في AndroidManifest)
  static const providerName = 'WaslChatWidgetProvider';

  /// صف واحد من صفوف الويدجت: 3 صفوف حصراً
  static const maxRows = 3;

  /// يكتب الصفوف ويطلب التحديث — يعيد true عند النجاح على أندرويد.
  static Future<bool> update(List<WidgetRow> rows) async {
    try {
      final limited = rows.take(maxRows).toList();
      for (var i = 0; i < maxRows; i++) {
        if (i < limited.length) {
          final r = limited[i];
          await HomeWidget.saveWidgetData<String>('r${i}_title', _short(r.title, 32));
          await HomeWidget.saveWidgetData<String>('r${i}_preview', _short(r.preview, 48));
          await HomeWidget.saveWidgetData<String>('r${i}_time', r.time);
          await HomeWidget.saveWidgetData<String>(
              'r${i}_unread', r.unread > 0 ? (r.unread > 99 ? '99+' : '${r.unread}') : '');
        } else {
          await HomeWidget.saveWidgetData<String>('r${i}_title', null);
          await HomeWidget.saveWidgetData<String>('r${i}_preview', null);
          await HomeWidget.saveWidgetData<String>('r${i}_time', null);
          await HomeWidget.saveWidgetData<String>('r${i}_unread', null);
        }
      }
      await HomeWidget.saveWidgetData<int>('rows_count', limited.length);
      return await HomeWidget.updateWidget(
            androidName: providerName,
            name: providerName,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// قص نص بلا كسر كلمات نصفية مزعجة — الويدجت مساحة صغيرة
  static String _short(String s, int max) {
    s = s.replaceAll('\n', ' ').trim();
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1).trimRight()}…';
  }

  /// إزالة كل البيانات (عند تسجيل الخروج — لا محادثات تُعرض لغير صاحبها)
  static Future<void> clear() async {
    try {
      for (var i = 0; i < maxRows; i++) {
        await HomeWidget.saveWidgetData<String>('r${i}_title', null);
        await HomeWidget.saveWidgetData<String>('r${i}_preview', null);
        await HomeWidget.saveWidgetData<String>('r${i}_time', null);
        await HomeWidget.saveWidgetData<String>('r${i}_unread', null);
      }
      await HomeWidget.saveWidgetData<int>('rows_count', 0);
      await HomeWidget.updateWidget(androidName: providerName, name: providerName);
    } catch (_) {}
  }
}
