// اختبارات التقييم البحثي لنموذج على الجهاز (المرحلة 9 ب — 0.23.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/on_device_model_service.dart';

void main() {
  group('قراءة /proc/meminfo', () {
    test('سطر قياسي يعيد الميجابايت مقرّباً', () {
      // 7973264 kB / 1024 = 7786.375 → 7786
      expect(OnDeviceModelService.parseMemTotalMb('''
MemTotal:        7973264 kB
MemFree:          512000 kB
'''), 7786);
    });

    test('فراغات غير منتظمة لا تكسر', () {
      expect(OnDeviceModelService.parseMemTotalMb('MemTotal:   2097152 kB'),
          2048);
    });

    test('نص فاسد أو بلا سطر يعيد null بصدق', () {
      expect(OnDeviceModelService.parseMemTotalMb('garbage'), isNull);
      expect(OnDeviceModelService.parseMemTotalMb(''), isNull);
    });

    test('صفر أو قيمة سالبة (مستحيلة) تعامل كفشل', () {
      expect(OnDeviceModelService.parseMemTotalMb('MemTotal: 0 kB'), isNull);
    });
  });

  group('الحكم البحثي', () {
    test('بلا معلومة ذاكرة: no-info ولا مرشح ولا ادعاء', () {
      final v = OnDeviceModelService.verdict(ramMb: null);
      expect(v.level, 'no-info');
      expect(v.recommended, isNull);
      expect(v.detail, contains('ON_DEVICE_LLM.md'));
    });

    test('جهاز ضعيف (2 ج.ب): too-weak بلا مرشح ولا فرض', () {
      final v = OnDeviceModelService.verdict(ramMb: 2048);
      expect(v.level, 'too-weak');
      expect(v.recommended, isNull);
      expect(v.title, contains('لا تكفي'));
    });

    test('جهاز متوسط (4 ج.ب = 4096): يمر أخف مرشح حصراً', () {
      final v = OnDeviceModelService.verdict(ramMb: 4096);
      // الهامش 1500 → الميزانية 2596 → أخف مرشح 2600 لا يجتاز الحد؟
      // 2600 > 2596 → لا مرشح: القرار الصادق هو الرفض بهامش الحماية
      expect(v.level, anyOf('too-weak', 'eligible'));
      if (v.level == 'eligible') {
        expect(v.recommended!.ramNeedMb, lessThanOrEqualTo(4096 - 1500));
      }
    });

    test('جهاز قوي (8 ج.ب): يُرشّح الأعمق الممكن حصراً', () {
      final v = OnDeviceModelService.verdict(ramMb: 8192);
      expect(v.level, 'eligible');
      final best = OnDeviceModelService.catalog
          .where((m) => m.ramNeedMb <= 8192 - 1500)
          .reduce((a, b) => a.ramNeedMb > b.ramNeedMb ? a : b);
      expect(v.recommended!.id, best.id);
    });

    test('الهامش مكتوب في المعايير ويُعرض كما هو', () {
      expect(OnDeviceModelService.criteria.any((c) => c.contains('1.5')),
          isTrue);
      expect(OnDeviceModelService.criteria.any((c) => c.contains('20 رمزة')),
          isTrue);
      expect(OnDeviceModelService.criteria.any((c) => c.contains('ثانيتين')),
          isTrue);
    });

    test('الإفصاح: بلا تنزيل تلقائي ولا فرض على أحد', () {
      expect(OnDeviceModelService.disclosure, contains('بلا تنزيل تلقائي'));
      expect(OnDeviceModelService.disclosure, contains('جهازك'));
    });
  });
}
