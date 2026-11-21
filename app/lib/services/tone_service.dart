import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// مجموعات النغمات في الاستوديو
enum ToneGroup { voice, melody, custom, system }

/// نغمة إشعار. الجاهزة ملفاتها في res/raw (المعرّف = اسم الملف)،
/// ونغماتك المصنوعة في الاستوديو ملفات على جهازك بمعرّف يبدأ بـ c_.
class WaslTone {
  final String id;
  final String label;
  final String hint;
  final ToneGroup group;

  /// رابط المحتوى الذي يقرأ منه النظام الصوت (لنغماتك فقط)
  final String? uri;

  /// مسار الملف على الجهاز (لنغماتك فقط)
  final String? path;
  const WaslTone(this.id, this.label, this.hint,
      [this.group = ToneGroup.voice, this.uri, this.path]);

  bool get isCustom => group == ToneGroup.custom;

  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'hint': hint, 'uri': uri, 'path': path};

  static WaslTone fromJson(Map<String, dynamic> j) => WaslTone(
      j['id'] as String,
      (j['label'] as String?) ?? 'نغمتي',
      (j['hint'] as String?) ?? 'من استوديو الصوت',
      ToneGroup.custom,
      j['uri'] as String?,
      j['path'] as String?);
}

/// قطعة من مكتبة الاستوديو (صوت أو لحن) في assets/tones
/// [hint] للأصوات = قسمها (رجالية/نسائية/طفولية)
class StudioPiece {
  final String id;
  final String label;
  final String hint;
  const StudioPiece(this.id, this.label, this.hint);
  String get asset => 'assets/tones/$id.wav';
}

class ToneService {
  /// النغمات الجاهزة (1.11.0 + 1.12.0)
  static const builtIn = <WaslTone>[
    // «وصل شات» بأصوات وطرق نطق مختلفة
    WaslTone('wasl_classic', 'وصل الكلاسيكية', '«وصل شات» ثم رنّتان صافيتان'),
    WaslTone('wasl_breeze', 'نسيم', '«وصل شات» ثم لحن صاعد خفيف'),
    WaslTone('wasl_crystal', 'كريستال', '«وصل شات» ثم لمعة عالية'),
    WaslTone('wasl_pulse', 'نبض', '«وصل شات» ثم نقرتان سريعتان'),
    WaslTone('wasl_calm', 'هادئة', '«وصل شات» ثم نغمة منخفضة ناعمة'),
    WaslTone('wasl_voice', 'الصوت فقط', '«وصل شات» بلا لحن'),
    WaslTone('wasl_man', 'رجالي', '«وصل شات» بصوت رجالي واضح'),
    WaslTone('wasl_man_deep', 'رجالي عميق', 'صوت رجالي هادئ وعميق'),
    WaslTone('wasl_man_energy', 'حماسي', 'صوت رجالي مليء بالطاقة'),
    WaslTone('wasl_anchor', 'مذيع', 'بأسلوب مذيع الأخبار'),
    WaslTone('wasl_grand', 'فخم', 'صوت رجالي فخم'),
    WaslTone('wasl_newmsg', 'رسالة جديدة', '«رسالة جديدة على وصل شات»'),
    WaslTone('wasl_whisper', 'همس', '«وصل شات» همساً'),
    WaslTone('wasl_warm', 'دافئ', 'صوت نسائي دافئ'),
    WaslTone('wasl_cheer', 'مبهج', 'صوت نسائي مبهج'),
    WaslTone('wasl_soft', 'ناعم', 'صوت نسائي ناعم'),
    WaslTone('wasl_bright', 'مشرق', 'صوت نسائي مشرق'),
    WaslTone('wasl_kid', 'طفولي', 'صوت طفل مرح'),
    WaslTone('wasl_kid_play', 'طفلة', 'صوت طفلة مع ماريمبا'),
    WaslTone('wasl_kid_boy', 'طفل', 'صوت طفل مع نقرتين'),
    WaslTone('wasl_robot', 'روبوت', 'صوت آلي تقني'),
    WaslTone('wasl_radio', 'لاسلكي', 'كأنه من جهاز لاسلكي'),
    WaslTone('wasl_space', 'فضائي', 'صوت فضائي بصدى'),
    WaslTone('wasl_echo', 'صدى', '«وصل شات» بصدى'),
    WaslTone('wasl_giant', 'عملاق', 'صوت عميق جداً'),
    // ألحان بلا كلام
    WaslTone('tone_marimba', 'ماريمبا', 'خمس نقرات خشبية مرحة', ToneGroup.melody),
    WaslTone('tone_bubble', 'فقاعة', 'ثلاث نقرات قصيرة صاعدة', ToneGroup.melody),
    WaslTone('tone_oasis', 'واحة', 'أجراس دافئة متتابعة', ToneGroup.melody),
    WaslTone('tone_star', 'نجمة', 'لمعات زجاجية عالية', ToneGroup.melody),
    WaslTone('tone_dawn', 'فجر', 'نغمة ناعمة طويلة', ToneGroup.melody),
    WaslTone('tone_knock', 'طرقة', 'طرقتان خفيفتان', ToneGroup.melody),
    WaslTone('tone_alert', 'تنبيه', 'أربع رنّات واضحة', ToneGroup.melody),
    WaslTone('tone_classic', 'رنّتان', 'لحن الكلاسيكية بلا كلام', ToneGroup.melody),
    WaslTone('system', 'نغمة الجوال', 'صوت الإشعار الافتراضي في جوالك',
        ToneGroup.system),
  ];

