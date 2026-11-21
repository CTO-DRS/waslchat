/// قواعد Web Share Target النقية (1.21.0) — بلا أي وصول للمنصة، تُختبَر
/// في VM مباشرة: ملف `share_target_rules.dart` منفصل عن خدمة PWA كي
/// يستورده التنفيذ الحي والمحتضنان بلا دورة استيراد.
///
/// العقد الصادق: وسم المشاركة القادم من عامل الصفحة يُتحقق **قبل أي
/// جلب** — وسم وحيد بأحرف آمنة وطول معلن، فلا مسار غريب ولا اجتياز
/// مجلدات عبر المعامل، ولا جلب أصلاً لمن وصل بلا وسم صالح.
library;

class ShareTargetRules {
  ShareTargetRules._();

  /// أقصى طول للوسم المولد من عامل الصفحة (الوسم الفعلي أقصر بكثير)
  static const int maxTokenLength = 32;

  /// هل الوسم صالح للجلب؟ [a-z0-9] حصراً — لا نقاط ولا شرطات مائلة
  /// ولا مسارات نسبية ممكنة أصلاً.
  static bool isValidToken(String token) =>
      token.isNotEmpty &&
      token.length <= maxTokenLength &&
      RegExp(r'^[a-z0-9]+$').hasMatch(token);

  /// استخراج الوسم من معاملات الرابط — null إن غاب أو خالفت الصيغة.
  static String? tokenFromQuery(Map<String, String> query) {
    final t = query['share'];
    if (t == null || !isValidToken(t)) return null;
    return t;
  }
}
