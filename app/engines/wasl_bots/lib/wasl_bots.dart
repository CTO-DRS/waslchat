/// كتالوج البوتات المجتمعية — المحرك النقي الثالث عشر من محركات وصل
/// (المرحلة 23 — 1.21.0).
///
/// ينفذ بند الخارطة «كتالوج بوتات مجتمعية موثق بقوالب جاهزة (ترحيب، حضور،
/// اقتراحات) على واجهة HMAC القائمة» كنواة نقية بلا أي اعتماديات:
/// HMAC-SHA256 (RFC 2104) مطبق يدوياً فوق SHA-256 النقي المعاد استخدامه
/// حرفياً من محرك النماذج `sha256.dart` (FIPS 180-4)، وبوابة تحقق موقعة
/// بنفس صيغة الواجهة القائمة `X-Wasl-Signature: sha256=HMAC(الجسم، السرّ)`
/// التي يعمل بها الويب هوك منذ المرحلة 4.
///
/// العقد الصادق:
/// 1. **التوقيع قبل الثقة**: أي بيان كتالوج بلا توقيع صحيح يسقط — والمقارنة
///    زمن-ثابت (لا تسرب بصمة البايت الأول)، والمتجهات المرجعية RFC 4231
///    محسوبة خارجياً بـpython hmac (مستقلة عن هذا التنفيذ).
/// 2. **القوالب تُفحص قبل العرض**: حدود معلنة لكل نوع (ترحيب ≤3 رسائل ≤200
///    حرف، حضور 1..2 جلسة ببيتاية/نهاية صحيحة HH:mm، اقتراحات 3..5 ≤80
///    حرفاً) — وتجمع كل الأسباب لا أولها.
/// 3. **حتمية الرندر**: نفس القالب والمدخلات = نص متطابق حرفياً — لا وقت
///    ولا عشوائية في جوهر المحرك.
/// 4. **الفشل صريح**: كل نتيجة تحمل أسبابها المجمعة، والكتالوج يرفض
///    التكرار والترتيب غير القياسي والسعة فوق 12.
///
/// ما ليس في هذه النواة (توثيق صادق): الشبكة والتخزين وصفحة الاكتشاف —
/// النواة تأخذ بايتات وترجع نتائج؛ صفحة الاكتشاف العامة على waslchat.app
/// تخدم الموثق القائم، وربط الغرف الحي عبر خدمة `bot_catalog_service`
/// في التطبيق. المحرك لا يستورد `dart:io` ولا شبكة — اختبار بنائي يحصره.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'sha256.dart';

// ————— HMAC-SHA256 (RFC 2104) — يدوياً فوق SHA-256 النقي —————

/// HMAC-SHA256: المفتاح الأطول من كتلة الـ64 بايتاً يُلَخَّص أولها
/// (مسار hash-first، المتجه المرجعي TC6 من RFC 4231 يثبته)، ثم
/// ipad 0x36 / opad 0x5c على كتلة مبطنة بأصفار.
Uint8List hmacSha256(List<int> key, List<int> message) {
  var k = Uint8List.fromList(key);
  if (k.length > 64) {
    final kh = Sha256()..update(k);
    k = kh.digestBytes();
  }
  final block = Uint8List(64);
  block.setRange(0, k.length.clamp(0, 64), k);
  final inner = Uint8List(64);
  final outer = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    inner[i] = block[i] ^ 0x36;
    outer[i] = block[i] ^ 0x5c;
  }
  final ih = Sha256()..update(inner)..update(message);
  final innerDigest = ih.digestBytes();
  final oh = Sha256()..update(outer)..update(innerDigest);
  return oh.digestBytes();
}

/// مقارنة زمن-ثابت: تمر على كل البايتات دائماً — لا تسرب بصمة البداية.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _toHex(Uint8List bytes) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(digits[(b >> 4) & 0xf]);
    out.write(digits[b & 0xf]);
  }
  return out.toString();
}

/// قراءة نصية صادقة من JSON الفاسد — الرقم أو null يعودان نصاً فارغاً
/// ويدخلان حدود الفحص بدل أن يرميا استثناءً.
String _asString(Object? v) => v is String ? v : '';

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

// ————— بوابة التوقيع — صيغة الواجهة القائمة حرفياً —————

/// نتيجة تحقق التوقيع — كل الأسباب مجمعة لا أولها.
class SignatureResult {
  SignatureResult.ok() : isOk = true, reasons = const [];
  SignatureResult.refused(this.reasons) : isOk = false;

