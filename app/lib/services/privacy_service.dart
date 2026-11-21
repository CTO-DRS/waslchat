import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// الخصوصية الحية (2.1.0): ماذا يشارك تطبيقك عنك لحظياً؟
/// القراءة، الاتصال، الكتابة، والمؤشرات الحيوية — قرارات على جهازك بلا خادم.
/// ملاحظة صادقة: الإيقاف يمنع تطبيقك من المشاركة فعلاً (لا تعليم مقروء، لا
/// تتبع حضور، لا بث كتابة) — وهو أصل السلوك لدى الطرف الآخر.
class PrivacyService {
  PrivacyService._();
  static const _store = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static bool _loaded = false;

  /// مشاركة إشعارات القراءة (تعليم المقروء)
  static final shareReads = ValueNotifier<bool>(true);

  /// مشاركة حالة الاتصال (الحضور اللحظي)
  static final sharePresence = ValueNotifier<bool>(true);

  /// مشاركة حالة «يكتب الآن»
  static final shareTyping = ValueNotifier<bool>(true);

  /// المؤشرات الحيوية (الهالة، شارة العودة، نبض الكتابة) — محلية فقط
  static final liveFx = ValueNotifier<bool>(true);

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    Future<void> one(String key, ValueNotifier<bool> n) async {
      try {
        final v = await _store.read(key: key);
        if (v != null) n.value = v != '0';
      } catch (_) {}
    }

    await one('wasl_priv_reads', shareReads);
    await one('wasl_priv_presence', sharePresence);
    await one('wasl_priv_typing', shareTyping);
    await one('wasl_priv_fx', liveFx);
  }

  static Future<void> set(String key, bool v) async {
    try {
      await _store.write(key: key, value: v ? '1' : '0');
    } catch (_) {}
  }
}
