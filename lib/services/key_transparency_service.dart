import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../config.dart';

/// صف من سجل شفافية المفاتيح كما يعود من الخادم (ترحيل 034 — 0.25.0).
class KeyLogEntry {
  KeyLogEntry({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.kind,
    required this.fingerprint,
    required this.prevHash,
    required this.entryHash,
    required this.createdAtIso,
  });

  final int id;
  final String userId;
  final String? deviceId;
  final String kind;
  final String fingerprint;
  final String prevHash;
  final String entryHash;
  final String createdAtIso;

  static KeyLogEntry? fromRow(Map<String, dynamic> r) {
    final id = (r['id'] as num?)?.toInt();
    final uid = r['user_id'] as String?;
    final kind = r['kind'] as String?;
    final hash = r['entry_hash'] as String?;
    if (id == null || uid == null || kind == null || hash == null) return null;
    final fp = (r['fingerprint'] as String?) ?? '';
    final prev = (r['prev_hash'] as String?) ?? '';
    return KeyLogEntry(
      id: id,
      userId: uid,
      deviceId: r['device_id'] as String?,
      kind: kind,
      fingerprint: fp,
      prevHash: prev,
      entryHash: hash,
      createdAtIso: (r['created_at'] as String?) ?? '',
    );
  }

  /// مدخلات إعادة حساب التجزئة كما تحسبها الدالة الخادمية حرفياً
  ({String prev, String userId, String device, String kind, String fp})
      get hashInput => (
          prev: prevHash,
          userId: userId,
          device: deviceId ?? '',
          kind: kind,
          fp: fingerprint,
        );
}

/// شفافية المفاتيح — سجل إلحاقي بسلسلة تجزئة لكل حدث مفاتيح الحساب
/// (المرحلة 10 ب — 0.25.0، ترحيل 034).
///
/// كل حدث (نشر هوية، تسجيل جهاز، إزالة جهاز، مفتاح جديد كلياً) يُلحَح ببصمة
/// المفتاح وسلسلة تجزئة: `sha256(prev|user|device|kind|fingerprint)` — أي
/// تعديل أو حذف أو إعادة ترتيب صف يكسر السلسلة، وشاشة «سجل مفاتيحي» تعيد
/// حسابها **محلياً على الجهاز** وتعلن سلامتها أو أول محطة مكسورة.
///
/// الحد الصادق (موثق في E2EE_PLAN §8-هـ): السجل مُستضاف على الخادم نفسه —
/// من يستطيع إعادة كتابة القاعدة كلها يستطيع إعادة بناء سلسلة كاذبة متسقة.
/// ما يمنعه السجل اليوم: أي عبث جزئي (حذف صف، تعديل بصمة، استبدال تاريخي)
/// يكشفه التطبيق محلياً بلا أي شبكة تحقق. الشهود الخارجيون الموقّعون بعد 1.0.
class KeyTransparencyService {
  KeyTransparencyService._();

  static final Sha256 _sha = Sha256();

  /// الأنواع الأربعة المعروفة — التطابق حرفي مع قيد الترحيل
  static const kinds = [
    'identity_publish',
    'device_register',
    'device_remove',
    'key_reset',
  ];

  /// التجزئة القياسية لصف — نقية ومطابقة للدالة الخادمية بايتاً بايتاً
  static Future<String> entryHash({
    required String prev,
    required String userId,
    required String device,
    required String kind,
    required String fp,
  }) async {
    final h =
        await _sha.hash(utf8.encode('$prev|$userId|$device|$kind|$fp'));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// التحقق من سلامة السلسلة كاملة — نقية: يعيد (سليمة؟، فهرس أول مكسور أو −1).
  /// السلسلة الفارغة سليمة؛ وأي صف شكله غير قابل للتحقق يكسر عند فهرسه.
  static Future<(bool, int)> verifyChain(List<KeyLogEntry> rows) async {
    var prev = '';
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (prev != r.prevHash) return (false, i);
      final expect = await entryHash(
        prev: r.prevHash,
        userId: r.userId,
        device: r.deviceId ?? '',
        kind: r.kind,
        fp: r.fingerprint,
      );
      if (expect != r.entryHash) return (false, i);
      prev = r.entryHash;
    }
    return (true, -1);
  }

  /// تسمية الحدث عربياً — نقية، والغير معروف يبقى صادقاً كما هو
  static String kindLabel(String kind) {
    switch (kind) {
      case 'identity_publish':
        return 'نشر مفتاح الحساب';
      case 'device_register':
        return 'تسجيل جهاز';
      case 'device_remove':
        return 'إزالة جهاز';
      case 'key_reset':
        return 'مفتاح جديد كلياً';
      default:
        return kind;
    }
  }

  /// وصف الحدث السطر الثاني — نقية
  static String kindDetail(String kind) {
    switch (kind) {
      case 'identity_publish':
        return 'هوية الحساب نُشرت أو جُدِّدت على هذا الحساب';
      case 'device_register':
        return 'جهاز سجّل نفسه بهوية ومخزون جديد (جديد أو بعد إزالة)';
      case 'device_remove':
        return 'أُزيل جهاز وحُذف مخزون مفاتيحه من الخادم فوراً';
      case 'key_reset':
        return 'هوية جديدة كلياً بلا استعادة — الرسائل القديمة لن تُقرأ';
      default:
        return 'حدث مفاتيح';
    }
  }

  // ---------- القراءة والتسجيل (وقت التشغيل) ----------

  /// جلب السجل كاملاً بترتيب الإلحاح — صاحب الحساب حصراً بـRLS
  static Future<List<KeyLogEntry>> fetch() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await supabase
          .from('e2e_key_log')
          .select()
          .eq('user_id', uid)
          .order('id');
      return rows
          .map((r) => KeyLogEntry.fromRow(Map<String, dynamic>.from(r)))
          .whereType<KeyLogEntry>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// إلحاح حدث — صامت دائماً (ناريَ ونسيان): فشل الترحيل أو الشبكة لا يعطل
  /// شيئاً، والسجل يلتقط ما يأتي بعد تشغيل 034 — بصدق في الشاشة.
  static Future<void> log({
    required String kind,
    String fingerprint = '',
    String? deviceId,
  }) async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null || !kinds.contains(kind)) return;
      await supabase.rpc('e2e_log_key_event', params: {
        'p_user_id': uid,
        'p_kind': kind,
        'p_fingerprint': fingerprint,
        if (deviceId != null) 'p_device_id': deviceId,
      });
    } catch (_) {}
  }
}
