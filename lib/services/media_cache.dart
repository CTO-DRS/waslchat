import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// كاش وسائط محلي (0.4.8 — بند المرحلة 1).
///
/// يخزّن النسخة المفكّكة من الفيديو داخل مجلد كاش التطبيق الخاص
/// (لا يراه أي تطبيق آخر) كي يعمل «التنزيل التلقائي» والفتح الفوري
/// بلا تنزيل ثاني.
///
/// الشفافية:
/// - الملف المخزّن **مفكّوك التشفير** على الجهاز — ضرورة تقنية للتشغيل،
///   مثل واتساب، داخل صندوق رملي خاص بالتطبيق، ويُحذفه النظام عند
///   ضغط التخزين، والمستخدم يمسحه كله من شاشة الإعدادات.
/// - المفتاح مسار التخزين المشفّر (لا الاسم ولا المحتوى) — الاسم على
///   القرص مجزأ SHA-256 لا يكشف شيء.
/// - رسائل «عرض مرة واحدة» لا تدخل هذا الكاش أبداً — تُفتح وتُحذف.
class MediaCache {
  MediaCache._();

  static const String dirName = 'wasl_media';

  static final Sha256 _sha256 = Sha256();

  /// مسار ملف الكاش لمفتاح (مسار التخزين المشفّر)
  static Future<File> fileFor(String key) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/$dirName');
    await dir.create(recursive: true);
    final h = await _sha256.hash(utf8.encode(key));
    final hex = h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return File('${dir.path}/$hex.bin');
  }

  /// النسخة المخزّنة إن وجدت
  static Future<File?> get(String key) async {
    try {
      final f = await fileFor(key);
      if (await f.exists()) return f;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// تخزين النسخة (يكتب فوق القديمة بأمان)
  static Future<File?> put(String key, Uint8List bytes) async {
    try {
      final f = await fileFor(key);
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// حذف كاش وسيط بعينه (مثلاً رسالة حُذفت)
  static Future<void> remove(String key) async {
    try {
      final f = await fileFor(key);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// مسح الكاش كله — زر «مسح الوسائط المؤقتة» في الإعدادات
  static Future<int> clear() async {
    var n = 0;
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/$dirName');
      if (!await dir.exists()) return 0;
      await for (final e in dir.list()) {
        if (e is File) {
          await e.delete();
          n++;
        }
      }
    } catch (_) {}
    return n;
  }
}
