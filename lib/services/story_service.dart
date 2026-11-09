import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'e2e_service.dart';

/// الحالات/القصص (24 ساعة) المشفّرة لجهات الاتصال — بند المرحلة 1 من خارطة الطريق.
///
/// - مفتاح عشوائي AES-256 لكل حالة؛ الوسائط (E2eService.encryptBytes) والتعليق
///   (E2eService.encryptText) يُشفَّران به ومع AAD = معرّف الحالة (لا يمكن نقل
///   محتوى مشفّر بين حالتين).
/// - مفتاح الحالة يُغلَّف لكل جهة اتصال بأسلوب أظرف المجموعات (007):
///     HKDF( X25519(الناشر↔جهة الاتصال), salt = storyId, info = 'wasl-story-v1' )
///   ويُغلَّف للناشر نفسه أيضاً كي تُقرأ حالاته من أي جهاز آخر له.
/// - «جهات الاتصال» يحددها الخادم (are_contacts في 019): من تربطك به محادثة فردية
///   قائمة. جهة بلا مفتاح عام منشور تُتخطى ولا ترى الحالة (نفس سلوك المجموعات).
/// - الانتهاء بعد 24 ساعة يفرضه الخادم (مشغّل stories_force_ttl) — العميل يعرض
///   المتبقي فقط ولا يمكنه إطالته.
/// - من تراه الخادم بصراحة: الناشر والأوقات والنوع وحجم الملف المشفّر والمشاهدون —
///   موثّق في docs/TRANSPARENCY.md.
class StoryService {
  StoryService._();

  static const bucket = 'stories';
  static const _info = 'wasl-story-v1';
  static const maxCaptionChars = 700; // نص الحالة/التعليق قبل التشفير
  static const maxBytes = 24 * 1024 * 1024; // نفس حد وسائط المحادثات

  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final X25519 _x25519 = X25519();

  // ذاكرة مفاتيح الحالات المفكوكة (تُنظَّف عند تجاوز الحد)
  static final Map<String, SecretKey> _keyCache = {};

  // ---------- الغلاف النقي (قابل للاختبار بلا شبكة) ----------

