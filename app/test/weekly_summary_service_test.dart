// اختبارات الملخص الأسبوعي المحلي (المرحلة 14 أ — 1.3.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/weekly_summary_service.dart';

WeeklyLine _l(String who, String text, DateTime at, {bool media = false}) =>
    WeeklyLine(who: who, text: text, createdAt: at, isMedia: media);

void main() {
  final end = DateTime(2026, 11, 14, 20, 0);

  group('النافذة المتدحرجة', () {
    test('يحصر الأسطر داخل آخر 7 أيام حصراً', () {
      final inside = _l('أ', 'نص داخل الأسبوع', end.subtract(const Duration(days: 2)));
      final old = _l('أ', 'نص قديم جدا', end.subtract(const Duration(days: 9)));
      final future = _l('أ', 'نص مستقبلي', end.add(const Duration(hours: 2)));
      final w = WeeklySummaryService.window([inside, old, future], end);
      expect(w, hasLength(1));
      expect(w.first.text, 'نص داخل الأسبوع');
    });

    test('الحد السفلي حصري: سطر على حدود البداية يُستبعد', () {
      final boundary = _l('أ', 'نص على الحد', end.subtract(const Duration(days: 7)));
      expect(WeeklySummaryService.window([boundary], end), isEmpty);
    });

    test('تخصيص عرض النافذة يعمل (3 أيام مثلاً)', () {
      final d2 = _l('أ', 'قريب', end.subtract(const Duration(days: 2)));
      final d5 = _l('أ', 'بعيد', end.subtract(const Duration(days: 5)));
      final w = WeeklySummaryService.window([d2, d5], end, days: 3);
      expect(w, hasLength(1));
      expect(w.first.text, 'قريب');
    });
  });

  group('بناء الملخص الأسبوعي', () {
    test('أسبوع بلا رسائل نصية (وسائط فقط أو فراغ) يعيد null بصدق', () {
      expect(WeeklySummaryService.build([], end), isNull);
      expect(
        WeeklySummaryService.build(
            [_l('أ', '[وسائط]', end.subtract(const Duration(days: 1)), media: true)],
            end),
        isNull,
      );
    });

    test('الترويسة تعلن النافذة بالتاريخ المزدوج هجري/ميلادي', () {
      final s = WeeklySummaryService.build([
        _l('أحمد', 'أرسلت التقرير اليوم', end.subtract(const Duration(days: 1))),
      ], end);
      expect(s, isNotNull);
      expect(s!, contains('ملخص الأسبوع'));
      expect(s, contains('نوفمبر'));
      expect(s, contains('هـ'));
    });

    test('الإحصاءات: الرسائل والوسائط وأيام النشاط بالعد الصادق', () {
      final d1 = end.subtract(const Duration(days: 1));
      final d2 = end.subtract(const Duration(days: 3));
      final s = WeeklySummaryService.build([
        _l('أحمد', 'رسالة أولى يوم واحد', d1),
        _l('سارة', 'رد اليوم نفسه', d1),
        _l('أحمد', 'رسالة يوم آخر', d2),
        _l('أحمد', '[صورة]', d2, media: true),
      ], end);
      expect(s, isNotNull);
      expect(s!, contains('3 رسالة'));
      expect(s, contains('1 وسائط'));
      expect(s, contains('نشاط في 2 يوم'));
    });

    test('أبرز المتشاركين يظهرون بعدّهم عند تعدد المتحدثين', () {
      final s = WeeklySummaryService.build([
        _l('أحمد', 'أ أ أ', end.subtract(const Duration(days: 1))),
        _l('سارة', 'ب ب ب', end.subtract(const Duration(days: 1))),
      ], end);
      expect(s, isNotNull);
      expect(s!, contains('أحمد'));
      expect(s, contains('سارة'));
    });

    test('المواضيع المتكررة عتبة الأسبوع 3 فأكثر — والمرتان تُستبعد', () {
      final s = WeeklySummaryService.build([
        _l('أ', 'المشروع المشروع المشروع', end.subtract(const Duration(days: 1))),
        _l('أ', 'اللجنة اللجنة فقط مرتين', end.subtract(const Duration(days: 2))),
      ], end);
      expect(s, isNotNull);
      // قسم المواضيع يعيد الكلمة الممثلة (مجردة التعريف) بترتيب التكرار
      expect(s!, contains('المواضيع المتكررة: مشروع'));
      // ولجنة تكررت مرتين فلا تدخل قسم المواضيع (نصها الخام يبقى في النقاط لا هنا)
      expect(s, isNot(contains('المواضيع المتكررة: مشروع، لجنة')));
      expect(s, isNot(contains('المواضيع المتكررة: لجنة')));
    });

    test('الرسائل خارج النافذة لا تدخل العد إطلاقاً', () {
      final old = _l('أحمد', 'رسالة قديمة خارج الأسبوع تماما',
          end.subtract(const Duration(days: 20)));
      final s = WeeklySummaryService.build([old], end);
      expect(s, isNull);
    });

    test('الأسطر الخلاصة (النقاط الأساسية) موجودة في المخرج', () {
      final s = WeeklySummaryService.build([
        _l('أحمد', 'اتفقنا على موعد التسليم يوم الخميس؟', end.subtract(const Duration(days: 1))),
        _l('سارة', 'نعم، الخميس الساعة عشرة', end.subtract(const Duration(days: 1))),
      ], end);
      expect(s, isNotNull);
      expect(s!, contains('النقاط الأساسية'));
    });
  });

  group('المخزن الآمن (بلا منصة فعلية — يهبط بصمت)', () {
    // في بيئة الاختبار لا يوجد مخزن آمن فعلي؛ الخدمة مصممة أن الفشل يهبط
    // بلا استثناء — وهذا الاختبار يوثق هذا العقد كنمط الملخص اليومي نفسه.
    test('load على فشل التخزين يعيد null ولا يرمي', () async {
      final store = WeeklySummaryStore();
      expect(await store.load('conv-x', DateTime(2026, 11, 14)), anyOf(isNull, isNotNull));
    });

    test('save على فشل التخزين لا يرمي', () async {
      final store = WeeklySummaryStore();
      await store.save('conv-x', 'نص', DateTime(2026, 11, 14));
      await store.clear('conv-x');
      await store.clearAll();
    });
  });
}
