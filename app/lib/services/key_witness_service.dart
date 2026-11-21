import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// الشهود الخارجيون لشفافية المفاتيح (المرحلة 15 ب — 1.6.0، ترحيل 038).
///
/// إغلاق الحد البنيوي F7 الموثق منذ 0.25.0: سجل الشفافية الإلحاحي مُستضاف
/// على خادم وصل نفسه، ومن يملك إعادة كتابة القاعدة كلها يستطيع نظرياً بناء
/// سلسلة كاذبة متسقة تتحقق عند كل مستخدم وحده. الشاهد الخارجي يكسر هذا:
/// أداة مراقبة مفتوحة المصدر (`tools/key_transparency_witness.py`) تقرأ
/// لقطة دورية من الدالتين الخادمتين (`key_log_witness_heads` و
/// `key_log_witness_digest` — ترحيل 038) وتنشرها في سجل إلحاحي عام — أي
/// إعادة كتابة لاحقة على الخادم تغيّر اللقطة عن المنشور قديماً فيكشف الانتهاك
/// أمام الجميع بلا ثقة بوعد.
///
/// الصيغة الصارمة — مطابقة للدالتين الخادمتين بايتاً بايتاً:
///   blind_digest    = sha256_hex( 'wt1|' || user_id || '|' || head_hash )
///   snapshot_digest = sha256_hex( string_agg(blind, '\n' order by blind) )
///
/// البصمة العمياء لا تكشف شيئاً عن صاحبها لغيره: من لا يعرف uid ورأس سلسلته
/// لا يستطيع ربط البصمة بأحد — وصاحب الحساب يُثبت وجوده في اللقطة بحسابها
/// من معلوماته هو التي تملكها أصلاً.
class KeyWitnessService {
  KeyWitnessService._();

  static const String domain = 'wt1';
  static final Sha256 _sha = Sha256();

  static Future<String> _hex(List<int> bytes) async {
    final h = await _sha.hash(bytes);
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// البصمة العمياء لرأس سلسلة حساب — مطابقة للدالة الخادمية حرفياً.
  /// أي غرابة في المدخلات تعيد '' صادقة (لا بصمة مزيفة لمدخلات فاسدة).
  static Future<String> blindDigest({
    required String userId,
    required String head,
  }) async {
    if (userId.isEmpty || head.isEmpty) return '';
    return _hex(utf8.encode('$domain|$userId|$head'));
  }

  /// بصمة اللقطة الكلية: تجزئة البصمات العمياء مرتبة معاً بسطر جديد —
  /// القائمة الفارغة تعطي بصمة السلسلة الفارغة الثابتة (مطابقة للخادم).
  static Future<String> snapshotDigest(List<String> blindDigests) {
    final sorted = List<String>.from(blindDigests)
      ..removeWhere((b) => b.isEmpty)
      ..sort();
    return _hex(utf8.encode(sorted.join('\n')));
  }

  /// تجميع بصمتك العمياء من صفوف سجلك المحلي — رأس السلسلة آخر صف أُلحِح.
  static Future<String> blindFromChain(
      String userId, List<String> chainHeadsInOrder) async {
    if (userId.isEmpty || chainHeadsInOrder.isEmpty) return '';
    return blindDigest(userId: userId, head: chainHeadsInOrder.last);
  }

  /// صف لقطة الشهود كما يعود من الخادم — تحليل دفاعي: الناقص الجوهري يُسقط
  static WitnessHead? headFromRow(Map<String, dynamic> r) {
    final d = r['blind_digest'] as String?;
    final len = (r['chain_len'] as num?)?.toInt();
    if (d == null || d.length != 64 || len == null || len < 1) return null;
    return WitnessHead(
      blindDigest: d.toLowerCase(),
      chainLen: len,
      lastEventAtIso: (r['last_event_at'] as String?) ?? '',
    );
  }

  /// سطر سجل الشاهد (JSONL) — تحليل دفاعي، والسطر الفاسد يُسقط بلا ثقة
  static WitnessSnapshot? snapshotFromLogLine(String line) {
    try {
      final o = jsonDecode(line);
      if (o is! Map) return null;
      final digest = o['digest'] as String?;
      final ts = o['ts'] as String?;
      if (digest == null ||
          digest.length != 64 ||
          ts == null ||
          DateTime.tryParse(ts) == null) {
        return null;
      }
      final rawHeads = o['heads'];
      final heads = <WitnessHead>[];
      if (rawHeads is List) {
        for (final h in rawHeads) {
          if (h is! Map) continue;
          final d = h['d'] as String?;
          final len = (h['len'] as num?)?.toInt();
          if (d == null || d.length != 64 || len == null || len < 1) continue;
          heads.add(WitnessHead(
            blindDigest: d.toLowerCase(),
            chainLen: len,
            lastEventAtIso: (h['at'] as String?) ?? '',
          ));
        }
      }
      return WitnessSnapshot(
        epochIso: ts,
        digest: digest.toLowerCase(),
        heads: heads,
      );
    } catch (_) {
      return null;
    }
  }

  /// تحقق صاحب الحساب من سجل الشاهد المنشور كاملاً — نقية بلا شبكة:
  /// كل لقطة سليمة بعد [after] يجب أن تحمل بصمتك العمياء، والعناوين الزمنية
  /// رتيبة التصاعدين — أي لقطة بعد لحظة وجودك بلا بصمتك = شاهد يعلن الانتهاك.
  /// يعيد (عدد اللقطات المفحوصة، عدد اللقطات الناقصة، أول لحظة ناقصة).
  static Future<(int, int, String?)> verifyPresenceInLog({
    required List<String> logLines,
    required String blindDigest,
    required DateTime after,
  }) async {
    if (blindDigest.isEmpty) return (0, 0, null);
    var checked = 0;
    var missing = 0;
    String? firstMissing;
    DateTime? lastEpoch;
    for (final line in logLines) {
      final snap = snapshotFromLogLine(line);
      if (snap == null) continue;
      final epoch = DateTime.tryParse(snap.epochIso)?.toUtc();
      if (epoch == null) continue;
      // العناوين الزمنية يجب أن تتقدم — سجل إلحاحي لا يعود للخلف
      if (lastEpoch != null && epoch.isBefore(lastEpoch)) {
        return (checked, missing + 1, snap.epochIso);
      }
      lastEpoch = epoch;
      if (!epoch.isAfter(after)) continue;
      checked++;
      final present = snap.heads.any((h) => h.blindDigest == blindDigest);
      if (!present) {
        missing++;
        firstMissing ??= snap.epochIso;
      }
    }
    return (checked, missing, firstMissing);
  }
}

/// بصمة عمياء واحدة في اللقطة: رأس سلسلة حساب مجهول بطوله ووقت آخر حدث
class WitnessHead {
  const WitnessHead({
    required this.blindDigest,
    required this.chainLen,
    required this.lastEventAtIso,
  });
  final String blindDigest;
  final int chainLen;
  final String lastEventAtIso;
}

/// لقطة شاهد منشورة: لحظة، وبصمة كلية، وقائمة البصمات العمياء
class WitnessSnapshot {
  const WitnessSnapshot({
    required this.epochIso,
    required this.digest,
    required this.heads,
  });
  final String epochIso;
  final String digest;
  final List<WitnessHead> heads;
}
