import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/lru_cache.dart';

/// اختبارات نقية لذاكرة LRU (المرحلة 13 أ — 1.1.0) — بلا شبكة ولا تخزين.
/// العقد: الأحدث استعمالاً يبقى والأقدم يُنظف ذاتياً عند السقف، والعدّادات
/// صادقة، والمسح لا يمس أصولاً (لا شيء يخرج من هذه البنية أصلاً).
void main() {
  group('الإدخال والوصول والعدّ', () {
    test('الوصول الناجح يعيد القيمة ويرفعها لأحدث عنصر', () {
      final c = LruCache<String, int>(3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      expect(c.get('a'), 1); // a صارت الأحدث
      expect(c.get('b'), 2);
      expect(c.length, 3);
    });

    test('الإخفاق يُعدّ ولا يضيف شيئاً', () {
      final c = LruCache<String, int>(3)..put('a', 1);
      expect(c.get('x'), isNull);
      expect(c.misses, 1);
      expect(c.hits, 0);
      expect(c.length, 1);
    });

    test('الإدخال فوق مفتاح موجود يعدّل ولا يخلي ولا يزيد الطول', () {
      final c = LruCache<String, int>(3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('a', 9);
      expect(c.get('a'), 9);
      expect(c.length, 2);
      expect(c.evictions, 0);
    });
  });

  group('الإخلاء بالسقف — الأقدم استعمالاً يرحل أولاً', () {
    test('فوق السقف: الأقدم استعمالاً يُخلى بالترتيب', () {
      final c = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3); // a الأقدم تُخلى
      expect(c.containsKey('a'), isFalse);
      expect(c.containsKey('b'), isTrue);
      expect(c.containsKey('c'), isTrue);
      expect(c.evictions, 1);
    });

    test('الوصول يغيّر مَن هو الأقدم — a جرى لمسها فبقيت وb رحلت', () {
      final c = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('b', 2);
      c.get('a'); // a صارت الأحدث
      c.put('c', 3); // b الأقدم تُخلى
      expect(c.containsKey('a'), isTrue);
      expect(c.containsKey('b'), isFalse);
    });

    test('سقف صفر أو سالب يُعامل واحداً — لا ذاكرة بلا سقف أبداً', () {
      final c = LruCache<String, int>(0)..put('a', 1)..put('b', 2);
      expect(c.capacity, 1);
      expect(c.length, 1);
      expect(c.containsKey('b'), isTrue);
    });
  });

  group('النظرة الصامتة والنسخ والمسح', () {
    test('peek يعيد القيمة بلا عدّ ولا إعادة ترتيب', () {
      final c = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('b', 2);
      expect(c.peek('a'), 1);
      expect(c.hits, 0); // لا عدّ
      expect(c.misses, 0);
      c.put('c', 3); // a ما زالت الأقدم رغم اللمسة الصامتة
      expect(c.containsKey('a'), isFalse);
    });

    test('copyWithCapacity يرحّل الأحدث ويحفظ إحصاء التاريخ', () {
      final c = LruCache<String, int>(3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      c.get('a'); // a صارت الأحدث — الترتيب الآن b ثم c ثم a
      final small = c.copyWithCapacity(2);
      expect(small.capacity, 2);
      expect(small.length, 2);
      expect(small.containsKey('a'), isTrue); // الأحدث بقيت
      expect(small.containsKey('c'), isTrue); // والثانية بعدها
      expect(small.containsKey('b'), isFalse); // الأقدم رحلت
      expect(small.hits, 1); // التاريخ مُرحَّل
      expect(small.evictions, greaterThanOrEqualTo(1));
    });

    test('clear يفرّغ كل شيء — ولا يمس أي أصل إطلاقاً (بنية محلية حصراً)', () {
      final c = LruCache<String, int>(2)..put('a', 1)..put('b', 2);
      c.clear();
      expect(c.isEmpty, isTrue);
      expect(c.length, 0);
    });
  });
}
