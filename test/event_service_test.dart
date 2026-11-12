import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/event_service.dart';

/// اختبارات نقية لخدمة أحداث المجتمع — بلا شبكة ولا قاعدة بيانات.
/// الفرض النهائي من الخادم (ترحيل 024)؛ هنا نتحقق من تنسيق الأزمنة والردود
/// وخيارات التذكير والمدة التي يعرضها التطبيق.
void main() {
  group('تسميات ردود الحضور', () {
    test('الردود الثلاثة بأسمائها', () {
      expect(CommunityEventService.responseLabel('going'), 'سأحضر');
      expect(CommunityEventService.responseLabel('maybe'), 'ربما');
      expect(CommunityEventService.responseLabel('not_going'), 'لن أحضر');
    });
    test('الرد الغريب والفارغ يعطي التسمية المحايدة', () {
      expect(CommunityEventService.responseLabel(null), 'لن أحضر');
      expect(CommunityEventService.responseLabel('x'), 'لن أحضر');
    });
    test('أيقونات الردود معرفة للثلاثة', () {
      expect(CommunityEventService.responseIcon('going'), isNotNull);
      expect(CommunityEventService.responseIcon('maybe'), isNotNull);
      expect(CommunityEventService.responseIcon('not_going'), isNotNull);
    });
  });

  group('تنسيق وقت البدء', () {
    final now = DateTime(2026, 11, 13, 10, 5);
    test('نفس اليوم يعرض «اليوم» والوقت', () {
      expect(CommunityEventService.formatStartsAt(DateTime(2026, 11, 13, 20, 30), now),
          'اليوم 20:30');
    });
    test('غداً يعرض «غداً» والوقت', () {
      expect(CommunityEventService.formatStartsAt(DateTime(2026, 11, 14, 9, 0), now),
          'غداً 09:00');
    });
    test('يوم آخر بنفس السنة يعرض اليوم والشهر والوقت', () {
      expect(CommunityEventService.formatStartsAt(DateTime(2026, 11, 20, 18, 30), now),
          '20 نوفمبر، 18:30');
    });
    test('سنة أخرى تُضاف بعد الشهر', () {
      expect(CommunityEventService.formatStartsAt(DateTime(2027, 1, 2, 8, 15), now),
          '2 يناير 2027، 08:15');
    });
  });

  group('المتبقي حتى البدء', () {
    test('الماضي واللحظة الحالية: يبدأ الآن', () {
      expect(CommunityEventService.startsInLabel(const Duration(seconds: -5)), 'يبدأ الآن');
      expect(CommunityEventService.startsInLabel(Duration.zero), 'يبدأ الآن');
    });
    test('دقائق بمفردها ومثناها وجمعها', () {
      expect(CommunityEventService.startsInLabel(const Duration(minutes: 1)),
          'بعد دقيقة واحدة');
      expect(CommunityEventService.startsInLabel(const Duration(minutes: 2)),
          'بعد دقيقتين');
      expect(CommunityEventService.startsInLabel(const Duration(minutes: 9)),
          'بعد 9 دقائق');
      expect(CommunityEventService.startsInLabel(const Duration(minutes: 25)),
          'بعد 25 دقيقة');
    });
    test('ساعات مع دقائق', () {
      expect(CommunityEventService.startsInLabel(const Duration(hours: 2, minutes: 30)),
          'بعد ساعتين و30 دقيقة');
      expect(CommunityEventService.startsInLabel(const Duration(hours: 12)),
          'بعد 12 ساعة');
    });
    test('أيام مع ساعات', () {
      expect(CommunityEventService.startsInLabel(const Duration(days: 2, hours: 5)),
          'بعد يومين و5 ساعات');
      expect(CommunityEventService.startsInLabel(const Duration(days: 30)),
          'بعد 30 يوماً');
    });
  });

  group('الحدث الجارٍ الآن', () {
    test('بين البدء والنهاية = جارٍ', () {
      final now = DateTime(2026, 11, 13, 12, 0);
      expect(
          CommunityEventService.isLive(DateTime(2026, 11, 13, 11, 0), 120, now), isTrue);
    });
    test('قبل البدء وبعده = ليس جارياً', () {
      final now = DateTime(2026, 11, 13, 12, 0);
      expect(
          CommunityEventService.isLive(DateTime(2026, 11, 13, 12, 1), 60, now), isFalse);
      expect(
          CommunityEventService.isLive(DateTime(2026, 11, 13, 10, 0), 60, now), isFalse);
    });
  });

  group('خيارات التذكير والمدة داخل حدود الخادم', () {
    test('التذكير ضمن المجموعة المسموحة {0,15,30,60,180,1440} وبلا تكرار', () {
      final minutes = CommunityEventService.remindChoices.map((c) => c.$2).toSet();
      expect(minutes, {0, 15, 30, 60, 180, 1440});
      for (final (label, _) in CommunityEventService.remindChoices) {
        expect(label, isNotEmpty);
      }
    });
    test('المدد داخل حد الخادم 5 → 10080 دقيقة', () {
      for (final (label, d) in CommunityEventService.durationChoices) {
        expect(label, isNotEmpty);
        expect(d, inInclusiveRange(5, 10080));
      }
    });
    test('تسمية التذكير تُعاد كما هي للقيم المعروفة ونص بديل للغريبة', () {
      expect(CommunityEventService.remindLabel(60), 'قبل ساعة');
      expect(CommunityEventService.remindLabel(0), 'بلا تذكير');
      expect(CommunityEventService.remindLabel(45), 'تذكير قبل 45 دقيقة');
    });
  });
}
