// اختبارات البحث الدلالي المتجهي المحلي (المرحلة 9 أ — 0.22.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/semantic_search_service.dart';
import 'package:wasl_chat/services/smart_search_service.dart';

SemanticDoc _d(String cid, String who, String text, String at) =>
    SemanticDoc(conversationId: cid, text: text, createdAtIso: at);

void main() {
  group('المتجهات والتشابه', () {
    test('متجهة نص فارغ أو كلمات وظيفية فارغة', () {
      expect(SemanticSearchService.vector(''), isEmpty);
      expect(SemanticSearchService.vector('في من على'), isEmpty);
    });

    test('التطبيع العربي في الرموز: همزات وتاء مربوطة متكافئة', () {
      final a = SemanticSearchService.vector('أحتاجُ ملفَّ المشروع');
      final b = SemanticSearchService.vector('احتاج ملفه المشروعه');
      // «ملف» و«ملفه» ليستا نفس الكلمة لكن «احتاج» و«المشروع» مشتركتان
      expect(SemanticSearchService.cosine(a, b), greaterThan(0));
      expect(
        SemanticSearchService.vector('أحمد').keys,
        containsAll(['احمد']),
      );
    });

    test('التشابه الذاتي = 1 والمعايرة تجعل المتجهات وحدة الطول', () {
      final v = SemanticSearchService.vector('سأرسل الملف غدا إن شاء الله الملف');
      var norm = 0.0;
      for (final w in v.values) {
        norm += w * w;
      }
      expect(norm, closeTo(1.0, 1e-9));
      expect(SemanticSearchService.cosine(v, v), closeTo(1.0, 1e-9));
    });

    test('تشابه نصين لا يشاركان كلمة = صفر', () {
      final a = SemanticSearchService.vector('شكرا جزيلا');
      final b = SemanticSearchService.vector('الطقس ممطر اليوم');
      expect(SemanticSearchService.cosine(a, b), 0);
    });
  });

  group('توسيع الاستعلام بالمرادفات', () {
    test('expansionsFor يعيد مجموعة المرادف', () {
      final ex = SmartSearchService.expansionsFor('ميعاد');
      expect(ex, contains('اجتماع'));
      expect(ex, contains('ميعاد')); // الكلمة نفسها داخل مجموعتها
    });

    test('متجهة الاستعلام تشمل المرادفات بوزن أخف', () {
      final v = SemanticSearchService.queryVector('ميعاد');
      expect(v, contains('اجتماع'));
      expect(v['اجتماع']!, lessThan(v['ميعاد']!));
    });

    test('استعلام فارغ متجهة فارغة', () {
      expect(SemanticSearchService.queryVector('   في   '), isEmpty);
    });
  });

  group('ترتيب المحادثات ذات الصلة', () {
    test('البحث الدلالي يجد «متى اللقاء» من «موعد الاجتماع» بلا كلمة مشتركة معجمياً', () {
      final docs = [
        _d('c1', 'سارة', 'متى اللقاء يا أحمد؟', '2026-11-13T10:00:00Z'),
        _d('c2', 'أم سالم', 'وصلت وصفة الكيك', '2026-11-13T09:00:00Z'),
      ];
      final hits = SemanticSearchService.rankConversations(docs, 'موعد الاجتماع');
      expect(hits, isNotEmpty);
      expect(hits.first.conversationId, 'c1');
    });

    test('المرادف يصل: «ميعاد» يجد «اجتماع»', () {
      final docs = [_d('c1', 'فريق', 'الاجتماع الساعة خمس', '2026-11-13T10:00:00Z')];
      final hits = SemanticSearchService.rankConversations(docs, 'ميعاد');
      expect(hits, isNotEmpty);
      expect(hits.first.conversationId, 'c1');
    });

    test('لا نتائج لاستعلام بلا أي قربة (عتبة الدنيا تحمي)', () {
      final docs = [_d('c1', 'ولد', 'شكرا جزيلا على المساعدة', '2026-11-13T10:00:00Z')];
      final hits =
          SemanticSearchService.rankConversations(docs, 'طقس الغد ممطر');
      expect(hits, isEmpty);
    });

    test('أفضل رسالة في المحادثة هي الأعلى تشابهاً للمعاينة', () {
      final docs = [
        _d('c1', 'ولد', 'كيف حالك اليوم؟', '2026-11-13T08:00:00Z'),
        _d('c1', 'ولد', 'متى موعد التسليم؟', '2026-11-13T10:00:00Z'),
      ];
      final hits = SemanticSearchService.rankConversations(docs, 'التسليم');
      expect(hits.first.bestText, 'متى موعد التسليم؟');
      expect(hits.first.bestAtIso, '2026-11-13T10:00:00Z');
    });

    test('الحد top وترتيب التعادل بالحداثة', () {
      final docs = [
        _d('c1', 'أ', 'الاجتماع الساعة خمس', '2026-11-13T08:00:00Z'),
        _d('c2', 'ب', 'الاجتماع الساعة خمس', '2026-11-13T10:00:00Z'),
        _d('c3', 'ج', 'الاجتماع الساعة خمس', '2026-11-13T09:00:00Z'),
      ];
      final hits = SemanticSearchService.rankConversations(docs, 'الاجتماع', top: 2);
      expect(hits.length, 2);
      // نفس النص ونقاط التشابه نفسها — الأحدث أولاً
      expect(hits.first.conversationId, 'c2');
    });

    test('إفصاح الدلالة نص صادق يذكر الجهاز', () {
      expect(SemanticSearchService.disclosure, contains('جهازك'));
      expect(SemanticSearchService.disclosure, contains('بلا شبكة'));
    });
  });
}