  /// أصوات الاستوديو: «وصل شات» بأصوات مختلفة
  static const studioVoices = <StudioPiece>[
    StudioPiece('v_aoede', 'الأصلي', 'الأصلية'),
    StudioPiece('v_orus', 'رجالي', 'رجالية'),
    StudioPiece('v_fenrir', 'حماسي', 'رجالية'),
    StudioPiece('v_algieba', 'عميق', 'رجالية'),
    StudioPiece('v_iapetus', 'رسمي', 'رجالية'),
    StudioPiece('v_charon', 'فخم', 'رجالية'),
    StudioPiece('v_rasal', 'مذيع', 'رجالية'),
    StudioPiece('v_alnilam', 'واثق', 'رجالية'),
    StudioPiece('v_umbriel', 'شاب', 'رجالية'),
    StudioPiece('v_schedar', 'ودود', 'رجالية'),
    StudioPiece('v_puck', 'مرح', 'رجالية'),
    StudioPiece('v_zubene', 'هادئ', 'رجالية'),
    StudioPiece('v_sadachbia', 'سريع', 'رجالية'),
    StudioPiece('v_achird', 'لطيف', 'رجالية'),
    StudioPiece('v_enceladus', 'همس', 'رجالية'),
    StudioPiece('p_newmsg_m', '«رسالة جديدة»', 'رجالية'),
    StudioPiece('v_leda', 'دافئة', 'نسائية'),
    StudioPiece('v_despina', 'مبهجة', 'نسائية'),
    StudioPiece('v_kore', 'واثقة', 'نسائية'),
    StudioPiece('v_achernar', 'ناعمة', 'نسائية'),
    StudioPiece('v_gacrux', 'ناضجة', 'نسائية'),
    StudioPiece('v_laomedeia', 'مشرقة', 'نسائية'),
    StudioPiece('v_sulafat', 'هادئة', 'نسائية'),
    StudioPiece('v_erinome', 'رقيقة', 'نسائية'),
    StudioPiece('v_autonoe', 'واضحة', 'نسائية'),
    StudioPiece('v_callirrhoe', 'رسمية', 'نسائية'),
    StudioPiece('v_aoede_happy', 'طفولي', 'طفولية'),
  ];

