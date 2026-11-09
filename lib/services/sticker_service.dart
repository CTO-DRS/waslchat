import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// الملصقات (0.4.9 — المرحلة 1): حزم مدمجة داخل التطبيق بلا خادم
/// بلا كتالوج بلا إحصاء استخدام. بايتات الملصق تُرفع كوسيط عادي
/// داخل التشفير مثل أي صورة — فالملقّى طرفه الآخر لا يحتاج الحزمة.
class StickerService {
  StickerService._();

  static const packBasics = 'basics';
  static const packBasicsTitle = 'أساسيات وصل';

  /// الملصقات المتحركة (gif) — الباقي webp ساكن
  static const _gifIds = {'heart_pulse', 'star_spin'};

  /// ترتيب العرض في الحزمة
  static const basicsOrder = [
    'smile', 'laugh', 'wink', 'heart_eyes', 'cry', 'angry', 'cool', 'sleep',
    'think', 'thumbsup', 'heart', 'fire', 'star', 'wave', 'party',
    'heart_pulse', 'star_spin',
  ];

  static const maxRecent = 16;
  static const _recentKey = 'sticker_recent';

  /// مفاتيح صارمة: أحرف صغيرة/أرقام/شرطة/شرطة سفلية حتى 32 — يمنع
  /// أي تلاعب بمسار الأصول أو بمدخل meta الواصل من الطرف الآخر
  static final _keyRe = RegExp(r'^[a-z0-9_-]{1,32}$');

  static bool validKey(String s) => _keyRe.hasMatch(s);

  static String extOf(String id) => _gifIds.contains(id) ? 'gif' : 'webp';

  static bool animatedOf(String id) => _gifIds.contains(id);

  /// مسار الأصل المحلي — يرمي ArgumentError على أي مفتاح غير صالح
  static String assetPath(String pack, String id) {
    if (!validKey(pack) || !validKey(id)) {
      throw ArgumentError('مفتاح ملصق غير صالح');
    }
    return 'assets/stickers/$pack/$id.${extOf(id)}';
  }

  /// meta الرسالة: صغير ثابت البنية — يُشفَّر مع نص الرسالة فلا يرى
  /// الخادم أي شيء عنه (بنفس مسار meta الفيديو في 0.4.8)
  static String metaJson(String pack, String id) {
    if (!validKey(pack) || !validKey(id)) {
      throw ArgumentError('مفتاح ملصق غير صالح');
    }
    return jsonEncode({
      'pack': pack,
      'id': id,
      'ext': extOf(id),
      'animated': animatedOf(id),
    });
  }

  /// فك meta الواصل — يقبل نصاً خاماً أو خريطة مفكوكة مسبقاً.
  /// يعيد null على أي خلل (فقاعة بديلة صادقة).
  static (String pack, String id)? decodeMeta(Object? raw) {
    Object? m = raw;
    if (raw is String && raw.isNotEmpty) {
      if (raw.length > 300) return null;
      try {
        m = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (m is! Map) return null;
    final pack = m['pack'], id = m['id'];
    if (pack is! String || id is! String) return null;
    // حقل ext إن وجد يجب أن يطابق امتدادنا المعروف للحزمة المدمجة
    final ext = m['ext'];
    if (ext is String && ext != extOf(id)) return null;
    if (!validKey(pack) || !validKey(id)) return null;
    if (!basicsOrder.contains(id) || pack != packBasics) return null;
    return (pack, id);
  }

  /// آخر المستخدمة — تخزين محلي فقط، لا شيء يغادر الجهاز
  static Future<List<(String, String)>> recent() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_recentKey) ?? const [];
    final out = <(String, String)>[];
    for (final e in raw) {
      final parts = e.split('|');
      if (parts.length != 2) continue;
      final (p, i) = (parts[0], parts[1]);
      if (!validKey(p) || !validKey(i) || !basicsOrder.contains(i)) continue;
      if (!out.any((x) => x.$1 == p && x.$2 == i)) out.add((p, i));
    }
    return out.take(maxRecent).toList();
  }

  /// تذكّر استخدام: إلى المقدمة، بلا تكرار، بسقف 16، إدخالات غير صالحة تُهمل
  static Future<void> remember(String pack, String id) async {
    if (!validKey(pack) || !validKey(id) || !basicsOrder.contains(id)) return;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_recentKey) ?? const [];
    final key = '$pack|$id';
    final next = [key, ...raw.where((e) => e != key)].take(maxRecent).toList();
    await sp.setStringList(_recentKey, next);
  }

  static Future<void> clearRecent() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_recentKey);
  }
}
