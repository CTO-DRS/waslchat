import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

/// التشفير بين الطرفين — المرحلتان 1 و2: المحادثات الخاصة والمجموعات الخاصة
///
/// - زوج هوية X25519 لكل جهاز؛ الخاص لا يخرج من الجهاز (flutter_secure_storage).
/// - المفتاح العام يُنشر في profiles.identity_public_key مع بصمة قصيرة key_fp.
/// - مفتاح المحادثة يُشتق عند الطرفين معاً:
///   HKDF-SHA256( X25519(خاصي، عامُ الآخر) , salt = conversation_id, info = 'wasl-dm-v1' )
/// - الرسائل النصية: AES-256-GCM بصيغة
///   "v1.<nonce b64>.<ciphertext b64>.<mac b64>" مع AAD = conversation_id
///   (يمنع نقل نص مشفّر بين محادثات مختلفة).
/// - الوسائط: ملف ثنائي = nonce(12بايت) + ciphertext + mac(16بايت) بامتداد .enc.bin
/// - الرسائل القديمة (بدون بادئة v1.) تُعرض كما هي — توافق رجعي كامل.
///
/// المرحلة 2 — المجموعات الخاصة:
/// - مفتاح مجموعة عشوائي 32B يثبّته مؤسس المجموعة أول مرة (دالة RPC بقفل استشاري
///   تمنع تثبيت مفتاحين متنافسين)، ويُغلَّف لكل عضو بـ HKDF(X25519(المُغلّف↔العضو)).
/// - الأظرفة في conversation_key_envelopes (ظرف لكل عضو، wrapped_by يسجّل المُغلّف).
/// - من يملك المفتاح يغلّفه تلقائياً لأعضاء بلا ظرف (انضمام لاحق/تقصّر سابق).
/// - فشل فك رسالة مجموعة يعيد جلب الظرف مرة واحدة (شفاء بعد إعادة تثبيت).
///
/// النسخة الاحتياطية: المفتاح الخاص يُشفَّر بكلمة سر (PBKDF2-SHA256 + AES-GCM) ويُخزَّن في
/// e2e_key_backups، فيستعيده الجهاز الجديد. حدود موثّقة: لا سرّية تقدّم، والقنوات/غرف المجتمعات غير مشفّرة، والخروج من مجموعة لا يسحب المفتاح السابق.
class E2eService {
  E2eService._();

  static const _infoDm = 'wasl-dm-v1';
  static const _infoGroup = 'wasl-group-v1';
  static const _privKeyStoreKey = 'e2e_identity_priv_v1';
  static const _plainMaxBytes = 2900; // يبقي النص المشفّر داخل قيد messages (4000 حرف)

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _storage = FlutterSecureStorage();

  static final Map<String, SimplePublicKey> _pubCache = {};
  static final Map<String, SecretKey> _dmKeyCache = {};
  static final Map<String, SecretKey> _groupKeyCache = {};
  static final Map<String, String> _previewCache = {};
  static SimpleKeyPair? _myPair;

  // ---------- الحالة ----------

  /// هل النص مشفّر بصيغة v1؟
  static bool isEncrypted(String content) =>
      content.startsWith('v1.') && '.'.allMatches(content).length >= 3;

  /// هل مسار الوسيط مشفّر؟ (نخزّنه بامتداد .enc.bin)
  static bool isEncryptedPath(String path) => path.endsWith('.enc.bin');

  /// هل النص الصريح داخل حد الطول قبل التشفير؟
  static bool withinPlainLimit(String text) => utf8.encode(text).length <= _plainMaxBytes;

  // ---------- الهوية والنسخة الاحتياطية ----------

  static const _backupIterations = 310000;
  static const _peerPubPrefix = 'e2e_peer_pub_';
  static const _groupKeyPrefix = 'e2e_group_key_';

  /// true بعد التأكد أن مفتاح هذا الجهاز هو المفتاح المنشور للحساب
  static bool _ready = false;
  static bool get isReady => _ready;

  /// مستخدمون تغيّر مفتاحهم العام منذ آخر مرة رأيناه (تنبيه في المحادثة)
  static final Set<String> _changedPeers = {};
  static bool peerKeyChanged(String userId) => _changedPeers.contains(userId);

