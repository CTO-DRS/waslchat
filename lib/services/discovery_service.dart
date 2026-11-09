import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// اكتشاف الأصدقاء من جهات الاتصال (بند المرحلة 1 — 0.4.7).
///
/// التصميم الصادق:
/// - أرقام جهات الاتصال تُطبَّع إلى E.164 وتُجزَّأ SHA-256 **على الجهاز**
///   بملح نطاق ثابت (`wasl-cd-v1:`) — لا يُرفع رقم خام إطلاقاً.
/// - التجزئات تُرسل للخادم لحظة الاكتشاف فقط داخل استدعاء واحد للمقارنة
///   ثم تُهمل — لا تخزين لتجزئات دفتر العناوين إطلاقاً (ترحيل 025).
/// - الرقم الذي يُصرّح به المستخدم ليُكتشف يُخزَّن تجزئةً فقط في
///   `discovery_identity` — حذفه يعيده للخفاء فوراً، ومن لم يصرّح لا
///   يمكن اكتشافه أصلاً. العرض «رقمك المسجّل» يقرأ نسخة محلية على
///   الجهاز (بياناتك على جهازك) — الخادم لا يعرف الرقم.
class DiscoveryService {
  DiscoveryService._();

  /// ملح النطاق: يمنع إعادة استخدام التجزئات عبر خدمات أخرى
  static const String domainSalt = 'wasl-cd-v1:';

  /// مفتاح الدولة الافتراضي عند أرقام بلا مفتاح دولي
  static const String defaultCountryCode = '+966';

  /// أقصى عدد تجزئات في استدعاء واحد (مفروض من الدالة في الخادم أيضاً)
  static const int maxHashesPerCall = 5000;

  /// أقصى عدد تجزئات إجمالاً لدفتر عناوين واحد (يفوق أي دفتر واقعي)
  static const int maxTotalHashes = 20000;

  /// أقصى نتائج يعيدها الخادم لكل استدعاء (500 — مطابقة لترحيل 025)
  static const int maxResultsPerCall = 500;

  static const String _prefsNumber = 'discovery_my_number';

  static final Sha256 _sha256 = Sha256();

