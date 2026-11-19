import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// نغمات إشعارات وصل شات (1.11.0): كل نغمة تبدأ بصوت «وصل شات» ثم لحن
/// مختلف. تُختار للجميع من الإعدادات، أو لمحادثة بعينها من داخلها.
/// أندرويد يربط الصوت بالقناة، لذلك لكل نغمة قناة خاصة بها.
class WaslTone {
  final String id; // اسم ملف الصوت في res/raw
  final String label;
  final String hint;
  const WaslTone(this.id, this.label, this.hint);
}

class ToneService {
  static const tones = <WaslTone>[
    WaslTone('wasl_classic', 'وصل الكلاسيكية', '«وصل شات» ثم رنّتان صافيتان'),
    WaslTone('wasl_breeze', 'نسيم', '«وصل شات» ثم لحن صاعد خفيف'),
    WaslTone('wasl_crystal', 'كريستال', '«وصل شات» ثم لمعة عالية'),
    WaslTone('wasl_pulse', 'نبض', '«وصل شات» ثم نقرتان سريعتان'),
    WaslTone('wasl_calm', 'هادئة', '«وصل شات» ثم نغمة منخفضة ناعمة'),
    WaslTone('wasl_voice', 'الصوت فقط', '«وصل شات» بلا لحن'),
    WaslTone('system', 'نغمة الجوال', 'صوت الإشعار الافتراضي في جوالك'),
  ];

  static const defaultTone = 'wasl_classic';
  static const _globalKey = 'notif_tone';
  static String _chatKey(String conv) => 'notif_tone_$conv';

  /// النغمة العامة الحالية (لتحديث الواجهة فوراً)
  static final global = ValueNotifier<String>(defaultTone);

  static WaslTone byId(String id) =>
      tones.firstWhere((t) => t.id == id, orElse: () => tones.first);

  static String normalize(String? id) =>
      tones.any((t) => t.id == id) ? id! : defaultTone;

  static Future<void> load() async {
    try {
      global.value = normalize(await _store.read(key: _globalKey));
    } catch (_) {}
  }

  static Future<void> setGlobal(String id) async {
    global.value = normalize(id);
    await _store.write(key: _globalKey, value: global.value);
  }

  /// نغمة محادثة بعينها، أو null = تتبع النغمة العامة
  static Future<String?> chatTone(String conv) async {
    try {
      final v = await _store.read(key: _chatKey(conv));
      return v == null ? null : normalize(v);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setChatTone(String conv, String? id) async {
    if (id == null) {
      await _store.delete(key: _chatKey(conv));
    } else {
      await _store.write(key: _chatKey(conv), value: normalize(id));
    }
  }

  /// النغمة الفعلية لإشعار: نغمة المحادثة إن وُجدت، وإلا العامة.
  /// تُقرأ من التخزين مباشرة لأن معالج الخلفية عزل مستقل.
  static Future<String> effective(String? conv) async {
    try {
      final c = conv == null ? null : await _store.read(key: _chatKey(conv));
      return normalize(c ?? await _store.read(key: _globalKey));
    } catch (_) {
      return defaultTone;
    }
  }

  /// معرّف قناة أندرويد للنغمة («system» = قناة «الرسائل» الأصلية)
  static String channelId(String tone) =>
      tone == 'system' ? 'messages' : 'msg_${tone}_v1';

  static String channelName(String tone) =>
      tone == 'system' ? 'الرسائل' : 'الرسائل — ${byId(tone).label}';

  static const _ch = MethodChannel('wasl/notify');

  static const _store = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));

  /// معاينة النغمة داخل التطبيق
  static Future<void> preview(String tone) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod('playTone', {'name': tone});
    } catch (_) {}
  }
}
