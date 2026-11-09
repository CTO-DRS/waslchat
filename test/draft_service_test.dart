import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_chat/services/draft_service.dart';

/// اختبارات وحدة: المسودات المحلية (بند المرحلة 1: الرسائل المجدولة والمسودات)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DraftService.reset();
  });

  test('حفظ واسترجاع مسودة', () async {
    await DraftService.load();
    expect(DraftService.get('c1'), isNull);
    await DraftService.save('c1', 'مرحبا كيف حالك');
    expect(DraftService.get('c1'), 'مرحبا كيف حالك');
  });

  test('النص الفارغ أو الفراغات يحذف المسودة', () async {
    await DraftService.load();
    await DraftService.save('c1', 'نص');
    await DraftService.save('c1', '   ');
    expect(DraftService.get('c1'), isNull);
    // حذف مسودة غير موجودة لا يفشل
    await DraftService.save('c2', '');
    expect(DraftService.get('c2'), isNull);
  });

  test('الاستمرارية: تُقرأ من التخزين بعد reset وإعادة التحميل', () async {
    await DraftService.load();
    await DraftService.save('c1', 'مسودة قديمة');
    DraftService.reset();
    expect(DraftService.get('c1'), isNull); // من الذاكرة فقط
    await DraftService.load();
    expect(DraftService.get('c1'), 'مسودة قديمة'); // من التخزين
  });

  test('مسودات متعددة مستقلة لكل محادثة', () async {
    await DraftService.load();
    await DraftService.save('a', 'مسودة أ');
    await DraftService.save('b', 'مسودة ب');
    await DraftService.clear('a');
    expect(DraftService.get('a'), isNull);
    expect(DraftService.get('b'), 'مسودة ب');
    expect(DraftService.drafts.value.length, 1);
  });
}
