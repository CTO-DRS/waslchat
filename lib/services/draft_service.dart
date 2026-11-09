import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// المسودات المحلية لكل محادثة (بند المرحلة 1: الرسائل المجدولة والمسودات).
/// تُحفظ على الجهاز فقط (SharedPreferences) ولا تُرفع للخادم إطلاقاً،
/// وتظهر كمعاينة «مسودة: …» في قائمة المحادثات.
class DraftService {
  static final drafts = ValueNotifier<Map<String, String>>({});
  static const _prefix = 'draft_';
  static bool _loaded = false;

  /// يقرأ كل المسودات المحفوظة مرة واحدة (للعرض في قائمة المحادثات)
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final map = <String, String>{};
      for (final k in sp.getKeys()) {
        if (k.startsWith(_prefix)) {
          final v = sp.getString(k);
          if (v != null && v.isNotEmpty) map[k.substring(_prefix.length)] = v;
        }
      }
      drafts.value = map;
      _loaded = true;
    } catch (_) {}
  }

  /// مسودة محادثة معينة أو null إن لا يوجد
  static String? get(String? convId) {
    if (convId == null) return null;
    final v = drafts.value[convId];
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  /// يحفظ محلياً؛ النص الفارغ يحذف المسودة
  static Future<void> save(String convId, String text) async {
    final t = text.trim();
    final map = Map<String, String>.from(drafts.value);
    if (t.isEmpty) {
      if (!map.containsKey(convId)) return; // لا تغيير ولا كتابة
      map.remove(convId);
    } else {
      map[convId] = text;
    }
    drafts.value = map;
    try {
      final sp = await SharedPreferences.getInstance();
      if (t.isEmpty) {
        await sp.remove('$_prefix$convId');
      } else {
        await sp.setString('$_prefix$convId', text);
      }
    } catch (_) {}
  }

  static Future<void> clear(String convId) => save(convId, '');

  /// يُستدعى عند تسجيل الخروج
  static void reset() {
    _loaded = false;
    drafts.value = {};
  }
}
