import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// رفع الوسائط إلى Supabase Storage وجلب روابط مؤقتة آمنة
class MediaService {
  static const bucket = 'chat-media';
  static final Map<String, (String, DateTime)> _cache = {};

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

  /// رابط صالح لساعة، مع ذاكرة مؤقتة تتجدد قبل انتهائه
  static Future<String> signedUrl(String path) async {
    final hit = _cache[path];
    if (hit != null && DateTime.now().isBefore(hit.$2)) return hit.$1;
    final url = await supabase.storage.from(bucket).createSignedUrl(path, 3600);
    _cache[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
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
      _cache.remove(path);
    } catch (_) {}
  }
}
