// اختبارات البحث الصادق للوسائط (المرحلة 14 ب — 1.4.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/media_gallery_service.dart';
import 'package:wasl_chat/services/media_search_service.dart';

MediaItem _m(String id, String type, String iso,
    {String? name, String? caption, int? size}) {
  return MediaItem(
    messageId: id,
    type: type,
    mediaUrl: 'media/$id',
    createdAtIso: iso,
    mine: true,
    name: name,
    caption: caption,
    sizeBytes: size,
  );
}

void main() {
  final sources = [
    (
      'محادثة العمل',
      [
        _m('2', 'image', '2026-11-16T10:00:00Z', caption: 'صورة الموقع'),
        _m('1', 'file', '2026-11-16T09:00:00Z',
            name: 'تقرير الاجتماع.pdf', size: 2 * 1024 * 1024),
        _m('3', 'video', '2026-11-15T12:00:00Z',
            name: 'اجتماع الخميس.mp4', size: 20 * 1024 * 1024),
        _m('5', 'image', '2026-11-14T08:00:00Z', caption: 'التقرير النهائي'),
        _m('4', 'voice', '2026-11-10T08:00:00Z'),
      ]
    ),
    (
      'العائلة',
      [
        _m('6', 'image', '2026-11-16T11:00:00Z', caption: 'الغداء'),
        _m('7', 'file', '2026-11-13T08:00:00Z',
            name: 'قائمة المشتريات.xlsx', size: 512 * 1024),
      ]
    ),
  ];

  group('النوع والحجم والتاريخ', () {
    test('فلتر النوع يعيد هذا النوع حصراً من كل المصادر', () {
      final r = MediaSearchService.search(
          sources: sources,
          query: const MediaSearchQuery(types: {'image'}));
      expect(r.length, 3);
      expect(r.every((h) => h.item.isImage), isTrue);
    });

    test('مجموعة أنواع فارغة تعني كل الأنواع', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery());
      expect(r.length, 7);
    });

    test('فلتر الحجم يستبعد من لا حجم موثق له بصدق', () {
      // أقل من 1 م.ب: الملف الصغير فقط (الصور والصوت بلا حجم تُستبعد)
      final r = MediaSearchService.search(
          sources: sources,
          query: const MediaSearchQuery(maxSizeBytes: 1024 * 1024));
      expect(r.map((h) => h.item.messageId), ['7']);
      // أكبر من 10 م.ب: الفيديو الكبير فقط
      final r2 = MediaSearchService.search(
          sources: sources,
          query: const MediaSearchQuery(minSizeBytes: 10 * 1024 * 1024));
      expect(r2.map((h) => h.item.messageId), ['3']);
    });

    test('نطاق الحجم المزدوج 1–10 م.ب يلتقط الوسط فقط', () {
      final r = MediaSearchService.search(
          sources: sources,
          query: const MediaSearchQuery(
              minSizeBytes: 1024 * 1024, maxSizeBytes: 10 * 1024 * 1024));
      expect(r.map((h) => h.item.messageId), ['1']);
    });

    test('فلتر التاريخ: آخر 24 ساعة بترتيب المصدر الأصلي الموثق', () {
      final r = MediaSearchService.search(
          sources: sources,
          query: MediaSearchQuery(from: DateTime.utc(2026, 11, 16)));
      // ترتيب المصدر الأصلي: وسائط «محادثة العمل» أولاً (الأحدث فيها) ثم «العائلة»
      expect(r.map((h) => h.item.messageId), ['2', '1', '6']);
    });
  });

  group('النص على الميتاداتا حصراً', () {
    test('الاسم من ميتا الملف يُطابق بعد التطبيع العربي — والمصدر الواحد', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery(text: 'اجتماع'));
      // «الاجتماع» و«اجتماع الخميس» كلاهما يحيوي «اجتماع» كجزء بعد التطبيع
      expect(r.length, 2);
      expect(r.every((h) => h.sourceTitle == 'محادثة العمل'), isTrue);
    });

    test('التشكيل والهمزات لا تكسر المطابقة (الإ إلى ا والفتحة تسقط)', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery(text: 'اَلْإجتماع'));
      // «الاجتماع» مطابقة حصراً — «اجتماع الخميس» بلا «ال» التعريف
      expect(r.length, 1);
      expect(r.first.item.name, 'تقرير الاجتماع.pdf');
    });

    test('التعليق النصي للصورة يُطابق', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery(text: 'الموقع'));
      expect(r.map((h) => h.item.messageId), ['2']);
    });

    test('المصدر الثاني يجيب أيضاً — والنتيجة تحمل عنوان المحادثة المصدر', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery(text: 'المشتريات'));
      expect(r.length, 1);
      expect(r.first.sourceTitle, 'العائلة');
      expect(r.first.item.name, 'قائمة المشتريات.xlsx');
    });

    test('الصدق الأعمق: كلمة ليست في أي ميتاداتا لا تُخترع نتائج لها', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery(text: 'كلمة داخل الصورة نفسها'));
      expect(r, isEmpty);
    });

    test('الجمع: نص + نوع + حجم معاً بشرط «و»', () {
      final r = MediaSearchService.search(
          sources: sources,
          query: const MediaSearchQuery(
              text: 'اجتماع', types: {'file'}, minSizeBytes: 1024 * 1024));
      expect(r.map((h) => h.item.messageId), ['1']);
    });
  });

  group('الصدق البنيوي', () {
    test('sizeKb يحسب من البايتات وnull حين لا حجم', () {
      final hit = MediaSearchHit(
          sourceTitle: 'س', item: _m('9', 'file', '2026-11-16T09:00:00Z', size: 2048));
      expect(hit.sizeKb, 2.0);
      final hit2 = MediaSearchHit(
          sourceTitle: 'س', item: _m('10', 'image', '2026-11-16T09:00:00Z'));
      expect(hit2.sizeKb, isNull);
    });

    test('استعلام فارغ لا يخفي شيئاً ولا يضيف شيئاً', () {
      final r = MediaSearchService.search(
          sources: sources, query: const MediaSearchQuery(text: '   '));
      expect(r.length, 7);
    });

    test('التاريخ الناقص يُستبعد من فلتر التاريخ بلا انفجار', () {
      final bad = [
        (
          'س',
          [_m('x', 'image', 'ليس تاريخاً', caption: 'صورة')]
        ),
      ];
      final r = MediaSearchService.search(
          sources: bad,
          query: MediaSearchQuery(from: DateTime.utc(2026, 11, 16)));
      expect(r, isEmpty);
    });
  });
}
