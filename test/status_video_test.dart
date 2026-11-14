import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/status_service.dart';

/// اختبارات نقية لفيديو الحالات والرد بحالة (المرحلة 11 ب — 0.27.0) —
/// بلا شبكة ولا تشفير: الحدود الصارمة وتحقق الفيديو وبحث اسم الأصل
/// وسطر رأس الرد الصادق كلها قرارات محلية تُثبت هنا.
void main() {
  group('تحقق فيديو الحالة', () {
    test('حدود البايتات صارمة: فارغ مرفوض والحد الأقصى مرفوض وما دونه سليم', () {
      expect(StatusService.validateVideo(bytes: 0), isNotNull);
      expect(
        StatusService.validateVideo(bytes: StatusService.maxVideoBytes + 1),
        contains('12 ميغابايت'),
      );
      expect(
        StatusService.validateVideo(bytes: StatusService.maxVideoBytes),
        isNull,
      );
    });

    test('المدة المقاسة تُفرض: فوق 15 ثانية مرفوض وما داخلها سليم', () {
      expect(
        StatusService.validateVideo(
            bytes: 1000, durationSeconds: StatusService.maxVideoSeconds + 1),
        contains('15 ثانية'),
      );
      expect(
        StatusService.validateVideo(
            bytes: 1000, durationSeconds: StatusService.maxVideoSeconds),
        isNull,
      );
      expect(
        StatusService.validateVideo(bytes: 1000, durationSeconds: 1),
        isNull,
      );
    });

    test('مدة غير صالحة (صفر أو سالبة) مرفوضة صادقاً', () {
      expect(
        StatusService.validateVideo(bytes: 1000, durationSeconds: 0),
        isNotNull,
      );
      expect(
        StatusService.validateVideo(bytes: 1000, durationSeconds: -3),
        isNotNull,
      );
    });

    test('المدة غير المقاسة لا تمنع النشر — حد البايتات هو الحارس الصارم', () {
      expect(StatusService.validateVideo(bytes: 1000), isNull);
    });

    test('الثوابت المعلنة في الواجهة مطابقة للتحقق', () {
      expect(StatusService.maxVideoSeconds, 15);
      expect(StatusService.maxVideoBytes, 12 * 1024 * 1024);
    });
  });

  group('اسم صاحب الحالة الأصلية من التغذية', () {
    List<Map<String, dynamic>> feed() => [
          {
            'author_name': 'سالم',
            'statuses': [
              {'status_id': 'st-a', 'created_at': '2026-11-14T10:00:00Z'},
              {'status_id': 'st-b', 'created_at': '2026-11-14T09:00:00Z'},
            ],
          },
          {
            'author_name': 'نورة',
            'statuses': [
              {'status_id': 'st-c', 'created_at': '2026-11-14T08:00:00Z'},
            ],
          },
        ];

    test('يجد اسم الأصل إذا كانت في التغذية المعروضة', () {
      expect(StatusService.replyAuthorName('st-a', feed()), 'سالم');
      expect(StatusService.replyAuthorName('st-c', feed()), 'نورة');
    });

    test('ما لم يوجد في التغذية (انتهى الأصل مثلاً) يعيد null — لا تخمين', () {
      expect(StatusService.replyAuthorName('st-gone', feed()), isNull);
      expect(StatusService.replyAuthorName(null, feed()), isNull);
      expect(StatusService.replyAuthorName('', feed()), isNull);
    });

    test('تغذية فارغة أو مشوهة لا ترمي استثناءً', () {
      expect(StatusService.replyAuthorName('st-a', []), isNull);
      expect(
        StatusService.replyAuthorName('st-a', [
          {'statuses': null}
        ]),
        isNull,
      );
    });
  });

  group('سطر رأس الرد الصادق', () {
    test('باسم الأصل إن وُجد — بلا اسم أو بفارغ: سطر عام بلا ادعاء', () {
      expect(StatusService.replyHeaderText('سالم'), 'رداً على حالة سالم');
      expect(StatusService.replyHeaderText(null), 'رد على حالة');
      expect(StatusService.replyHeaderText(''), 'رد على حالة');
    });
  });
}
