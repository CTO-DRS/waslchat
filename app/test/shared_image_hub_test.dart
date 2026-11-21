/// اختبارات مركز الصورة المشتركة (1.22.0): الاستهلاك الواحد، العمر
/// المعلن 10 دقائق، الجلب على غير الويب صمت صادق، والإسقاط الصريح.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/shared_image_hub.dart';

void main() {
  setUp(() {
    SharedImageHub.drop();
    SharedImageHub.now = DateTime.now;
  });

  test('بلا صورة: consume صادقة — null لا ادعاء', () {
    expect(SharedImageHub.consume(), isNull);
    expect(SharedImageHub.hasPending, isFalse);
  });

  test('الجلب على غير الويب: صمت صادق — المنصات الأصلية لا هدف مشاركة لها',
      () async {
    await SharedImageHub.pull();
    expect(SharedImageHub.hasPending, isFalse,
        reason: 'kIsWeb=false في VM فالجلب لا يمس الكاش أصلاً');
  });

  test('الاستهلاك الواحد: أول دردشة تأخذ البايتات وتصفرها', () {
    final bytes = [1, 2, 3, 255];
    SharedImageHub.debugSeed(bytes);
    expect(SharedImageHub.hasPending, isTrue);
    expect(SharedImageHub.consume(), bytes);
    expect(SharedImageHub.consume(), isNull,
        reason: 'لا صورة تُرفق مرتين');
  });

  test('العمر المعلن: بعد 10 دقائق تسقط بصدق بلا استهلاك', () {
    var clock = DateTime(2026, 1, 1, 12);
    SharedImageHub.now = () => clock;
    SharedImageHub.debugSeed([9, 9]);
    clock = clock.add(const Duration(minutes: 9));
    expect(SharedImageHub.hasPending, isTrue);
    clock = clock.add(const Duration(minutes: 2));
    expect(SharedImageHub.hasPending, isFalse);
    expect(SharedImageHub.consume(), isNull);
  });

  test('ضمن العمر: تبقى صالحة حتى 10 دقائق بالضبط', () {
    var clock = DateTime(2026, 1, 1, 12);
    SharedImageHub.now = () => clock;
    SharedImageHub.debugSeed([7]);
    clock = clock.add(const Duration(minutes: 10));
    expect(SharedImageHub.hasPending, isTrue,
        reason: 'الحد شامل: 10 دقائق بالضبط ما تزال صالحة');
  });

  test('drop يمسح صراحة — بلا صورة شبح', () {
    SharedImageHub.debugSeed([1]);
    SharedImageHub.drop();
    expect(SharedImageHub.consume(), isNull);
  });
}
