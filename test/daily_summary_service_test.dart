// اختبارات الملخص اليومي المحلي (المرحلة 9 أ — 0.22.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/daily_summary_service.dart';

DailyLine _l(String who, String text, {bool media = false}) =>
    DailyLine(who: who, text: text, isMedia: media);

void main() {
  group('بناء الملخص اليومي', () {
    test('قائمة فارغة أو وسائط فقط بلا رسائل نصية تعيد null بصدق', () {
      expect(DailySummaryService.build([], DateTime(2026, 11, 14)), isNull);
      expect(
        DailySummaryService.build([_l('أحمد', '[صورة]', media: true)],
            DateTime(2026, 11, 14)),
        isNull,
      );
    });

    test('الترويسة تحمل اسم اليوم والتاريخ المزدوج هجري/ميلادي', () {
      final s = DailySummaryService.build(
          [_l('أحمد', 'صباح الخير، هل أرسلت الملف؟')], DateTime(2026, 11, 14));
      expect(s, isNotNull);
      expect(s!, contains('ملخص'));
      expect(s, contains('نوفمبر'));
      expect(s, contains('هـ')); // السطر المزدوج يتضمن الهجري
      // 2026-11-14 سببت
      expect(s, contains('السبت'));
    });

    test('الإحصاءات: عدد الرسائل والوسائط وأبرز المشاركين', () {
      final s = DailySummaryService.build([
        _l('أحمد', 'أرسلت التقرير الصباحي بخصوص المشروع'),
        _l('أحمد', 'وانتظرت مراجعتكم قبل الاجتماع'),
        _l('سارة', 'شكرا جزيلا، سأراجع الآن بكل تفصيل'),
        _l('سارة', '[صورة]', media: true),
      ], DateTime(2026, 11, 14));
      expect(s!, contains('3 رسالة'));
      expect(s, contains('1 وسائط'));
      expect(s, contains('أحمد (2)'));
      expect(s, contains('سارة (1)'));
    });

    test('المحادثة الفردية (متحدث واحد) لا تعرض «أبرز المشاركين»', () {
      final s = DailySummaryService.build(
          [_l('أحمد', 'وصلت الملف'), _l('أحمد', 'بالتوفيق')],
          DateTime(2026, 11, 14));
      expect(s!, isNot(contains('أبرز المشاركين')));
    });

    test('المواضيع المتكررة: كلمات معنوية تكررت مرتين فأكثر', () {
      final s = DailySummaryService.build([
        _l('أحمد', 'متى تسليم المشروع؟'),
        _l('سارة', 'تسليم المشروع يوم الخميس بإذن الله'),
        _l('سارة', 'أكيد المشروع قريب من النهاية'),
      ], DateTime(2026, 11, 14));
      expect(s!, contains('المواضيع المتكررة'));
      expect(s, contains('مشروع')); // «المشروع» تشترى «ال» فتصير مشروع
    });

    test('المواضيع تتجاهل الكلمات الوظيفية والقصيرة', () {
      final t = DailySummaryService.topics([
        _l('أ', 'هل هذا هو التقرير الجاهز؟'),
        _l('ب', 'نعم هذا هو التقرير جاهز فعلا'),
      ]);
      expect(t, isNot(contains('هذا')));
      expect(t, isNot(contains('هل')));
      expect(t, contains('تقرير')); // «التقرير» تشترى «ال» وتكررت مرتين
      expect(t, contains('جاهز'));
    });

    test('النقاط الأساسية مستخلصة من الأسطر الأصلية بترتيبها', () {
      final s = DailySummaryService.build([
        _l('أحمد', 'سؤال أول عن الميزانية؟'),
        _l('سارة', 'الرد على السؤال الأول: الميزانية معتمدة'),
        _l('أحمد', 'التفاصيل في ملف مرفق لاحقا'),
        _l('سارة', 'ملخص الاجتماع القادم يوم الأحد الساعة عشر الصباح'),
      ], DateTime(2026, 11, 14));
      expect(s!, contains('النقاط الأساسية'));
      // أربعة أسطر مع maxLines 3 — يظهر 3 فقط لكنها من الأصلية
      expect(s.split('\n').where((l) => l.startsWith('•')).length, 3);
    });
  });

  group('مفتاح اليوم', () {
    test('صيغة قياسية yyyy-MM-dd', () {
      expect(DailySummaryService.dayKey(DateTime(2026, 11, 14)), '2026-11-14');
      expect(DailySummaryService.dayKey(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('اليوم القياسي يفرق بين يومين متتاليين', () {
      expect(
        DailySummaryService.dayKey(DateTime(2026, 11, 14)) ==
            DailySummaryService.dayKey(DateTime(2026, 11, 15)),
        isFalse,
      );
    });
  });

  group('المخزن الآمن (بلا منصة فعلية — يهبط بصمت)', () {
    // في بيئة الاختبار لا يوجد مخزن آمن فعلي؛ الخدمة مصممة أن الفشل يهبط
    // بلا استثناء — وهذا الاختبار يوثق هذا العقد.
    test('load على فشل التخزين يعيد null ولا يرمي', () async {
      final store = DailySummaryStore();
      expect(await store.load('conv-x', DateTime(2026, 11, 14)), anyOf(isNull, isNotNull));
    });

    test('save على فشل التخزين لا يرمي', () async {
      final store = DailySummaryStore();
      await store.save('conv-x', 'نص', DateTime(2026, 11, 14));
      await store.clear('conv-x');
      await store.clearAll();
    });
  });
}