  /// ألحان الاستوديو
  static const studioMelodies = <StudioPiece>[
    StudioPiece('mel_classic', 'رنّتان', ''),
    StudioPiece('mel_breeze', 'نسيم', ''),
    StudioPiece('mel_crystal', 'كريستال', ''),
    StudioPiece('mel_pulse', 'نبض', ''),
    StudioPiece('mel_calm', 'هادئة', ''),
    StudioPiece('mel_marimba', 'ماريمبا', ''),
    StudioPiece('mel_bubble', 'فقاعة', ''),
    StudioPiece('mel_oasis', 'واحة', ''),
    StudioPiece('mel_star', 'نجمة', ''),
    StudioPiece('mel_dawn', 'فجر', ''),
    StudioPiece('mel_knock', 'طرقة', ''),
    StudioPiece('mel_alert', 'تنبيه', ''),
  ];

  /// قسم كل نغمة جاهزة في المكتبة
  static const sections = <String, String>{
    "wasl_classic": "الأصلية",
    "wasl_breeze": "الأصلية",
    "wasl_crystal": "الأصلية",
    "wasl_pulse": "الأصلية",
    "wasl_calm": "الأصلية",
    "wasl_voice": "الأصلية",
    "wasl_man": "رجالية",
    "wasl_man_deep": "رجالية",
    "wasl_man_energy": "رجالية",
    "wasl_anchor": "رجالية",
    "wasl_grand": "رجالية",
    "wasl_newmsg": "رجالية",
    "wasl_whisper": "رجالية",
    "wasl_warm": "نسائية",
    "wasl_cheer": "نسائية",
    "wasl_soft": "نسائية",
    "wasl_bright": "نسائية",
    "wasl_kid": "طفولية",
    "wasl_kid_play": "طفولية",
    "wasl_kid_boy": "طفولية",
    "wasl_robot": "تقنية",
    "wasl_radio": "تقنية",
    "wasl_space": "تقنية",
    "wasl_echo": "تقنية",
    "wasl_giant": "تقنية",
  };

  static String sectionOf(WaslTone t) => switch (t.group) {
        ToneGroup.melody => 'ألحان بلا كلام',
        ToneGroup.system => 'ألحان بلا كلام',
        ToneGroup.custom => 'نغماتي',
        ToneGroup.voice => sections[t.id] ?? 'الأصلية',
      };

  static const sectionOrder = ['نغماتي', 'الأصلية', 'رجالية', 'نسائية', 'طفولية', 'تقنية', 'ألحان بلا كلام'];

  static const defaultTone = 'wasl_classic';
  static const _globalKey = 'notif_tone';
  static const _customKey = 'custom_tones';
  static String _chatKey(String conv) => 'notif_tone_$conv';

  /// النغمة العامة الحالية (لتحديث الواجهة فوراً)
  static final global = ValueNotifier<String>(defaultTone);

  /// نغماتك المصنوعة في الاستوديو
  static final custom = ValueNotifier<List<WaslTone>>(const []);

  /// للتوافق مع 1.11.0: كل النغمات المتاحة الآن
  static List<WaslTone> get tones => [...builtIn, ...custom.value];

  static WaslTone byId(String id) =>
      tones.firstWhere((t) => t.id == id, orElse: () => builtIn.first);

  static String normalize(String? id) => normalizeIn(id, custom.value);

  static String normalizeIn(String? id, List<WaslTone> customList) =>
      (builtIn.any((t) => t.id == id) || customList.any((t) => t.id == id))
          ? id!
          : defaultTone;

