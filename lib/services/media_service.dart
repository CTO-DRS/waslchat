import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'lru_cache.dart';

/// رفع الوسائط إلى Supabase Storage وجلب روابط مؤقتة آمنة
class MediaService {
  static const bucket = 'chat-media';

  static Future<String> upload({
    required String conversationId,
    required Uint8List bytes,
    required String ext,
    required String contentType,
  }) async {
    final uid = supabase.auth.currentUser!.id.substring(0, 8);
    final path = '$conversationId/${DateTime.now().millisecondsSinceEpoch}_$uid.$ext';
    await supabase.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  }

  /// رابط صالح لساعة، مع ذاكرة مؤقتة LRU بسقف معلن يضبطه صاحبها (1.1.0)
  /// — الأحدث استعمالاً يبقى والأقدم يُنظف ذاتياً بلا نمو بلا سقف
  static Future<String> signedUrl(String path) async {
    final hit = MediaCacheService.lru.get(path);
    if (hit != null && DateTime.now().isBefore(hit.$2)) return hit.$1;
    final url = await supabase.storage.from(bucket).createSignedUrl(path, 3600);
    MediaCacheService.lru.put(path, (url, DateTime.now().add(const Duration(minutes: 50))));
    return url;
  }

  /// تنزيل بايتات ملف مباشرة (تخزين خاص — RLS تتحقق من العضوية)
  static Future<Uint8List> download(String path) async {
    return supabase.storage.from(bucket).download(path);
  }

  /// حذف ملف (لصاحبه فقط — سياسة التخزين) — صامتة عند الفشل
  static Future<void> remove(String path) async {
    try {
      await supabase.storage.from(bucket).remove([path]);
      MediaCacheService.lru.remove(path);
    } catch (_) {}
  }
}

/// ذاكرة روابط الوسائط المؤقتة — السقف معلن يعرضه صاحبها ويعدّله من
/// ورقة المؤشرات، والأصل على الخادم لا يمسه المسح أبداً (ما نخزنه روابط
/// موقعة مؤقتة فقط، فمسحها لا يمس بايتاً واحداً من وسائطك).
class MediaCacheService {
  MediaCacheService._();

  static const _key = 'media_cache_cap_v1';
  static const _storage = FlutterSecureStorage();

  /// السقوف المسموحة — ثلاثة أضابط واضحة بلا تخمين
  static const allowedCaps = [100, 300, 1000];
  static const defaultCap = 300;

  /// روابط الوسائط — الأحدث استعمالاً يبقى
  static LruCache<String, (String, DateTime)> lru = LruCache(defaultCap);

  /// للواجهة: يتغير عند كل ضبط سقف أو مسح
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final raw = await _storage.read(key: _key);
      final v = int.tryParse(raw ?? '');
      if (v != null && allowedCaps.contains(v)) {
        lru = lru.copyWithCapacity(v);
      }
    } catch (_) {}
    version.value++;
  }

  /// ضبط السقف: الأحدث استعمالاً يرحَّل كما هو وما زاد عن السقف يُخلى —
  /// ولا شيء يُلمس على الخادم إطلاقاً
  static Future<void> setCap(int cap) async {
    if (!allowedCaps.contains(cap)) return;
    lru = lru.copyWithCapacity(cap);
    try {
      await _storage.write(key: _key, value: '$cap');
    } catch (_) {}
    version.value++;
  }

  /// مسح الذاكرة المؤقتة محلياً حصراً — روابط مؤقتة لا أصول
  static void clear() {
    lru.clear();
    lru.hits = 0;
    lru.misses = 0;
    lru.evictions = 0;
    version.value++;
  }

  static int get cap => lru.capacity;
}
