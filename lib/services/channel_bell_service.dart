/// جرس القنوات (المرحلة 8 ب — 0.21.0، ترحيل 032)
///
/// تفضيل الإشعار لكل قناة مستقلة على حدة:
/// - all: كل المنشورات تنبهني (الافتراضي)
/// - pinned: المنشورات المثبتة فقط (إعلانات المالك/المشرفين)
/// - mute: صمت تام — لا تصلني بيانات أصلاً
///
/// التطبيق هنا جزء العرض فقط: الحفظ عبر RPC الخادمي `set_channel_bell`
/// (عضو القناة يضبط تفضيله حصراً)، والتطبيق الحقيقي في دالة الإشعارات
/// الخادمية: الصمت حقيقي — الخادم لا يرسل البيانات أصلاً فلا يخترق شيء
/// الجهاز، وال«مثبتة فقط» يقارن عمود pinned للمنشور قبل الإرسال.
///
/// لا تخزين محلي مرجعي هنا بلا داعٍ: القائمة تقرأ الحالة من my_channels
/// (بعد ترحيل 032) وتحدّثها RPC، وأي فشل شبكة يعيد رسالة تعذر واضحة.
import '../config.dart';

class ChannelBellService {
  ChannelBellService._();

  /// القيم الحرفية المخزنة (نفسها في الترحيل والدالة الخادمية)
  static const all = 'all';
  static const pinned = 'pinned';
  static const mute = 'mute';

  /// هل القيمة صالحة؟ (قيمة غريبة تُعرض كالافتراضي ولا تكسر الواجهة)
  static bool isValid(String? v) =>
      v == all || v == pinned || v == mute;

  /// القيمة المطبَّعة: القيمة الصالحة كما هي، وإلا الافتراضي all
  static String normalize(String? v) => isValid(v) ? v! : all;

  /// الحالة العربية للعرض على زر الجرس
  static String label(String v) {
    switch (v) {
      case pinned:
        return 'المثبتة فقط';
      case mute:
        return 'صمت';
      default:
        return 'كل المنشورات';
    }
  }

  /// أيقونة الحالة للعرض
  static String icon(String v) {
    switch (v) {
      case pinned:
        return 'pin';
      case mute:
        return 'off';
      default:
        return 'on';
    }
  }

  /// يضبط تفضيل القناة عبر RPC الخادمي — يرمي استثناء عند الفشل
  /// (الواجهة تعرض «تعذّر الحفظ»).
  static Future<void> set(String conversationId, String pref) async {
    final p = normalize(pref);
    await supabase.rpc('set_channel_bell',
        params: {'conv': conversationId, 'pref': p});
  }
}