  /// يغلّف مفتاح حالة لجهة اتصال: AES-GCM(HKDF(X25519(الناشر↔الجهة)))، AAD = storyId
  static Future<String> wrapStoryKey({
    required SecretKey storyKey,
    required String storyId,
    required SimpleKeyPair publisherPair,
    required SimplePublicKey contactPub,
  }) async {
    final shared =
        await _x25519.sharedSecretKey(keyPair: publisherPair, remotePublicKey: contactPub);
    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(storyId),
      info: utf8.encode(_info),
    );
    final kb = await storyKey.extractBytes();
    final box = await _aes.encrypt(kb,
        secretKey: kek, nonce: _aes.newNonce(), aad: utf8.encode(storyId));
    return 'v1.${base64Encode(box.nonce)}.'
        '${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}';
  }

  /// يفك ظرفاً ويعيد مفتاح الحالة (null عند الفشل: مفتاح خاطئ أو عبث)
  static Future<SecretKey?> unwrapStoryKey({
    required String wrapped,
    required String storyId,
    required SimpleKeyPair myPair,
    required SimplePublicKey publisherPub,
  }) async {
    if (!E2eService.isEncrypted(wrapped)) return null;
    try {
      final shared =
          await _x25519.sharedSecretKey(keyPair: myPair, remotePublicKey: publisherPub);
      final kek = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode(storyId),
        info: utf8.encode(_info),
      );
      final p = wrapped.split('.');
      final kb = await _aes.decrypt(
        SecretBox(base64Decode(p[2]),
            nonce: base64Decode(p[1]), mac: Mac(base64Decode(p[3]))),
        secretKey: kek,
        aad: utf8.encode(storyId),
      );
      return SecretKeyData(kb);
    } catch (_) {
      return null;
    }
  }

  // ---------- النشر ----------

  /// ينشر حالة جديدة ويعيد معرّفها. type: 'image' | 'video' | 'text'.
  /// ترتيب الأمان: صف القاعدة أولاً (بمسار محسوب) ثم الرفع — فإذا فشل الرفع
  /// يُحذف الصف فيسجل مساره في media_trash بلا ملف يتيم يبقى في التخزين.
  static Future<String> publish({
    required String type,
    Uint8List? bytes,
    String? caption,
    String? bg,
  }) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) throw StateError('not authenticated');
    if (!E2eService.isReady) throw StateError('e2e not ready');
    final cap = (caption ?? '').trim();
    if (type == 'text' && cap.isEmpty) throw StateError('النص مطلوب');
    if (cap.runes.length > maxCaptionChars) throw StateError('النص طويل جداً');
    if (type != 'text' && bytes == null) throw StateError('الملف مطلوب');
    if (bytes != null && bytes.length > maxBytes) throw StateError('الحجم أكبر من 24 ميغابايت');

    final storyId = uuidV4();
    final key = await _aes.newSecretKey();
    final captionEnc =
        cap.isEmpty ? null : await E2eService.encryptText(key, storyId, cap);

    String? mediaPath;
    if (type != 'text') {
      mediaPath = '$me/$storyId.enc.bin';
      await supabase.from('stories').insert({
        'id': storyId,
        'user_id': me,
        'type': type,
        'media_path': mediaPath,
        if (captionEnc != null) 'caption': captionEnc,
      });
      try {
        final enc = await E2eService.encryptBytes(key, storyId, bytes);
        await supabase.storage.from(bucket).uploadBinary(
              mediaPath,
              enc,
              fileOptions: FileOptions(contentType: 'application/octet-stream'),
            );
      } catch (_) {
        await supabase.from('stories').delete().eq('id', storyId);
        rethrow;
      }
    } else {
      await supabase.from('stories').insert({
        'id': storyId,
        'user_id': me,
        'type': type,
        'caption': captionEnc,
        'bg': bg ?? 'indigo',
      });
    }

    unawaited(_wrapForContacts(storyId, key));
    return storyId;
  }

  /// يغلّف مفتاح الحالة للناشر نفسه أولاً (كي تُقرأ حالاته من أي جهاز)، ثم لجهات
  /// اتصاله ذات المفاتيح المنشورة. فشل تغليف جهة لا يلغي النشر.
  static Future<void> _wrapForContacts(String storyId, SecretKey key) async {
    try {
      final me = supabase.auth.currentUser!.id;
      final pair = await E2eService.identityPair();
      final myPub = await pair.extractPublicKey();
      Future<String> wrapFor(SimplePublicKey pub) => wrapStoryKey(
          storyKey: key, storyId: storyId, publisherPair: pair, contactPub: pub);

      // 1) ظرفي أنا (جهازي الحالي يفك عبره أيضاً — مصدر الحقيقة موحّد)
      await supabase.from('story_key_envelopes').upsert({
        'story_id': storyId,
        'user_id': me,
        'wrapped_key': await wrapFor(myPub),
        'wrapped_by': me,
      }, onConflict: 'story_id,user_id');

      // 2) جهات الاتصال (دفعة واحدة؛ من بلا مفتاح عام يُتخطى)
      final rows = await supabase.rpc('my_contacts');
      final payload = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(rows as List)) {
        final uid = r['id'] as String;
        if (uid == me) continue;
        final pub = await E2eService.publicKeyOf(uid);
        if (pub == null) continue;
        payload.add({
          'story_id': storyId,
          'user_id': uid,
          'wrapped_key': await wrapFor(pub),
          'wrapped_by': me,
        });
      }
      if (payload.isNotEmpty) {
        await supabase
            .from('story_key_envelopes')
            .upsert(payload, onConflict: 'story_id,user_id');
      }
    } catch (_) {
      // الظرف الذاتي مضمون أعلاه؛ فشل الدفعات الجماعية يُترك للنشر القادم
    }
  }

  // ---------- القراءة ----------

  /// حالات جهات الاتصال النشطة (كل سطر حالة، مع ظرفي أنا)
  static Future<List<StoryItem>> feed() async {
    try {
      final rows = await supabase.rpc('stories_feed');
      return List<Map<String, dynamic>>.from(rows as List)
          .map((r) => StoryItem.fromRow(r, mine: false))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// حالاتي النشطة مع عدد المشاهدين
  static Future<List<StoryItem>> mine() async {
    try {
      final rows = await supabase.rpc('my_stories');
      return List<Map<String, dynamic>>.from(rows as List)
          .map((r) => StoryItem.fromRow(r, mine: true))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// عدد جهات الاتصال الذين ستظهر لهم الحالة (لمعاينة المنشئ)
  static Future<int> contactsCount() async {
    try {
      final rows = await supabase.rpc('my_contacts');
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// مفتاح حالة (ظرفي ← الذاكرة). null إن تعذّر الفك.
  static Future<SecretKey?> storyKey(StoryItem s) async {
    final hit = _keyCache[s.id];
    if (hit != null) return hit;
    if (s.wrappedKey.isEmpty) return null;
    try {
      final myPair = await E2eService.identityPair();
      final authorPub = await E2eService.publicKeyOf(s.authorId);
      if (authorPub == null) return null;
      final key = await unwrapStoryKey(
          wrapped: s.wrappedKey, storyId: s.id, myPair: myPair, publisherPub: authorPub);
      if (key != null) {
        if (_keyCache.length > 200) _keyCache.clear();
        _keyCache[s.id] = key;
      }
      return key;
    } catch (_) {
      return null;
    }
  }

  /// يفك تعليق/نص الحالة. يعيده كما لو كان صريحاً غير مشفّر (توافق)، و'' عند الفشل.
  static Future<String> caption(StoryItem s) async {
    final raw = s.caption;
    if (raw == null || raw.isEmpty) return '';
    if (!E2eService.isEncrypted(raw)) return raw;
    final key = await storyKey(s);
    if (key == null) return '';
    return await E2eService.decryptText(key, s.id, raw) ?? '';
  }

  /// ينزّل وسيط الحالة ويفكه. null عند الفشل.
  static Future<Uint8List?> loadMedia(StoryItem s) async {
    if (s.mediaPath == null) return null;
    try {
      final key = await storyKey(s);
      if (key == null) return null;
      final data = await supabase.storage.from(bucket).download(s.mediaPath!);
      return await E2eService.decryptBytes(key, s.id, data);
    } catch (_) {
      return null;
    }
  }

  /// يسجّل مشاهدة (تُتجاهل إن سبقت) — الخادم يفرض أن الحالة نشطة وأن بينك اتصالاً
  static Future<void> markViewed(String storyId) async {
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;
      await supabase.from('story_views').upsert({
        'story_id': storyId,
        'viewer_id': me,
      }, onConflict: 'story_id,viewer_id', ignoreDuplicates: true);
    } catch (_) {}
  }

  /// مشاهدو حالة من حالاتي (الاسم والصورة ووقت المشاهدة)
  static Future<List<Map<String, dynamic>>> viewers(String storyId) async {
    try {
      final rows = await supabase.rpc('story_viewers', params: {'p_story': storyId});
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return const [];
    }
  }

  /// حذف حالة من حالاتي (الملف يُحذف من التخزين خلال ساعة عبر media_trash)
  static Future<void> delete(String storyId) async {
    _keyCache.remove(storyId);
    try {
      await supabase.from('stories').delete().eq('id', storyId);
    } catch (_) {}
  }

  // ---------- «تمت المشاهدة» محلياً (للون الحلقة في الشريط) ----------

  static const _seenKey = 'story_seen_ids_v1';
  static final Set<String> _seen = {};
  static bool _seenLoaded = false;

  static Set<String> get seen => _seen;

  static Future<void> loadSeen() async {
    if (_seenLoaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _seen.addAll(p.getStringList(_seenKey) ?? const []);
    } catch (_) {}
    _seenLoaded = true;
  }

  static Future<void> markSeenLocally(String storyId) async {
    _seen.add(storyId);
    try {
      final p = await SharedPreferences.getInstance();
      var list = _seen.toList();
      if (list.length > 500) list = list.sublist(list.length - 500);
      await p.setStringList(_seenKey, list);
    } catch (_) {}
  }

  // ---------- أدوات ----------

  /// UUID v4 من مصدر عشوائي آمن — معرّف الحالة يولّده العميل لأنه AAD التشفير
  static String uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// حالة واحدة جاهزة للعرض (المحتوى يُفك عند الطلب فقط)
class StoryItem {
  StoryItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.type,
    this.mediaPath,
    this.caption,
    this.bg,
    required this.createdAt,
    required this.expiresAt,
    required this.wrappedKey,
    this.mine = false,
    this.views = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final String type; // image | video | text
  final String? mediaPath;
  final String? caption; // مشفّرة — يفكها StoryService.caption
  final String? bg; // خلفية الحالة النصية
  final DateTime createdAt;
  final DateTime expiresAt;
  final String wrappedKey;
  final bool mine;
  final int views; // لحالاتي فقط

  factory StoryItem.fromRow(Map<String, dynamic> r, {required bool mine}) {
    return StoryItem(
      id: r['story_id'] as String,
      authorId: (r['author_id'] ?? r['user_id'] ?? '') as String,
      authorName: ((r['author_name'] ?? '') as String?) ?? '',
      authorAvatar: r['author_avatar'] as String?,
      type: (r['type'] ?? 'text') as String,
      mediaPath: r['media_path'] as String?,
      caption: r['caption'] as String?,
      bg: r['bg'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(r['expires_at'] as String).toLocal(),
      wrappedKey: (r['wrapped_key'] ?? '') as String,
      mine: mine,
      views: (r['views'] as num?)?.toInt() ?? 0,
    );
  }

  /// المتبقي من عمر الحالة
  Duration get remaining =>
      expiresAt.difference(DateTime.now()).isNegative
          ? Duration.zero
          : expiresAt.difference(DateTime.now());
}
