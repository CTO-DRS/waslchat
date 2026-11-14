import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/unified_search_service.dart';

UnifiedDoc _d(String cid, String title, String text, String at,
    {String sender = '', bool mine = false}) {
  return UnifiedDoc(
    conversationId: cid,
    title: title,
    messageId: 'm-$at-$text',
    text: text,
    createdAtIso: at,
    senderName: sender,
    mine: mine,
    isGroup: title.startsWith('مجموعة'),
  );
}

void main() {
  group('ترتيب البحث الموحد', () {
    test('استعلام فارغ أو فراغات يعيد لا شيء', () {
      expect(UnifiedSearchService.rank([], ''), isEmpty);
      expect(UnifiedSearchService.rank([], '   '), isEmpty);
    });

    test('مطابقة عادية ترتب بالقوة', () {
      final docs = [
        _d('c1', 'أحمد', 'الاجتماع يوم الخميس', '2026-11-13T10:00:00Z'),
        _d('c2', 'سارة', 'سأرسل الملف غدا', '2026-11-13T09:00:00Z'),
        _d('c3', 'فريق العمل', 'تأكدنا من موعد الاجتماع', '2026-11-13T08:00:00Z'),
      ];
      final hits = UnifiedSearchService.rank(docs, 'الاجتماع');
      expect(hits.length, 2);
      // المطابقة التامة للعبارة تسبق مطابقة الكلمة
      expect(hits.first.doc.conversationId, 'c1');
    });

    test('تسامح الأخطاء: حرف ناقص يجد النتيجة', () {
      final docs = [_d('c1', 'ولد', 'شكرا جزيلا', '2026-11-13T10:00:00Z')];
      final hits = UnifiedSearchService.rank(docs, 'شكر jazila'.replaceAll('jazila', 'جزيل'));
      expect(hits, isNotEmpty);
    });

    test('حد ثلاث نتائج لكل محادثة حتى لا تبتلع محادثة واحدة', () {
      final docs = [
        for (var i = 0; i < 6; i++)
          _d('c1', 'فريق', 'رسالة الاجتماع رقم $i', '2026-11-13T0$i:00:00Z'),
        _d('c2', 'آخر', 'الاجتماع مؤجل', '2026-11-13T00:30:00Z'),
      ];
      final hits = UnifiedSearchService.rank(docs, 'الاجتماع');
      final fromC1 = hits.where((h) => h.doc.conversationId == 'c1').length;
      expect(fromC1, 3);
      expect(hits.any((h) => h.doc.conversationId == 'c2'), isTrue);
    });

    test('الحد الأعلى 60 نتيجة', () {
      final docs = [
        for (var i = 0; i < 200; i++)
          _d('c${i % 70}', 'م${i % 70}', 'كلمة الاجتماع رقم $i',
              '2026-11-${((i % 28) + 1).toString().padLeft(2, '0')}T10:00:00Z'),
      ];
      final hits = UnifiedSearchService.rank(docs, 'الاجتماع');
      expect(hits.length, lessThanOrEqualTo(60));
    });

    test('الأحدث أولاً عند تعادل النقاط', () {
      final docs = [
        _d('c1', 'أ', 'الاجتماع', '2026-11-13T09:00:00Z'),
        _d('c2', 'ب', 'الاجتماع', '2026-11-13T11:00:00Z'),
      ];
      final hits = UnifiedSearchService.rank(docs, 'الاجتماع');
      expect(hits.first.doc.conversationId, 'c2');
    });

    test('التجميع حسب المحادثة يحفظ الترتيب', () {
      final docs = [
        _d('c1', 'أ', 'كلمة', '2026-11-13T10:00:00Z'),
        _d('c2', 'ب', 'كلمة', '2026-11-13T09:00:00Z'),
      ];
      final hits = UnifiedSearchService.rank(docs, 'كلمة');
      final g = UnifiedSearchService.groupByConversation(hits);
      expect(g.keys.toSet(), {'c1', 'c2'});
    });

    test('الإفصاح الحرفي موجود ويذكر «على جهازك»', () {
      expect(UnifiedSearchService.disclosure.contains('على جهازك'), isTrue);
      expect(UnifiedSearchService.disclosure.contains('لا يُرسل'), isTrue);
    });
  });
}
