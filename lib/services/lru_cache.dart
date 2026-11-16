/// ذاكرة مؤقتة LRU نقية (المرحلة 13 أ — 1.1.0).
///
/// الأحدث استعمالاً يبقى والأقدم يُنظف ذاتياً عند بلوغ السقف المعلن —
/// بلا شبكة وبلا تخزين: بنية بيانات قابلة للاختبار مباشرة، تُستعمل لذاكرة
/// روابط الوسائط المؤقتة كي لا تنمو بلا سقف في جلسة طويلة. المسح لا يمس
/// الأصل على الخادم أبداً — ما تُخزنه هذه البنية روابط مؤقتة وعناوين فقط.
import 'dart:collection';

class LruCache<K, V> {
  /// سقف العناصر — سقف ≤ 0 يُعامل 1 (لا ذاكرة بلا سقف أبداً)
  LruCache(int capacity) : capacity = capacity <= 0 ? 1 : capacity;

  final int capacity;

  /// ترتيب الإدراج: الأحدث في النهاية (نحرك عند كل وصول ناجح)
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  // عدّادات صادقة للعرض في ورقة المؤشرات
  int hits = 0;
  int misses = 0;
  int evictions = 0;

  int get length => _map.length;
  bool get isEmpty => _map.isEmpty;
  bool get isFull => _map.length >= capacity;

  /// وصول ناجح يعيد القيمة وينقلها لأحدث عنصر — والعدّ يصير هنا حصراً
  V? get(K key) {
    final v = _map.remove(key);
    if (v == null) {
      misses++;
      return null;
    }
    hits++;
    _map[key] = v;
    return v;
  }

  /// إدخال يعدّل الموجود ويرفعه لأحدث، والإضافة فوق السقف تُخلي الأقدم
  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      final oldest = _map.keys.first;
      _map.remove(oldest);
      evictions++;
    }
  }

  /// نظرة بلا عدّ ولا إعادة ترتيب — للفحص الصامت (الحداثة الزمنية مثلاً)
  V? peek(K key) => _map[key];

  bool containsKey(K key) => _map.containsKey(key);

  V? remove(K key) => _map.remove(key);

  void clear() => _map.clear();

  /// نسخ إلى ذاكرة بسقف جديد: الأحدث استعمالاً تبقى والأقدم قد يُخلى
  /// بحسب السقف الجديد — عدّادات الإحصاء تُرحَّل كما هي (تاريخ حقيقي)
  LruCache<K, V> copyWithCapacity(int newCapacity) {
    final c = LruCache<K, V>(newCapacity);
    c._map.addAll(_map);
    while (c._map.length > c.capacity) {
      final oldest = c._map.keys.first;
      c._map.remove(oldest);
      c.evictions++;
    }
    c.hits = hits;
    c.misses = misses;
    c.evictions += evictions;
    return c;
  }
}
