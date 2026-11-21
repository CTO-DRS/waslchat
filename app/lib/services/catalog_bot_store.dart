/// مخزن بوتات الكتالوج المركبة (1.22.0) — الربط الحي يحتاج حالة تثبيت
/// حقيقية: بوتات الكتالوج تُركّب **محلياً على جهاز صاحب الغرفة**
/// (shared_preferences) لأن العدّاء يعمل من جهازه كمسودات يراجعها —
/// لا جدول خادمي ولا صلاحية جديدة، فالقالب نص يجيء من الكتالوج الموثق
/// والخادم لا علاقة له به إطلاقاً.
///
/// العقد الصادق:
/// 1. التثبيت لكل غرفة بحدود الخدمة نفسها: 3 لكل غرفة والتكرار مرفوض —
///    الأسباب مجمعة عبر `CatalogOutcome` النمط القائم.
/// 2. JSON الفاسد يبدأ فارغاً بلا انفجار — التخزين المحلي حصري.
/// 3. المحرك النقي يظل مرجع حدود القوالب؛ هنا تسجيل وحفظ واسترجاع.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bot_catalog_service.dart';

class CatalogBotStore {
  CatalogBotStore._();

  static const String _key = 'wasl_catalog_bots_v1';

  /// كل التثبيتات: conversationId → قائمة البوتات المركبة فيه
  static Future<Map<String, List<InstalledCatalogBot>>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final doc = json.decode(raw) as Map<String, dynamic>;
      return {
        for (final e in doc.entries)
          e.key: [
            for (final b in (e.value as List?) ?? const [])
              if (b is Map<String, dynamic>) _fromJson(b),
          ].where((b) => b.username.isNotEmpty).toList(),
      };
    } catch (_) {
      return {}; // فاسد يبدأ فارغاً بلا انفجار
    }
  }

  /// تثبيت بوت في غرفة — حدود الخدمة نفسها: الحد والتكرار بصياغة مجمعة
  static Future<CatalogOutcome<List<InstalledCatalogBot>>> add(
      String conversationId, InstalledCatalogBot bot) async {
    final all = await loadAll();
    final list = all[conversationId] ?? <InstalledCatalogBot>[];
    if (list.any((b) => b.username == bot.username)) {
      return CatalogOutcome.refused(
          ['البوت مركّب في هذه الغرفة أصلاً — بلا تكرار']);
    }
    if (list.length >= BotCatalogService.maxCatalogBotsPerConversation) {
      return CatalogOutcome.refused([
        'عدد بوتات الكتالوج ${list.length} بلغ الحد '
            '${BotCatalogService.maxCatalogBotsPerConversation}'
      ]);
    }
    list.add(bot);
    await _save(conversationId, list);
    return CatalogOutcome.ok(list);
  }

  /// إزالة تثبيت — true إن أُزيل فعلاً
  static Future<bool> remove(String conversationId, String username) async {
    final all = await loadAll();
    final list = all[conversationId];
    if (list == null) return false;
    final next = [...list]..removeWhere((b) => b.username == username);
    if (next.length == list.length) return false;
    await _save(conversationId, next);
    return true;
  }

  /// بوتات غرفة واحدة — فارغة صادقة إن لم يوجد
  static Future<List<InstalledCatalogBot>> forConversation(
      String conversationId) async {
    final all = await loadAll();
    return all[conversationId] ?? const [];
  }

  static Future<void> _save(
      String conversationId, List<InstalledCatalogBot> bots) async {
    final sp = await SharedPreferences.getInstance();
    final all = await loadAll();
    if (bots.isEmpty) {
      all.remove(conversationId);
    } else {
      all[conversationId] = bots;
    }
    await sp.setString(_key, json.encode({
      for (final e in all.entries)
        e.key: [for (final b in e.value) _toJson(b)],
    }));
  }

  // ————— تسلسل محلي — نفس أشكال الكتالوج الموثق حرفياً —————

  /// قراءة آمنة: القيمة الغريبة (رقم/null) فارغة صادقة لا استثناء مسرب
  static String _s(Object? v) => v is String ? v : '';
  static bool _enabledOf(Object? v) => v is bool ? v : true;

  static Map<String, dynamic> _toJson(InstalledCatalogBot b) => {
        'username': b.username,
        'displayName': b.displayName,
        'enabled': b.enabled,
        'templates': [for (final t in b.templates) _tplToJson(t)],
      };

  static InstalledCatalogBot _fromJson(Map<String, dynamic> j) =>
      InstalledCatalogBot(
        username: _s(j['username']),
        displayName: _s(j['displayName']),
        enabled: _enabledOf(j['enabled']),
        templates: [
          for (final t in (j['templates'] as List?) ?? const [])
            if (t is Map<String, dynamic>) _tplFromJson(t),
        ],
      );

  static Map<String, dynamic> _tplToJson(CatalogTemplate t) =>
      switch (t.type) {
        CatalogTemplateType.welcome => {
            'type': 'welcome',
            'messages': t.messages,
          },
        CatalogTemplateType.attendance => {
            'type': 'attendance',
            'sessions': [
              for (final (s, e) in t.sessions) {'start': s, 'end': e}
            ],
          },
        CatalogTemplateType.suggestions => {
            'type': 'suggestions',
            'prompts': t.prompts,
          },
      };

  static CatalogTemplate _tplFromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String?) ?? '';
    return switch (type) {
      'welcome' => CatalogTemplate.welcome([
          for (final m in (j['messages'] as List?) ?? const [])
            if (m is String) m
        ]),
      'attendance' => CatalogTemplate.attendance([
          for (final s in (j['sessions'] as List?) ?? const [])
            if (s is Map<String, dynamic>)
              (_s(s['start']), _s(s['end']))
        ]),
      'suggestions' => CatalogTemplate.suggestions([
          for (final p in (j['prompts'] as List?) ?? const [])
            if (p is String) p
        ]),
      _ => CatalogTemplate.welcome(const []), // نوع غريب → فارغ فترفض حدوده
    };
  }
}