  /// تطبيع رقم خام إلى E.164 قدر الإمكان، أو null إن تعذّر.
  ///
  /// القواعد (محدّدة ومُختبرة — يجب أن يطبّقها الطرفانِ على حدّ سواء
  /// كي تتطابق التجزئات):
  /// - «+966 51 234 5678» → +966512345678 (الأصل بمفتاح دولي)
  /// - «00966512345678» → +966512345678 (بادئة 00 الدولية)
  /// - «0512345678» → +966512345678 (صفر وطني + الدولة الافتراضية)
  /// - «966512345678» → +966512345678 (مفتاح الدولة بلا +)
  /// - «512345678» → +966512345678 (رقم محلي بلا صفر — الدولة الافتراضية)
  static String? normalizeToE164(String raw,
      {String defaultCc = defaultCountryCode}) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final hasPlus = s.startsWith('+');
    s = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (s.isEmpty) return null;
    if (hasPlus) return '+$s';
    if (s.startsWith('00')) return '+${s.substring(2)}';
    final ccDigits = defaultCc.startsWith('+') ? defaultCc.substring(1) : defaultCc;
    if (s.startsWith(ccDigits)) return '+$s';
    if (s.startsWith('0')) return defaultCc + s.substring(1);
    return defaultCc + s;
  }

  /// تجزئة رقم E.164 — 64 خانة hex صغيرة
  static Future<String> hashPhone(String e164) async {
    final h = await _sha256.hash(utf8.encode(domainSalt + e164));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// تطبيع وتجزئة دفعة أرقام خام مع إزالة المكرر، أو استثناء إذا
  /// تجاوزت السقف الإجمالي.
  static Future<Set<String>> hashNumbers(Iterable<String> rawNumbers) async {
    final hashes = <String>{};
    for (final raw in rawNumbers) {
      final e = normalizeToE164(raw);
      if (e == null) continue;
      final h = await hashPhone(e);
      hashes.add(h);
      if (hashes.length > maxTotalHashes) {
        throw StateError('عدد جهات الاتصال يتجاوز الحد ($maxTotalHashes)');
      }
    }
    return hashes;
  }

  /// تقطيع التجزئات إلى دفعات ضمن حد الاستدعاء الواحد
  static List<List<String>> chunkHashes(Set<String> hashes) {
    final list = hashes.toList();
    final chunks = <List<String>>[];
    for (var i = 0; i < list.length; i += maxHashesPerCall) {
      chunks.add(
          list.sublist(i, math.min(i + maxHashesPerCall, list.length)));
    }
    return chunks;
  }

  // ── الرقم المُصرّح به (لِيُكتشف صاحبه) ────────────────────────────

  /// إعلان رقمي ليتسمى بني الآخرين: يُخزَّن تجزئةً فقط على الخادم،
  /// والرقم نفسه نسخة محلية على جهازي للعرض.
  static Future<void> declareMyNumber(String rawNumber) async {
    final e = normalizeToE164(rawNumber);
    if (e == null) throw ArgumentError('رقم غير صالح');
    final me = supabase.auth.currentUser?.id;
    if (me == null) throw StateError('غير مسجّل');
    final h = await hashPhone(e);
    await supabase.from('discovery_identity').upsert({
      'user_id': me,
      'phone_hash': h,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsNumber, e);
  }

  /// إزالة رقمي من الاكتشاف — خفاء فوري، لا يمكن اكتشافي بعد حذفه
  static Future<void> clearMyNumber() async {
    final me = supabase.auth.currentUser?.id;
    if (me != null) {
      await supabase.from('discovery_identity').delete().eq('user_id', me);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsNumber);
  }

  /// رقمي المُصرّح به كما هو محفوظ محلياً (للعرض فقط — الخادم لا يعرفه)
  static Future<String?> myDeclaredNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsNumber);
  }

  /// هل رقمي مسجّل على الخادم فعلاً؟ (يُسأل من الخادم مباشرة —
  /// يصحّح الحالة عبر الأجهزة حتى لو اختلفت النسخة المحلية)
  static Future<bool> isDeclaredOnServer() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return false;
    final row = await supabase
        .from('discovery_identity')
        .select('user_id')
        .eq('user_id', me)
        .maybeSingle();
    return row != null;
  }

  // ── الاكتشاف ─────────────────────────────────────────────────────

  /// قراءة دفتر الجهاز (إذن قراءة محلي فقط) وتجزئته ومطابقته.
  ///
  /// يعيد خريطة: نتائج مطابقة (صفوف profiles) + عدد الأرقام المُجزَّأة.
  /// التجزئات لا تُخزَّن في أي مكان — تُرسل وتُهمل.
  static Future<DiscoveryResult> discoverFromDeviceContacts({
    Set<String> excludeIds = const {},
  }) async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      throw StateError('permission_denied');
    }
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final raw = <String>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        if (p.number.isNotEmpty) raw.add(p.number);
      }
    }
    final hashes = await hashNumbers(raw);
    final matches = await discoverByHashes(hashes, excludeIds: excludeIds);
    return DiscoveryResult(
      matches: matches,
      scannedNumbers: raw.length,
      uniqueHashes: hashes.length,
    );
  }

  /// مطابقة تجزئات جاهزة عبر دالة الخادم (بلا تخزين — استدعاء لحظي)
  static Future<List<Map<String, dynamic>>> discoverByHashes(
    Set<String> hashes, {
    Set<String> excludeIds = const {},
  }) async {
    if (hashes.isEmpty) return const [];
    final out = <String, Map<String, dynamic>>{};
    for (final chunk in chunkHashes(hashes)) {
      final rows = await supabase.rpc('discover_contacts', params: {'hashes': chunk});
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = row['user_id'] as String;
        if (id == supabase.auth.currentUser?.id) continue;
        if (excludeIds.contains(id)) continue;
        out[id] = row;
      }
    }
    return out.values.toList();
  }
}

/// نتيجة الاكتشاف لعرضها في الواجهة
class DiscoveryResult {
  DiscoveryResult({
    required this.matches,
    required this.scannedNumbers,
    required this.uniqueHashes,
  });

  /// المستخدمون المطابقون (صفوف profiles)
  final List<Map<String, dynamic>> matches;

  /// عدد الأرقام الخام الممسوحة في دفتر الجهاز
  final int scannedNumbers;

  /// عدد التجزئات الفريدة بعد التطبيع
  final int uniqueHashes;
}
