import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/privacy_service.dart';

/// اختبارات وحدة: إعدادات الخصوصية الاختيارية (بند المرحلة 1)
/// بيئة الاختبار بلا خادم Supabase: يفشل الحفظ بصمت لكن القيم المحلية
/// تُطبَّق فوراً — وهذا هو السلوك المطلوب (الإعداد لا يعطّل التطبيق).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // إعادة الضبط بين الاختبارات (نفس مسار تسجيل الخروج)
    PrivacyService.reset();
  });

  test('القيم الافتراضية: كل شيء ظاهر (بلا إخفاء)', () {
    expect(PrivacyService.hidePresence.value, isFalse);
    expect(PrivacyService.hideReceipts.value, isFalse);
    // قاعدة المبادلة: بلا إخفاء تُعرض حالة الآخرين
    expect(!PrivacyService.hidePresence.value, isTrue);
  });

  test('save يطبّق الإخفاء محلياً فوراً حتى لو فشل الخادم', () async {
    await PrivacyService.save(hidePresenceValue: true, hideReceiptsValue: true);
    expect(PrivacyService.hidePresence.value, isTrue);
    expect(PrivacyService.hideReceipts.value, isTrue);
  });

  test('reset يعيد الافتراضات (مسار تسجيل الخروج)', () async {
    await PrivacyService.save(hidePresenceValue: true, hideReceiptsValue: false);
    PrivacyService.reset();
    expect(PrivacyService.hidePresence.value, isFalse);
    expect(PrivacyService.hideReceipts.value, isFalse);
  });

  test('تحديث أحادي: تغيير إعداد واحد لا يلمس الآخر', () async {
    await PrivacyService.save(hidePresenceValue: true, hideReceiptsValue: false);
    await PrivacyService.save(
        hidePresenceValue: PrivacyService.hidePresence.value,
        hideReceiptsValue: true);
    expect(PrivacyService.hidePresence.value, isTrue);
    expect(PrivacyService.hideReceipts.value, isTrue);
  });
}
