// اختبارات قواعد PWA النقية (المرحلة 12 — 0.28.0): القرارات الصادقة
// بلا منصة — أي غرابة تعطّل الميزة بأمان ولا تخمين.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/pwa_service.dart';

void main() {
  group('PwaRules.canInstall', () {
    test('زر التثبيت يظهر عند اكتمال الشروط الثلاثة', () {
      expect(
        PwaRules.canInstall(installable: true, standalone: false),
        isTrue,
      );
    });

    test('لا زر وهو مثبّت أصلاً نافذة مستقلة', () {
      expect(
        PwaRules.canInstall(installable: true, standalone: true),
        isFalse,
      );
    });

    test('لا زر قبل أن يقدّم المتصفح حدث التثبيت', () {
      expect(
        PwaRules.canInstall(installable: false, standalone: false),
        isFalse,
      );
    });
  });

  group('PwaRules.shouldSuggestInstall', () {
    test('يُقترح مرة واحدة — الرفض يمنع التكرار', () {
      expect(
        PwaRules.shouldSuggestInstall(
            installable: true, standalone: false, dismissed: false),
        isTrue,
      );
      expect(
        PwaRules.shouldSuggestInstall(
            installable: true, standalone: false, dismissed: true),
        isFalse,
      );
    });

    test('المثبّت لا يُقترح عليه التثبيت أبداً', () {
      expect(
        PwaRules.shouldSuggestInstall(
            installable: true, standalone: true, dismissed: false),
        isFalse,
      );
    });
  });

  group('PwaRules.workerLabel — تقارير Service Worker الصادقة', () {
    test('متصفح بلا دعم يعلن ذلك صراحة', () {
      expect(
        PwaRules.workerLabel(
            supported: false, active: false, waiting: false),
        contains('لا يدعم'),
      );
    });

    test('worker انتظار = تحديث جاهز بإعادة الفتح', () {
      final label = PwaRules.workerLabel(
          supported: true, active: true, waiting: true);
      expect(label, contains('تحديث جاهز'));
    });

    test('worker نشط بلا انتظار = عمل جزئي دون اتصال بلا ادعاء كامل', () {
      final label = PwaRules.workerLabel(
          supported: true, active: true, waiting: false);
      expect(label, contains('جزئياً'));
    });

    test('بلا worker = لم يُسجَّل بعد', () {
      final label = PwaRules.workerLabel(
          supported: true, active: false, waiting: false);
      expect(label, contains('لم يُسجَّل'));
    });
  });

  test('نص الخبرة دون اتصال يعلن الحد الصادق: واجهة فقط', () {
    expect(PwaRules.offlineHonestText, contains('الواجهة'));
    expect(PwaRules.offlineHonestText, contains('تحتاج اتصالاً'));
  });
}