  final bool isOk;
  final List<String> reasons;
}

/// توقيع كائن بيان بالتقانون الواحد: ترميز JSON القياسي (dart:convert)
/// ثم HMAC — يوقّع الناشر به ويصادق عليه المستهلك فلا اختلاف تقانون.
String signManifest(Map<String, dynamic> manifest, List<int> secret) {
  final mac = hmacSha256(secret, utf8.encode(json.encode(manifest)));
  return 'sha256=${_toHex(mac)}';
}

/// تحقق `X-Wasl-Signature: sha256=…` على جسم الطلب — نفس الصيغة التي
/// يفرضها الخادم على ويب هوك البوتات منذ المرحلة 4، هنا كبوابة كتالوج.
SignatureResult verifyXWaslSignature(
    String header, List<int> body, List<int> secret) {
  final reasons = <String>[];
  final h = header.trim();
  if (h.isEmpty) {
    reasons.add('التوقيع مفقود');
  }
  if (!h.startsWith('sha256=')) {
    reasons.add('بادئة التوقيع يجب أن تكون sha256=');
  }
  final hex = h.startsWith('sha256=') ? h.substring(7) : '';
  if (hex.length != 64) {
    reasons.add('بصمة التوقيع يجب أن تكون 64 خانة سدسية لا ${hex.length}');
  } else if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
    reasons.add('بصمة التوقيع تحوي محارف غير سدسية');
  }
  if (reasons.isEmpty) {
    final given = _hexToBytes(hex);
    final expected = hmacSha256(secret, body);
    if (!constantTimeEquals(given, expected)) {
      reasons.add('التوقيع لا يطابق جسم البيان');
    }
  }
  return reasons.isEmpty
      ? SignatureResult.ok()
      : SignatureResult.refused(reasons);
}

// ————— القوالب الجاهزة الثلاثة —————

enum BotTemplateType { welcome, attendance, suggestions }

/// قالب جاهز واحد — كل نوع بحقله وحده وحدوده المعلنة.
class BotTemplate {
  const BotTemplate.welcome(this.messages)
      : type = BotTemplateType.welcome,
        sessions = const [],
        prompts = const [];

  const BotTemplate.attendance(List<(String, String)> this.sessions)
      : type = BotTemplateType.attendance,
        messages = const [],
        prompts = const [];

  const BotTemplate.suggestions(this.prompts)
      : type = BotTemplateType.suggestions,
        messages = const [],
        sessions = const [];

  final BotTemplateType type;
  final List<String> messages; // welcome
  final List<(String, String)> sessions; // attendance (start,end)
  final List<String> prompts; // suggestions

  /// حدود القالب المعلنة — تُجمع كل المخالفات لا أولها.
  List<String> validate() {
    final reasons = <String>[];
    switch (type) {
      case BotTemplateType.welcome:
        if (messages.isEmpty || messages.length > 3) {
          reasons.add('قوالب الترحيب من 1 إلى 3 رسائل لا ${messages.length}');
        }
        for (final m in messages) {
          if (m.trim().isEmpty || m.length > 200) {
            reasons.add('رسالة ترحيب فارغة أو أطول من 200 حرف (${m.length})');
          }
        }
      case BotTemplateType.attendance:
        if (sessions.isEmpty || sessions.length > 2) {
          reasons.add('قوالب الحضور من 1 إلى 2 جلسة لا ${sessions.length}');
        }
        final time = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
        for (final (start, end) in sessions) {
          if (!time.hasMatch(start) || !time.hasMatch(end)) {
            reasons.add('أوقات الحضور يجب أن تكون HH:mm صحيحة: $start / $end');
          } else if (start.compareTo(end) >= 0) {
            reasons.add('بداية جلسة الحضور يجب أن تسبق نهايتها: $start ≥ $end');
          }
        }
      case BotTemplateType.suggestions:
        if (prompts.length < 3 || prompts.length > 5) {
          reasons.add('قوالب الاقتراحات من 3 إلى 5 عناصر لا ${prompts.length}');
        }
        for (final p in prompts) {
          if (p.trim().isEmpty || p.length > 80) {
            reasons.add('اقتراح فارغ أو أطول من 80 حرفاً (${p.length})');
          }
        }
    }
    return reasons;
  }

  /// رندر حتمي — بلا وقت ولا عشوائية.
  String? renderWelcome(String recipientName) =>
      type == BotTemplateType.welcome
          ? messages.map((m) => m.replaceAll('{name}', recipientName)).join('\n')
          : null;