  static List<WaslTone> decodeCustom(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => WaslTone.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<WaslTone>> _readCustom() async {
    try {
      return decodeCustom(await _store.read(key: _customKey));
    } catch (_) {
      return const [];
    }
  }

  static Future<void> load() async {
    try {
      custom.value = await _readCustom();
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
  static Future<WaslTone> effectiveTone(String? conv) async {
    try {
      final list = await _readCustom();
      final c = conv == null ? null : await _store.read(key: _chatKey(conv));
      final id = normalizeIn(c ?? await _store.read(key: _globalKey), list);
      return [...builtIn, ...list].firstWhere((t) => t.id == id);
    } catch (_) {
      return builtIn.first;
    }
  }

  static Future<String> effective(String? conv) async =>
      (await effectiveTone(conv)).id;

  /// معرّف قناة أندرويد للنغمة («system» = قناة «الرسائل» الأصلية)
  static String channelId(String tone) =>
      tone == 'system' ? 'messages' : 'msg_${tone}_v1';

  static String reminderChannelId(String tone) =>
      tone == 'system' ? 'wasl-reminders' : 'rem_${tone}_v1';

  static String channelName(String tone) =>
      tone == 'system' ? 'الرسائل' : 'الرسائل — ${byId(tone).label}';

  static const _ch = MethodChannel('wasl/notify');

  static const _store = FlutterSecureStorage(
      aOptions: AndroidOptions());

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// معاينة النغمة داخل التطبيق
  static Future<void> preview(String tone) async {
    if (!supported) return;
    final t = byId(tone);
    try {
      if (t.isCustom && t.path != null) {
        await _ch.invokeMethod('playFile', {'path': t.path});
      } else {
        await _ch.invokeMethod('playTone', {'name': tone});
      }
    } catch (_) {}
  }

  /// تشغيل ملف صوتي (مسودة الاستوديو)
  static Future<void> playFile(String path) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('playFile', {'path': path});
    } catch (_) {}
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/tones');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// ملف مؤقت للمعاينة في الاستوديو
  static Future<String> writeDraft(Uint8List wav) async {
    final d = await _dir();
    final f = File('${d.path}/draft.wav');
    await f.writeAsBytes(wav, flush: true);
    return f.path;
  }

  /// حفظ نغمة جديدة من الاستوديو وتسجيل قناتها في النظام
  static Future<WaslTone?> saveCustom(Uint8List wav, String label, String hint) async {
    if (!supported) return null;
    final id = 'c_${DateTime.now().millisecondsSinceEpoch}';
    final d = await _dir();
    final f = File('${d.path}/$id.wav');
    await f.writeAsBytes(wav, flush: true);
    final clean = label.trim().isEmpty ? 'نغمتي' : label.trim();
    String? uri;
    try {
      uri = await _ch.invokeMethod<String>('registerTone', {
        'id': id,
        'path': f.path,
        'msgChannel': channelId(id),
        'remChannel': reminderChannelId(id),
        'name': 'الرسائل — $clean',
      });
    } catch (_) {}
    if (uri == null) {
      try {
        f.deleteSync();
      } catch (_) {}
      return null;
    }
    final t = WaslTone(id, clean, hint, ToneGroup.custom, uri, f.path);
    custom.value = [...custom.value, t];
    await _saveCustomList();
    return t;
  }

  static Future<void> renameCustom(String id, String label) async {
    custom.value = [
      for (final t in custom.value)
        t.id == id
            ? WaslTone(t.id, label.trim().isEmpty ? t.label : label.trim(), t.hint,
                ToneGroup.custom, t.uri, t.path)
            : t
    ];
    await _saveCustomList();
  }

  /// حذف نغمة: من يستخدمها يعود للنغمة الافتراضية تلقائياً
  static Future<void> deleteCustom(String id) async {
    final t = custom.value.where((e) => e.id == id).toList();
    custom.value = custom.value.where((e) => e.id != id).toList();
    await _saveCustomList();
    if (global.value == id) await setGlobal(defaultTone);
    try {
      await _ch.invokeMethod('deleteTone', {
        'msgChannel': channelId(id),
        'remChannel': reminderChannelId(id),
      });
    } catch (_) {}
    for (final x in t) {
      try {
        if (x.path != null) File(x.path!).deleteSync();
      } catch (_) {}
    }
  }

  static Future<void> _saveCustomList() async {
    await _store.write(
        key: _customKey,
        value: jsonEncode(custom.value.map((e) => e.toJson()).toList()));
  }
}