  static Future<SimpleKeyPair> _loadMyPair() async {
    final cached = _myPair;
    if (cached != null) return cached;
    final stored = await _storage.read(key: _privKeyStoreKey);
    if (stored == null) throw StateError('no identity key');
    final pair = await _x25519.newKeyPairFromSeed(base64Decode(stored));
    _myPair = pair;
    return pair;
  }

  static Future<String> _myPubB64() async {
    final pub = await (await _loadMyPair()).extractPublicKey();
    return base64Encode(pub.bytes);
  }

  static Future<void> _publishMyKey() async {
    final uid = supabase.auth.currentUser!.id;
    final pub = await (await _loadMyPair()).extractPublicKey();
    await supabase.from('profiles').update({
      'identity_public_key': base64Encode(pub.bytes),
      'key_fp': await fingerprint(pub.bytes),
    }).eq('id', uid);
  }

  static void _clearKeyCaches() {
    _myPair = null;
    _dmKeyCache.clear();
    _groupKeyCache.clear();
    _previewCache.clear();
  }

  /// بصمة قصيرة للمفتاح العام (16 hex)
  static Future<String> fingerprint(List<int> pubBytes) async {
    final h = await Sha256().hash(pubBytes);
    return h.bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// يفحص حالة مفاتيح هذا الجهاز مقابل الحساب — لا يستبدل مفتاحاً منشوراً أبداً بصمت.
  static Future<E2eKeyState> checkKeys() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return E2eKeyState.error;
      final row = await supabase
          .from('profiles')
          .select('identity_public_key')
          .eq('id', uid)
          .maybeSingle();
      final published = row?['identity_public_key'] as String?;
      final backup = await supabase
          .from('e2e_key_backups')
          .select('user_id')
          .eq('user_id', uid)
          .maybeSingle();
      final hasBackup = backup != null;
      final local = await _storage.read(key: _privKeyStoreKey);

      if (local == null && (published == null || published.isEmpty)) {
        // أول جهاز للحساب: نولّد المفتاح وننشره
        final made = await _x25519.newKeyPair();
        await _storage.write(
            key: _privKeyStoreKey, value: base64Encode(await made.extractPrivateKeyBytes()));
        _clearKeyCaches();
        await _publishMyKey();
        _ready = true;
        return E2eKeyState.needsBackup;
      }
      if (local != null) {
        _clearKeyCaches();
        final mine = await _myPubB64();
        if (published == null || published.isEmpty) {
          await _publishMyKey();
          _ready = true;
          return hasBackup ? E2eKeyState.ready : E2eKeyState.needsBackup;
        }
        if (published == mine) {
          _ready = true;
          return hasBackup ? E2eKeyState.ready : E2eKeyState.needsBackup;
        }
      }
      // الحساب له مفتاح منشور غير الموجود على هذا الجهاز (جهاز جديد / إعادة تثبيت)
      _ready = false;
      return hasBackup ? E2eKeyState.needsRestore : E2eKeyState.needsReset;
    } catch (_) {
      return E2eKeyState.error;
    }
  }

  static Future<SecretKey> _backupKek(String passphrase, List<int> salt, int iterations) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  /// يشفّر المفتاح الخاص بكلمة سر يختارها المستخدم ويخزّنه في الحساب.
  /// الخادم لا يرى كلمة السر ولا المفتاح.
  static Future<void> createBackup(String passphrase) async {
    final uid = supabase.auth.currentUser!.id;
    final seed = base64Decode((await _storage.read(key: _privKeyStoreKey))!);
    final salt = _aes.newNonce() + _aes.newNonce(); // 24 بايت عشوائية
    final kek = await _backupKek(passphrase, salt, _backupIterations);
    final box = await _aes.encrypt(seed,
        secretKey: kek, nonce: _aes.newNonce(), aad: utf8.encode(uid));
    await supabase.from('e2e_key_backups').upsert({
      'user_id': uid,
      'salt': base64Encode(salt),
      'iterations': _backupIterations,
      'wrapped': 'v1.${base64Encode(box.nonce)}.'
          '${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// يستعيد المفتاح من النسخة الاحتياطية. false إن كانت كلمة السر خاطئة.
  static Future<bool> restoreBackup(String passphrase) async {
    final uid = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('e2e_key_backups')
        .select('salt, iterations, wrapped')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return false;
    try {
      final kek = await _backupKek(
          passphrase, base64Decode(row['salt'] as String), row['iterations'] as int);
      final p = (row['wrapped'] as String).split('.');
      final seed = await _aes.decrypt(
        SecretBox(base64Decode(p[2]), nonce: base64Decode(p[1]), mac: Mac(base64Decode(p[3]))),
        secretKey: kek,
        aad: utf8.encode(uid),
      );
      await _storage.write(key: _privKeyStoreKey, value: base64Encode(seed));
      _clearKeyCaches();
      final pub = await _myPubB64();
      final prof = await supabase
          .from('profiles')
          .select('identity_public_key')
          .eq('id', uid)
          .maybeSingle();
      if (prof?['identity_public_key'] != pub) await _publishMyKey();
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// مفتاح جديد كلياً (لا نسخة احتياطية أو نُسيت كلمة السر): الرسائل المشفّرة القديمة لن تُقرأ.
  static Future<void> resetKeys(String passphrase) async {
    final made = await _x25519.newKeyPair();
    await _storage.write(
        key: _privKeyStoreKey, value: base64Encode(await made.extractPrivateKeyBytes()));
    _clearKeyCaches();
    await _publishMyKey();
    // أظرفتي القديمة لا تُفك بالمفتاح الجديد، والأظرفة التي غلّفتُها لغيري تعتمد على مفتاحي القديم:
    // نحذفها ليعيد أعضاء يملكون المفتاح تغليفه تلقائياً.
    await supabase.rpc('e2e_drop_my_envelopes');
    await createBackup(passphrase);
    _ready = true;
  }

  /// عند تسجيل الخروج: مسح المفاتيح المحفوظة على الجهاز (تُستعاد بكلمة سر النسخة الاحتياطية)
  static Future<void> wipeLocal() async {
    await _storage.deleteAll();
    _clearKeyCaches();
    _pubCache.clear();
    _changedPeers.clear();
    _ready = false;
  }

  // ---------- رمز الأمان ----------

  /// رقم أمان من 60 خانة (12 مجموعة × 5) يتطابق عند الطرفين إن لم يُستبدل أي مفتاح.
  static Future<String?> safetyNumber(String otherUserId) async {
    if (!_ready) return null;
    _pubCache.remove(otherUserId);
    final other = await _publicKeyOf(otherUserId);
    if (other == null) return null;
    final mine = await (await _loadMyPair()).extractPublicKey();
    final keys = [base64Encode(mine.bytes), base64Encode(other.bytes)]..sort();
    final h = (await Sha512().hash(utf8.encode('wasl-safety-v1|${keys[0]}|${keys[1]}'))).bytes;
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      var n = 0;
      for (var j = 0; j < 5; j++) {
        n = (n * 256 + h[i * 5 + j]) % 100000;
      }
      groups.add(n.toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  /// يعتمد المفتاح الحالي للطرف الآخر بعد أن تحقق المستخدم منه
  static void acknowledgePeerKey(String userId) => _changedPeers.remove(userId);

  // ---------- مفاتيح المحادثة ----------

  static Future<SimplePublicKey?> _publicKeyOf(String userId) async {
    final hit = _pubCache[userId];
    if (hit != null) return hit;
    final row = await supabase
        .from('profiles')
        .select('identity_public_key')
        .eq('id', userId)
        .maybeSingle();
    final v = row?['identity_public_key'] as String?;
    if (v == null || v.isEmpty) return null;
    // تنبيه عند تغيّر مفتاح طرف رأيناه سابقاً
    final seen = await _storage.read(key: '$_peerPubPrefix$userId');
    if (seen != null && seen != v) _changedPeers.add(userId);
    if (seen != v) await _storage.write(key: '$_peerPubPrefix$userId', value: v);
    final pub = SimplePublicKey(base64Decode(v), type: KeyPairType.x25519);
    _pubCache[userId] = pub;
    return pub;
  }

  /// مفتاح محادثة خاصة مشترك — نفس القيمة عند الطرفين. null إن لم تكن المفاتيح جاهزة.
  static Future<SecretKey?> dmKey(String conversationId, String otherUserId) async {
    if (!_ready) return null;
    final cacheKey = '$conversationId:$otherUserId';
    final hit = _dmKeyCache[cacheKey];
    if (hit != null) return hit;
    final other = await _publicKeyOf(otherUserId);
    if (other == null) return null;
    final my = await _loadMyPair();
    final shared = await _x25519.sharedSecretKey(keyPair: my, remotePublicKey: other);
    final derived = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(conversationId),
      info: utf8.encode(_infoDm),
    );
    _dmKeyCache[cacheKey] = derived;
    return derived;
  }

  // ---------- النص ----------

  static Future<String> encryptText(
      SecretKey key, String conversationId, String plain) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plain),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(conversationId),
    );
    return 'v1.${base64Encode(box.nonce)}.'
        '${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}';
  }

  /// يفك v1... ويعيد null عند الفشل. النص القديم (غير المشفّر) يُعاد كما هو.
  static Future<String?> decryptText(
      SecretKey key, String conversationId, String content) async {
    if (!isEncrypted(content)) return content;
    try {
      final p = content.split('.');
      final box = SecretBox(
        base64Decode(p[2]),
        nonce: base64Decode(p[1]),
        mac: Mac(base64Decode(p[3])),
      );
      final plain =
          await _aes.decrypt(box, secretKey: key, aad: utf8.encode(conversationId));
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  // ---------- الوسائط ----------

  static Future<Uint8List> encryptBytes(
      SecretKey key, String conversationId, Uint8List bytes) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(bytes,
        secretKey: key, nonce: nonce, aad: utf8.encode(conversationId));
    final out = BytesBuilder(copy: false);
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  static Future<Uint8List?> decryptBytes(
      SecretKey key, String conversationId, Uint8List data) async {
    try {
      if (data.length < 12 + 16) return null;
      final nonce = data.sublist(0, 12);
      final mac = data.sublist(data.length - 16);
      final ct = data.sublist(12, data.length - 16);
      final plain = await _aes.decrypt(
        SecretBox(ct, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(conversationId),
      );
      return Uint8List.fromList(plain);
    } catch (_) {
      return null;
    }
  }

  // ---------- معاينة قائمة المحادثات ----------

  /// يفك سطر المعاينة (مع ذاكرة مؤقتة). النص القديم يُعاد كما هو، والفشل يعيد نصاً عاماً.
  static Future<String> preview({
    required String conversationId,
    required String? otherId,
    required String? content,
  }) async {
    final raw = content ?? '';
    if (!isEncrypted(raw)) return raw;
    final hit = _previewCache[raw];
    if (hit != null) return hit;
    if (otherId == null) return '🔒 رسالة مشفرة';
    final key = await dmKey(conversationId, otherId);
    if (key == null) return '🔒 رسالة مشفرة';
    final plain = await decryptText(key, conversationId, raw);
    final out = plain ?? '🔒 رسالة مشفرة';
    if (_previewCache.length > 300) _previewCache.clear();
    _previewCache[raw] = out;
    return out;
  }

  /// معاينة سطر مجموعة: نفس المنطق لكن بمفتاح المجموعة
  static Future<String> previewGroup({
    required String conversationId,
    required String? content,
  }) async {
    final raw = content ?? '';
    if (!isEncrypted(raw)) return raw;
    final hit = _previewCache[raw];
    if (hit != null) return hit;
    final key = await groupKey(conversationId);
    if (key == null) return '🔒 رسالة مشفرة';
    final plain = await decryptText(key, conversationId, raw);
    final out = plain ?? '🔒 رسالة مشفرة';
    if (_previewCache.length > 300) _previewCache.clear();
    _previewCache[raw] = out;
    return out;
  }

  // ---------- المرحلة 2: مفاتيح المجموعات ----------

  /// يغلف مفتاح المجموعة لعضو بـ HKDF(X25519(المُغلِّف↔العضو)) — دالة نقية (قابلة للاختبار)
  static Future<String> wrapGroupKey({
    required SecretKey groupKey,
    required String conversationId,
    required SimpleKeyPair wrapperPair,
    required SimplePublicKey memberPub,
  }) async {
    final shared =
        await _x25519.sharedSecretKey(keyPair: wrapperPair, remotePublicKey: memberPub);
    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(conversationId),
      info: utf8.encode(_infoGroup),
    );
    final kb = await groupKey.extractBytes();
    final box = await _aes.encrypt(kb,
        secretKey: kek, nonce: _aes.newNonce(), aad: utf8.encode(conversationId));
    return 'v1.${base64Encode(box.nonce)}.'
        '${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}';
  }

  /// يفك ظرفاً مغلقاً ويعيد مفتاح المجموعة (null عند الفشل) — دالة نقية
  static Future<SecretKey?> unwrapGroupKey({
    required String wrapped,
    required String conversationId,
    required SimpleKeyPair myPair,
    required SimplePublicKey wrapperPub,
  }) async {
    if (!isEncrypted(wrapped)) return null;
    try {
      final shared =
          await _x25519.sharedSecretKey(keyPair: myPair, remotePublicKey: wrapperPub);
      final kek = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode(conversationId),
        info: utf8.encode(_infoGroup),
      );
      final p = wrapped.split('.');
      final kb = await _aes.decrypt(
        SecretBox(base64Decode(p[2]),
            nonce: base64Decode(p[1]), mac: Mac(base64Decode(p[3]))),
        secretKey: kek,
        aad: utf8.encode(conversationId),
      );
      return SecretKeyData(kb);
    } catch (_) {
      return null;
    }
  }

  /// ظرفي في محادثة: (المغلَّف، مُغلِّفي)
  static Future<(String, String)?> _fetchMyEnvelope(String convId, String me) async {
    final row = await supabase
        .from('conversation_key_envelopes')
        .select('wrapped_key, wrapped_by')
        .eq('conversation_id', convId)
        .eq('user_id', me)
        .maybeSingle();
    if (row == null) return null;
    final w = row['wrapped_key'] as String?;
    final by = row['wrapped_by'] as String?;
    if (w == null || by == null || w.isEmpty) return null;
    return (w, by);
  }

  static Future<SecretKey?> _unwrapEnvelope(String convId, (String, String) env) async {
    final wrapperPub = await _publicKeyOf(env.$2);
    if (wrapperPub == null) return null;
    final my = await _loadMyPair();
    return unwrapGroupKey(
        wrapped: env.$1, conversationId: convId, myPair: my, wrapperPub: wrapperPub);
  }

  static Future<List<String>> _memberIds(String convId) async {
    final rows = await supabase
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', convId);
    return rows.map((r) => r['user_id'] as String).toList();
  }

  /// من يملك المفتاح يغلّفه لمن بلا ظرف (انضمام لاحق) — صامتة دائماً
  static Future<void> _topUpForMissingMembers(String convId, SecretKey key) async {
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;
      final members = (await _memberIds(convId)).toSet();
      final envRows = await supabase
          .from('conversation_key_envelopes')
          .select('user_id')
          .eq('conversation_id', convId);
      final covered = envRows.map((r) => r['user_id'] as String).toSet();
      final missing = members.difference(covered);
      if (missing.isEmpty) return;
      final my = await _loadMyPair();
      final payload = <Map<String, dynamic>>[];
      for (final id in missing) {
        final pub = await _publicKeyOf(id);
        if (pub == null) continue; // بلا مفاتيح بعد — سيُغلَّف له بعد تحديث تطبيقه
        payload.add({
          'user_id': id,
          'wrapped_key': await wrapGroupKey(
              groupKey: key,
              conversationId: convId,
              wrapperPair: my,
              memberPub: pub),
        });
      }
      if (payload.isEmpty) return;
      await supabase.rpc('e2e_wrap_for_members',
          params: {'p_conv': convId, 'p_envelopes': payload});
    } catch (_) {}
  }

  static Future<void> _persistGroupKey(String convId, SecretKey key) async {
    await _storage.write(
        key: '$_groupKeyPrefix$convId', value: base64Encode(await key.extractBytes()));
  }

  static Future<SecretKey?> _localGroupKey(String convId) async {
    final v = await _storage.read(key: '$_groupKeyPrefix$convId');
    return v == null ? null : SecretKeyData(base64Decode(v));
  }

  /// مفتاح مجموعة خاصة.
  /// الترتيب: الذاكرة ← ظرفي من الخادم ← نسخة محفوظة على الجهاز ← تثبيت أول (فقط إن لم يوجد أي ظرف).
  /// لا يستبدل أحدٌ مفتاحَ مجموعة قائماً أبداً؛ العضو بلا ظرف ينتظر عضواً يملك المفتاح ليغلّفه له.
  static Future<SecretKey?> groupKey(String conversationId) async {
    if (!_ready) return null;
    final hit = _groupKeyCache[conversationId];
    if (hit != null) return hit;
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return null;

      // 1) ظرفي الحالي
      final mine = await _fetchMyEnvelope(conversationId, me);
      if (mine != null) {
        final key = await _unwrapEnvelope(conversationId, mine);
        if (key != null) {
          _groupKeyCache[conversationId] = key;
          await _persistGroupKey(conversationId, key);
          unawaited(_topUpForMissingMembers(conversationId, key));
          return key;
        }
      }

      // 2) نسخة محفوظة محلياً (تبقى صالحة حتى لو تغيّر مفتاح من غلّف لي)
      final local = await _localGroupKey(conversationId);
      if (local != null) {
        _groupKeyCache[conversationId] = local;
        unawaited(_topUpForMissingMembers(conversationId, local));
        return local;
      }

      // 3) هل للمجموعة مفتاح أصلاً؟ إن وُجد أي ظرف فلا تثبيت: ننتظر عضواً يغلّف لنا
      final envAny = await supabase
          .from('conversation_key_envelopes')
          .select('user_id')
          .eq('conversation_id', conversationId)
          .limit(1);
      if (envAny.isNotEmpty) return null;

      // 4) لا مفتاح بعد: المؤسس يثبّت (أو أي عضو في مجموعة قديمة بلا مؤسس)
      final conv = await supabase
          .from('conversations')
          .select('created_by')
          .eq('id', conversationId)
          .maybeSingle();
      final founder = conv?['created_by'] as String?;
      if (founder != null && founder != me) return null;

      final members = await _memberIds(conversationId);
      if (!members.contains(me) || members.length < 2) return null;
      final my = await _loadMyPair();
      final myPub = await my.extractPublicKey();
      final pubs = <String, SimplePublicKey>{};
      for (final id in members) {
        final p = id == me ? myPub : await _publicKeyOf(id);
        if (p != null) pubs[id] = p; // من بلا مفتاح يُغلَّف له لاحقاً تلقائياً
      }

      final key = await _aes.newSecretKey();
      final payload = <Map<String, dynamic>>[];
      for (final e in pubs.entries) {
        payload.add({
          'user_id': e.key,
          'wrapped_key': await wrapGroupKey(
              groupKey: key,
              conversationId: conversationId,
              wrapperPair: my,
              memberPub: e.value),
        });
      }
      await supabase.rpc('e2e_set_group_key',
          params: {'p_conv': conversationId, 'p_envelopes': payload});

      // 5) الحقيقة النهائية من القاعدة (إن سبقنا متسابق فمفتاحه هو المعتمد)
      final fresh = await _fetchMyEnvelope(conversationId, me);
      if (fresh == null) return null;
      final truth = await _unwrapEnvelope(conversationId, fresh);
      if (truth == null) return null;
      _groupKeyCache[conversationId] = truth;
      await _persistGroupKey(conversationId, truth);
      return truth;
    } catch (_) {
      return null;
    }
  }

  /// مسح ذاكرة مفتاح مجموعة (عند فشل فك رسالة — يُعاد جلب الظرف)
  static void invalidateGroupKey(String conversationId) {
    _groupKeyCache.remove(conversationId);
  }

  /// تثبيت مبكر لمفتاح مجموعة عند إنشائها (ناريَ ونسيان — لا يعطّل الواجهة)
  static void initGroupKey(String conversationId) {
    unawaited(groupKey(conversationId));
  }
}

/// حالة مفاتيح التشفير على هذا الجهاز
enum E2eKeyState {
  /// جاهز ومعه نسخة احتياطية
  ready,

  /// جاهز لكن بلا نسخة احتياطية (يُطلب من المستخدم إنشاؤها)
  needsBackup,

  /// للحساب مفتاح منشور، وتوجد نسخة احتياطية: يستعيدها بكلمة السر
  needsRestore,

  /// للحساب مفتاح منشور بلا نسخة احتياطية: لا بد من مفتاح جديد (الرسائل القديمة لن تُقرأ)
  needsReset,

  error,
}