  String? renderAttendance() => type == BotTemplateType.attendance
      ? sessions.map((s) => 'الحضور: ${s.$1}–${s.$2}').join(' ، ')
      : null;

  List<String>? renderSuggestions() => type == BotTemplateType.suggestions
      ? List<String>.from(prompts)
      : null;

  Map<String, dynamic> toJson() => switch (type) {
        BotTemplateType.welcome => {'type': 'welcome', 'messages': messages},
        BotTemplateType.attendance => {
            'type': 'attendance',
            'sessions': [
              for (final (s, e) in sessions) {'start': s, 'end': e}
            ],
          },
        BotTemplateType.suggestions => {'type': 'suggestions', 'prompts': prompts},
      };

  /// من JSON — المخالفات تُجمَع في reasons والعنصر الفاسد يُسقط (لا استثناءات).
  static BotTemplate? fromJson(
      Map<String, dynamic> j, List<String> reasons) {
    final type = j['type'] as String?;
    switch (type) {
      case 'welcome':
        final rawMsgs = (j['messages'] as List?) ?? const [];
        final msgs = <String>[];
        for (final m in rawMsgs) {
          if (m is! String) {
            reasons.add('رسالة ترحيب ليست نصاً');
            continue;
          }
          msgs.add(m);
        }
        final t = BotTemplate.welcome(msgs);
        final bad = t.validate();
        reasons.addAll(bad.map((r) => 'قالب ترحيب: $r'));
        return bad.isEmpty ? t : null;
      case 'attendance':
        final raw = (j['sessions'] as List?) ?? const [];
        final ss = <(String, String)>[];
        for (final s in raw) {
          if (s is! Map<String, dynamic>) {
            reasons.add('جلسة حضور ليست كائناً');
            continue;
          }
          ss.add((_asString(s['start']), _asString(s['end'])));
        }
        final t = BotTemplate.attendance(ss);
        final bad = t.validate();
        reasons.addAll(bad.map((r) => 'قالب حضور: $r'));
        return bad.isEmpty ? t : null;
      case 'suggestions':
        final rawPs = (j['prompts'] as List?) ?? const [];
        final ps = <String>[];
        for (final p in rawPs) {
          if (p is! String) {
            reasons.add('اقتراح ليس نصاً');
            continue;
          }
          ps.add(p);
        }
        final t = BotTemplate.suggestions(ps);
        final bad = t.validate();
        reasons.addAll(bad.map((r) => 'قالب اقتراحات: $r'));
        return bad.isEmpty ? t : null;
      default:
        reasons.add('نوع قالب غير معروف: $type');
        return null;
    }
  }
}

// ————— بيان البوت والكتالوج —————

/// بيان بوت مجتمعي موثق — الاسم البرمجي بصيغة الواجهة القائمة حرفياً
/// (`^[a-z0-9_]{4,20}_bot$` كما في BotService وترحيل 025).
class BotManifest {
  BotManifest({
    required this.username,
    required this.displayName,
    required this.description,
    required this.templates,
  });

  final String username;
  final String displayName;
  final String description;
  final List<BotTemplate> templates;

  static final RegExp usernameFormat = RegExp(r'^[a-z0-9_]{4,20}_bot$');

  /// كل المخالفات مجمعة — بيان بلا مخالفات فقط يُعتمد.
  List<String> validate() {
    final reasons = <String>[];
    if (!usernameFormat.hasMatch(username)) {
      reasons.add('الاسم البرمجي يجب أن يطابق ^[a-z0-9_]{4,20}_bot\$: '
          '$username');
    }
    if (displayName.trim().isEmpty || displayName.length > 40) {
      reasons.add('اسم العرض فارغ أو أطول من 40 حرفاً');
    }
    if (description.length > 240) {
      reasons.add('الوصف أطول من 240 حرفاً (${description.length})');
    }
    if (templates.isEmpty || templates.length > 3) {
      reasons.add('عدد القوالب من 1 إلى 3 لا ${templates.length}');
    }
    final types = templates.map((t) => t.type).toSet();
    if (types.length != templates.length) {
      reasons.add('نوع قالب مكرر في نفس البيان');
    }
    for (final t in templates) {
      reasons.addAll(t.validate().map((r) => 'قالب ${t.type.name}: $r'));
    }
    return reasons;
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'displayName': displayName,
        'description': description,
        'templates': [for (final t in templates) t.toJson()],
      };

