import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'e2e_service.dart';
import 'media_service.dart';

/// الحالات/القصص المشفّرة (24 ساعة) — المرحلة 1
///
/// الجمهور: شركاء المحادثات الفردية (بلا حظر بينهم) — يحدده الخادم في
/// `my_status_audience` و`my_status_feed` (ترحيل 018).
/// كل حالة: مفتاح محتوى عشوائي 32B يبقى على الأجهزة؛ النص/الوسيط يشفَّر
/// AES-256-GCM بسياق معرف الحالة (AAD يمنع نقل نص مشفّر بين حالات)، والمفتاح
/// يُغلَّف لكل مشاهد بنمط أظرفة المجموعات (HKDF-X25519 بسياق معرف الحالة)،
/// ويُغلَّف لصاحب الحالة نفسه أيضاً ليبقى قابلاً للعرض بعد إعادة تشغيل التطبيق.
/// الخادم لا يرى إلا نصوصاً مشفّرة وأظرفةً مغلقة وتواريخ النشر والانتهاء.
class StatusService {
  StatusService._();

  /// حد الجمهور (حماية من زحام أظرفة فاشلة)
  static const maxAudience = 300;

  /// حد نص الحالة بالأحرف
  static const maxTextChars = 700;

  static final Map<String, SecretKey> _keyCache = {};
  static final Map<String, String> _textCache = {};
  static final Map<String, Uint8List> _mediaCache = {};

  /// معرف UUID v4 محلي — الصاحب يولّده قبل التشفير لأنه جزء من سياق AAD
  static String newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ---------- النشر ----------

  /// جمهور الحالة المحتمل (شركاء المحادثات الفردية بمفاتيحهم) — الخادم يقصّ نهائياً
  static Future<List<Map<String, dynamic>>> audience() async {
    final rows = await supabase.rpc('my_status_audience');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// نشر حالة نصية — تُشفَّر قبل مغادرة الجهاز
  static Future<void> publishText(String text) async {
    final t = text.trim();
    if (t.isEmpty || t.length > maxTextChars) throw Exception('bad status text');
    if (!E2eService.withinPlainLimit(t)) throw Exception('status text too long');
    await _publish(kind: 'text', body: t);
  }

  /// نشر حالة صورة (تُشفَّر بايتاتها ثم تُرفع بامتداد .enc.bin)
  static Future<void> publishImage(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 24 * 1024 * 1024) {
      throw Exception('bad status image');
    }
    await _publish(kind: 'image', imageBytes: bytes);
  }

  static Future<void> _publish({
    required String kind,
    String? body,
    Uint8List? imageBytes,
  }) async {
    final me = supabase.auth.currentUser!.id;
    final id = newId();
    final key = await E2eService.newContentKey();

    String bodyEnc = '';
    String? mediaPath;
    if (kind == 'image') {
      final payload = await E2eService.encryptBytes(key, id, imageBytes!);
      mediaPath = await MediaService.upload(
        conversationId: id, // المجلد الأول = معرف الحالة (سياسة تخزين الحالات)
        bytes: payload,
        ext: 'enc.bin',
        contentType: 'application/octet-stream',
      );
    } else {
      bodyEnc = await E2eService.encryptText(key, id, body!);
    }

    await supabase.from('statuses').insert({
      'id': id,
      'user_id': me,
      'kind': kind,
      'body': bodyEnc,
      if (mediaPath != null) 'media_path': mediaPath,
      if (mediaPath != null) 'media_mime': 'application/octet-stream',
    });

    // ظرفي أولاً: بلا عندها أفقد حالتي بعد إعادة تشغيل التطبيق
    final pair = await E2eService.identityPair();
    final myEnv = {
      'status_id': id,
      'viewer_id': me,
      'wrapped_key': await E2eService.wrapGroupKey(
        groupKey: key,
        conversationId: id,
        wrapperPair: pair,
        memberPub: await pair.extractPublicKey(),
      ),
    };
    await supabase.from('status_key_envelopes').insert(myEnv);

    // أظرفة الجمهور: دفعة واحدة، وعند رفض أي صف (حظر متأخر مثلاً) نُفردها بصمت
    final rest = <Map<String, dynamic>>[];
    try {
      final targets = await audience();
      for (final t in targets) {
        if (rest.length >= maxAudience - 1) break;
        final pubB64 = t['identity_public_key'] as String?;
        if (pubB64 == null || pubB64.isEmpty) continue; // بلا مفتاح: لن يفكّ أبداً
        try {
          final pub = SimplePublicKey(base64Decode(pubB64), type: KeyPairType.x25519);
          rest.add({
            'status_id': id,
            'viewer_id': t['id'] as String,
            'wrapped_key': await E2eService.wrapGroupKey(
                groupKey: key, conversationId: id, wrapperPair: pair, memberPub: pub),
          });
        } catch (_) {}
      }
      if (rest.isNotEmpty) {
        await supabase.from('status_key_envelopes').insert(rest);
      }
    } catch (_) {
      for (final e in rest) {
        try {
          await supabase.from('status_key_envelopes').insert(e);
        } catch (_) {}
      }
    }
  }

  // ---------- القراءة ----------

