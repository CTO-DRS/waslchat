/// خدمة الويب التقدمية PWA (المرحلة 12 — 0.28.0): التثبيت من المتصفح
/// وتقارير Service Worker الصادقة.
///
/// الواجهة الموحّدة: كل المنصات تعمل بها، والويب فقط له تنفيذ حي
/// (`pwa_service_web.dart`) والبقية stub — النمط نفسه لـplatform_name.
/// القواعد النقية `PwaRules` مُختبَرة على كل المنصات.
export 'pwa_service_stub.dart' if (dart.library.js_interop) 'pwa_service_web.dart';

/// قواعد قرار PWA النقية — بلا أي وصول للمنصة، تُختبَر في VM مباشرة.
class PwaRules {
  PwaRules._();

  /// هل يُعرض زر «تثبيت التطبيق»؟ الثلاثية الصادقة:
  /// المتصفح أرسل حدث التثبيت (installable) والتطبيق ليس مثبّتاً أصلاً
  /// (standalone=false) والمفتاح مُعدّ في هذا البناء.
  static bool canInstall({
    required bool installable,
    required bool standalone,
  }) =>
      installable && !standalone;

  /// هل نُقترح التثبيت؟ — لا اقتراح وهو مثبّت، ولا وهو مرفوض سابقاً.
  static bool shouldSuggestInstall({
    required bool installable,
    required bool standalone,
    required bool dismissed,
  }) =>
      installable && !standalone && !dismissed;

  /// التقرير الصادق لحالة Service Worker — نص عربي يُعرض كما هو:
  /// - null = المتصفح لا يدعم Service Worker إطلاقاً (متصفح قديم أو غير آمن).
  /// - «يعمل دون اتصال جزئياً» = worker نشط (الواجهة تُفتح بلا شبكة،
  ///   والمحادثات نفسها تحتاج الشبكة حصراً — التشفير اللحظي لا يعمل دون اتصال).
  /// - «يوجد تحديث جاهز» = worker انتظار يُفعَّل عند إعادة الفتح.
  static String workerLabel({
    required bool supported,
    required bool active,
    required bool waiting,
  }) {
    if (!supported) return 'المتصفح لا يدعم وضع العمل دون اتصال';
    if (waiting) return 'يوجد تحديث جاهز — أعد فتح التطبيق ليُفعَّل';
    if (active) return 'يعمل دون اتصال جزئياً — الواجهة تُفتح بلا شبكة';
    return 'لم يُسجَّل بعد — أعد فتح الصفحة';
  }

  /// نص الخبرة دون اتصال — الصدق أولاً: ما يعمل فعلاً بلا شبكة هو
  /// فتح الواجهة وحدها، وكل شيء آخر (رسائل، مكالمات، تشفير) يحتاج الشبكة.
  static const offlineHonestText =
      'بلا شبكة: تُفتح الواجهة والوسائط المخزّنة حصراً — المحادثات والمكالمات تحتاج اتصالاً';
}
