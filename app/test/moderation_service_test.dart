import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/moderation_service.dart';

/// اختبارات نقية لخدمة الإشراف — بلا شبكة ولا قاعدة بيانات.
/// الفرض النهائي من الخادم (ترحيل 023)؛ هنا نتحقق من تصنيف أخطاء الخادم
/// وتنسيق المدد وأسطر السجل التي يعرضها التطبيق.
void main() {
  group('رسائل أخطاء الإرسال', () {
    test('الكتم يعطي رسالة واضحة', () {
      final e = Exception('PostgrestException: COMMUNITY_MUTED');
      expect(ModerationService.sendErrorHint(e), contains('مكتوم'));
    });
    test('فلتر الكلمات يعطي رسالة واضحة', () {
      final e = Exception('PostgrestException: COMMUNITY_FILTER');
      expect(ModerationService.sendErrorHint(e), contains('محجوبة'));
    });
    test('الخطأ الغريب يعيد null بلا رسالة إشراف', () {
      expect(ModerationService.sendErrorHint(Exception('network error')), isNull);
      expect(ModerationService.sendErrorHint('BLOCKED'), isNull);
    });
    test('انضمام مطرود يعطي رسالة الحظر', () {
      expect(ModerationService.joinErrorHint(Exception('x COMMUNITY_BANNED y')),
          contains('مطرود'));
      expect(ModerationService.joinErrorHint(Exception('community not found')),
          isNull);
    });
  });

  group('تنسيق المدد المتبقية', () {
    test('أقل من دقيقة', () {
      expect(ModerationService.formatRemaining(const Duration(seconds: 30)),
          'أقل من دقيقة');
    });
    test('دقائق مفردة ومثنى وجمع', () {
      expect(ModerationService.formatRemaining(const Duration(minutes: 1)),
          'دقيقة واحدة');
      expect(ModerationService.formatRemaining(const Duration(minutes: 2)),
          'دقيقتان');
      expect(ModerationService.formatRemaining(const Duration(minutes: 9)),
          '9 دقائق');
      expect(ModerationService.formatRemaining(const Duration(minutes: 25)),
          '25 دقيقة');
    });
    test('ساعات مع دقائق', () {
      expect(
          ModerationService.formatRemaining(
              const Duration(hours: 2, minutes: 30)),
          'ساعتان و30 دقيقة');
      expect(ModerationService.formatRemaining(const Duration(hours: 12)),
          '12 ساعة');
    });
    test('أيام مع ساعات', () {
      expect(
          ModerationService.formatRemaining(
              const Duration(days: 2, hours: 5)),
          'يومان و5 ساعات');
      expect(ModerationService.formatRemaining(const Duration(days: 30)),
          '30 يوماً');
    });
  });

  group('تنسيق وقت الانتهاء', () {
    test('نفس اليوم يعرض الوقت فقط', () {
      final now = DateTime(2026, 11, 13, 10, 5);
      final until = DateTime(2026, 11, 13, 10, 45);
      expect(ModerationService.formatUntil(until, now), '10:45');
    });
    test('يوم آخر يعرض اليوم والشهر والوقت', () {
      final now = DateTime(2026, 11, 13, 10, 5);
      final until = DateTime(2026, 11, 14, 9, 45);
      expect(ModerationService.formatUntil(until, now), '14 نوفمبر، 09:45');
    });
  });

  group('أسطر سجل الإشراف', () {
    test('كتم بسبب وبواسطة', () {
      final line = ModerationService.describeLog({
        'action': 'mute',
        'actor_name': 'سعيد',
        'target_name': 'أحمد',
        'details': 'إزعاج',
      });
      expect(line, contains('كتم'));
      expect(line, contains('أحمد'));
      expect(line, contains('إزعاج'));
      expect(line, contains('سعيد'));
    });
    test('طرد وحظر بلا سبب', () {
      final line = ModerationService.describeLog({
        'action': 'ban',
        'actor_name': 'المالك',
        'target_name': 'زيد',
      });
      expect(line, contains('طرد وحظر'));
      expect(line, contains('زيد'));
    });
    test('إضافة وإزالة كلمات الفلتر', () {
      expect(
          ModerationService.describeLog(
              {'action': 'filter_add', 'details': 'كلمة', 'actor_name': 'س'}),
          contains('«كلمة»'));
      expect(
          ModerationService.describeLog(
              {'action': 'filter_remove', 'details': 'كلمة', 'actor_name': 'س'}),
          contains('إزالة'));
    });
    test('إجراء مجهول لا يكسر الواجهة', () {
      expect(ModerationService.describeLog({'action': 'x'}), isNotEmpty);
    });
  });

  group('خيارات الكتم', () {
    test('ضمن حد الخادم 43200 دقيقة ومقيمتها أرقام صحيحة', () {
      for (final (label, minutes) in ModerationService.muteChoices) {
        expect(label, isNotEmpty);
        expect(minutes, inInclusiveRange(1, 43200));
      }
    });
  });
}