  /// الحالات النشطة (لي + شركاء محادثاتي الفردية) كما يحددها الخادم
  static Future<List<Map<String, dynamic>>> feed() async {
    final rows = await supabase.rpc('my_status_feed');
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (_keyCache.length > 500) _keyCache.clear();
    if (_textCache.length > 500) _textCache.clear();
    if (_mediaCache.length > 30) _mediaCache.clear();
    return list;
  }

  /// مفتاح حالة من الظرف (يُخزَّن مؤقتاً حتى نهاية الجلسة)
  static Future<SecretKey?> statusKey(Map<String, dynamic> s) async {
    final sid = s['status_id'] as String;
    final hit = _keyCache[sid];
    if (hit != null) return hit;
    final wrapped = s['wrapped_key'] as String?;
    if (wrapped == null || !E2eService.isEncrypted(wrapped)) return null;
    final authorId = (s['author_id'] ?? s['user_id']) as String?;
    if (authorId == null) return null;
    final authorPub = await E2eService.publicKeyOf(authorId);
    if (authorPub == null) return null;
    final key = await E2eService.unwrapGroupKey(
      wrapped: wrapped,
      conversationId: sid,
      myPair: await E2eService.identityPair(),
      wrapperPub: authorPub,
    );
    if (key != null) _keyCache[sid] = key;
    return key;
  }

  /// نص الحالة مفكوكاً (null عند الفشل — 🔒 في الواجهة)
  static Future<String?> decryptText(Map<String, dynamic> s) async {
    final sid = s['status_id'] as String;
    final hit = _textCache[sid];
    if (hit != null) return hit;
    final raw = (s['body'] ?? '') as String;
    if (raw.isEmpty) return '';
    if (!E2eService.isEncrypted(raw)) return raw; // توافق رجعي
    final key = await statusKey(s);
    if (key == null) return null;
    final plain = await E2eService.decryptText(key, sid, raw);
    if (plain != null) _textCache[sid] = plain;
    return plain;
  }

  /// بايتات وسيط الحالة مفكوكة (null عند الفشل)
  static Future<Uint8List?> decryptMedia(Map<String, dynamic> s) async {
    final sid = s['status_id'] as String;
    final hit = _mediaCache[sid];
    if (hit != null) return hit;
    final path = s['media_path'] as String?;
    if (path == null) return null;
    final key = await statusKey(s);
    if (key == null) return null;
    final data = await MediaService.download(path);
    final plain = await E2eService.decryptBytes(key, sid, data);
    if (plain != null) _mediaCache[sid] = plain;
    return plain;
  }

  /// تسجيل مشاهدة (صامتة: تكرارها يرفضه المفتاح الأساسي)
  static Future<void> markViewed(String statusId) async {
    try {
      await supabase.from('status_views').insert({
        'status_id': statusId,
        'viewer_id': supabase.auth.currentUser!.id,
      });
    } catch (_) {}
  }

  /// من شاهد حالة من حالاتي (للصاحب فقط)
  static Future<List<Map<String, dynamic>>> viewers(String statusId) async {
    final rows = await supabase
        .from('status_views')
        .select('viewer_id, viewed_at, profiles(display_name, username, avatar_url)')
        .eq('status_id', statusId)
        .order('viewed_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// حذف حالة من حالاتي (التتالي يحذف الأظرف والمشاهدات، والوسيط يذهب لسلة التنظيف)
  static Future<void> delete(String statusId) async {
    _keyCache.remove(statusId);
    _textCache.remove(statusId);
    _mediaCache.remove(statusId);
    await supabase.from('statuses').delete().eq('id', statusId);
  }

  // ---------- دوال نقية (قابلة للاختبار) ----------

  /// تجميع التغذية حسب صاحبها: حالتي أولاً، ثم أصحاب بأحدث حالاتهم.
  /// كل مجموعة: {author_id, author_name, author_avatar, is_me, all_viewed, statuses}
  /// والحالات داخل المجموعة بأحدث نشر أولاً.
  static List<Map<String, dynamic>> groupByAuthor(
      List<Map<String, dynamic>> rows, String meId) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final a = (r['author_id'] ?? r['user_id']) as String?;
      if (a == null) continue;
      (groups[a] ??= []).add(r);
    }
    final out = <Map<String, dynamic>>[];
    for (final entry in groups.entries) {
      final sts = entry.value
        ..sort((a, b) => DateTime.parse(b['created_at'] as String)
            .compareTo(DateTime.parse(a['created_at'] as String)));
      final isMe = entry.key == meId;
      final allViewed = isMe ||
          sts.every((s) => s['viewed'] == true);
      out.add({
        'author_id': entry.key,
        'author_name': (sts.first['author_name'] ?? 'مستخدم') as String,
        'author_avatar': sts.first['author_avatar'] as String?,
        'is_me': isMe,
        'all_viewed': allViewed,
        'statuses': sts,
      });
    }
    out.sort((a, b) {
      if (a['is_me'] != b['is_me']) return (b['is_me'] as bool) ? 1 : -1;
      final ta = DateTime.parse((a['statuses'].first)['created_at'] as String);
      final tb = DateTime.parse((b['statuses'].first)['created_at'] as String);
      return tb.compareTo(ta);
    });
    return out;
  }

  /// عمر الحالة بنص عربي مختصر: «الآن»، «قبل ٥ د»، «قبل ٣ س»، ثم يوم/شهر
  static String ageText(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    return '${d.day}/${d.month}';
  }
}