  /// من JSON — مع كل الأسباب المجمعة، والفاسد يُسقط.
  static (BotManifest?, List<String>) fromJson(Map<String, dynamic> j) {
    final reasons = <String>[];
    final username = _asString(j['username']);
    final displayName = _asString(j['displayName']);
    final description = _asString(j['description']);
    final rawTemplates = (j['templates'] as List?) ?? const [];
    final templates = <BotTemplate>[];
    for (final raw in rawTemplates) {
      if (raw is! Map<String, dynamic>) {
        reasons.add('قالب فاسد — ليس كائناً');
        continue;
      }
      final parsed = BotTemplate.fromJson(raw, reasons);
      if (parsed != null) templates.add(parsed);
    }
    final m = BotManifest(
      username: username,
      displayName: displayName,
      description: description,
      templates: templates,
    );
    reasons.addAll(m.validate());
    return (reasons.isEmpty ? m : null, reasons);
  }
}

/// كتالوج موثق: نسخة + قائمة بوتات، كل بيان موقّع بـ`sha256=…` على
/// ترميزه القانوني — والترتيب القياسي (تصاعدياً بالاسم البرمجي) شرط
/// اعتماد، فلا كتالوج يتبدل حسب ترتيب وصوله.
class CatalogEntry {
  CatalogEntry(this.manifest, this.signature);
  final BotManifest manifest;
  final String signature;
}

class CatalogResult {
  CatalogResult.ok(this.entries) : reasons = const [];
  CatalogResult.refused(this.reasons) : entries = const [];

  final List<CatalogEntry> entries;
  final List<String> reasons;
  bool get isOk => reasons.isEmpty;
}

/// تحقق كتالوج كامل — الوسم الصادق:
/// {
///   "version": 1,
///   "bots": [ {"manifest": {...}, "signature": "sha256=…"} ]
/// }
CatalogResult verifyCatalog(
    String jsonText, List<int> secret,
    {int maxBots = 12}) {
  final reasons = <String>[];
  Object? decoded;
  try {
    decoded = json.decode(jsonText);
  } on FormatException {
    return CatalogResult.refused(['نص الكتالوج ليس JSON صالحاً']);
  }
  final doc = decoded as Map<String, dynamic>;
  if (doc['version'] != 1) {
    reasons.add('نسخة الكتالوج يجب أن تكون 1 لا ${doc['version']}');
  }
  final rawBots = (doc['bots'] as List?) ?? const [];
  if (rawBots.isEmpty) reasons.add('الكتالوج فارغ — لا بوتات');
  if (rawBots.length > maxBots) {
    reasons.add('عدد البوتات ${rawBots.length} فوق الحد $maxBots');
  }
  final entries = <CatalogEntry>[];
  for (final raw in rawBots) {
    if (raw is! Map<String, dynamic>) {
      reasons.add('مدخل بوت فاسد — ليس كائناً');
      continue;
    }
    final manifestJson = raw['manifest'];
    final signature = _asString(raw['signature']);
    if (manifestJson is! Map<String, dynamic>) {
      reasons.add('مدخل بوت بلا بيان');
      continue;
    }
    // التوقيع على الترميز القانوني قبل أي فك — كما وقّع الناشر
    final sig = verifyXWaslSignature(
        signature, utf8.encode(json.encode(manifestJson)), secret);
    if (!sig.isOk) {
      reasons.addAll(sig.reasons.map((r) => 'بوت: $r'));
      continue;
    }
    final (m, mReasons) = BotManifest.fromJson(manifestJson);
    if (m == null) {
      reasons.addAll(mReasons.map((r) => 'بوت: $r'));
      continue;
    }
    entries.add(CatalogEntry(m, signature));
  }
  // الترتيب القياسي والتكرار — بعد اجتياز التوقيعات
  final names = entries.map((e) => e.manifest.username).toList();
  final sorted = [...names]..sort();
  if (!const ListEquality().equals(names, sorted) && names.length > 1) {
    reasons.add('الترتيب القياسي تصاعدياً بالاسم البرمجي — الكتالوج غير مرتب');
  }
  if (names.toSet().length != names.length) {
    reasons.add('اسم برمجي مكرر في الكتالوج');
  }
  return reasons.isEmpty
      ? CatalogResult.ok(entries)
      : CatalogResult.refused(reasons);
}

/// مقارنة قوائم بترتيبها — للتحقق من الترتيب القياسي.
class ListEquality {
  const ListEquality();

  bool equals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
