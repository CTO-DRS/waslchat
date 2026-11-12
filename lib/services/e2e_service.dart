import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import 'ratchet.dart';

/// نتائج مسح رمز تحقق QR
enum VerifyScanResult {
  /// تطابق — تم توثيق الطرف على هذا الجهاز
  verified,

  /// الحساب مطابق لكن المفتاح في الرمز مختلف عن المنشور — تحذير احتيال
  mismatch,

  /// الرمز يعود لحساب آخر غير محادثتك
  foreign,

  /// ليس رمز تحقق من وصل شات
  invalid,
}

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
/// المرحلة 2-أ — السرية الأمامية (v2، المحادثات الخاصة فقط):
/// - كل حساب ينشر مفاتيح X25519 أولية «لمرة واحدة» في e2e_prekeys (ترحيل 020)
///   ويضبط profiles.e2e_version = 2؛ من يبدأ يسحب واحداً بـ e2e_claim_prekey
///   (سحب ذري لا يتكرر) ويشتق سرّ X3DH ثم يدير جلسة Double Ratchet محلياً
///   (lib/services/ratchet.dart) — فسرقة مفتاح الهوية لاحقاً لا تكشف الرسائل السابقة.
/// - الصيغة: "v2.<ترويسة b64>.<ciphertext b64>.<mac b64>" وAAD = conv + الترويسة.
/// - من لا يملك الطرف الآخر مفاتيح أولية (تطبيق قديم) يبقى على مسار v1 تلقائياً،
///   والقاعدة: الأصغر معرفاً يبدأ v2 — يمنع سباق بدء مزدوج بلا وساطة.
/// - الوسائط تبقى على مفتاح v1 الثابت في هذا الإصدار (تغليف مفاتيح الوسائط
///   داخل الرسائل المتدرجة متأجل) — موثق في E2EE_PLAN حدود المرحلة.
///
/// المرحلة 2 — المجموعات الخاصة:
/// - مفتاح مجموعة عشوائي 32B يثبّته مؤسس المجموعة أول مرة (دالة RPC بقفل استشاري
///   تمنع تثبيت مفتاحين متنافسين)، ويُغلَّف لكل عضو بـ HKDF(X25519(المُغلّف↔العضو)).
/// - الأظرفة في conversation_key_envelopes (ظرف لكل عضو، wrapped_by يسجّل المُغلّف).
/// - من يملك المفتاح يغلّفه تلقائياً لأعضاء بلا ظرف (انضمام لاحق/تقصّر سابق).
/// - فشل فك رسالة مجموعة يعيد جلب الظرف مرة واحدة (شفاء بعد إعادة تثبيت).
///
/// النسخة الاحتياطية: المفتاح الخاص يُشفَّر بكلمة سر (PBKDF2-SHA256 + AES-GCM) ويُخزَّن في
/// e2e_key_backups، فيستعيده الجهاز الجديد. حدود موثّقة: لا سرّية تقدّم، والقنوات/غرف المجتمعات غير مشفّرة، وعند إزالة عضو أو مغادرته يُدوَّر مفتاح المجموعة (إصدار جديد للأعضاء الباقين فقط).
class E2eService {
  E2eService._();

  static const _infoDm = 'wasl-dm-v1';
  static const _infoGroup = 'wasl-group-v1';
  static const _privKeyStoreKey = 'e2e_identity_priv_v1';
  // 2600 يبقي نص v2 (ترويسة + تشفير + mac) داخل قيد messages (4000 حرف) حتى في
  // أول رسالة (الأثقل ترويسةً)
  static const _plainMaxBytes = 2600;

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

  /// هل النص مشفّر بصيغة v1 أو v2؟
  static bool isEncrypted(String content) {
    if (content.startsWith('v2.')) return content.split('.').length == 4;
    return content.startsWith('v1.') && '.'.allMatches(content).length >= 3;
  }

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
    _verCache.clear();
    _allLoaded.clear();
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
        unawaited(ensurePrekeys());
        return E2eKeyState.needsBackup;
      }
      if (local != null) {
        _clearKeyCaches();
        final mine = await _myPubB64();
        if (published == null || published.isEmpty) {
          await _publishMyKey();
          _ready = true;
          unawaited(ensurePrekeys());
          return hasBackup ? E2eKeyState.ready : E2eKeyState.needsBackup;
        }
        if (published == mine) {
          _ready = true;
          unawaited(ensurePrekeys());
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
      unawaited(ensurePrekeys());
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
    // المفاتيح الأولية القديمة مرتبطة بالهوية المنقرضة: حذفها من الخادم والجهاز
    // مع الجلسات، ثم نشر مخزون جديد بالهوية الجديدة.
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      try {
        await supabase.from('e2e_prekeys').delete().eq('user_id', uid);
      } catch (_) {}
    }
    try {
      final all = await _storage.readAll();
      for (final k in all.keys) {
        if (k.startsWith(_prekeyPrivPrefix) || k.startsWith(_sessionPrefix)) {
          await _storage.delete(key: k);
        }
      }
    } catch (_) {}
    await createBackup(passphrase);
    _ready = true;
    unawaited(ensurePrekeys());
  }

  /// عند تسجيل الخروج: مسح المفاتيح المحفوظة على الجهاز (تُستعاد بكلمة سر النسخة الاحتياطية)
  static Future<void> wipeLocal() async {
    await _storage.deleteAll();
    _clearKeyCaches();
    _pubCache.clear();
    _changedPeers.clear();
    _sessionCache.clear();
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

  // ---------- التحقق من رمز الأمان بمسح QR ----------

  static const _verifyPrefix = 'e2e_verified_';

  /// حمولة رمز QR للتحقق — تربط هوية الحساب بمفتاحه العام:
  /// wasl-verify:v1|<userId>|<identity_public_key base64>
  static Future<String?> myVerifyPayload() async {
    if (!_ready) return null;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final pair = await _loadMyPair();
    final pub = await pair.extractPublicKey();
    return verifyPayloadFor(uid, base64Encode(pub.bytes));
  }

  static String verifyPayloadFor(String userId, String pubB64) =>
      'wasl-verify:v1|$userId|$pubB64';

  /// تحليل حمولة ممسوحة — null إن كان الشكل غير صالح (دالة نقية للاختبار)
  static (String, String)? parseVerifyPayload(String raw) {
    final parts = raw.trim().split('|');
    if (parts.length != 3 || parts[0] != 'wasl-verify:v1') return null;
    final uid = parts[1];
    final pub = parts[2];
    if (uid.length < 20 || pub.isEmpty) return null;
    try {
      final b = base64Decode(pub);
      if (b.length != 32) return null; // مفتاح X25519 = 32 بايت
    } catch (_) {
      return null;
    }
    return (uid, pub);
  }

  /// معالجة حمولة ممسوحة في سياق محادثة مع [expectedUserId]:
  /// يطابق مفتاح الرمز مع المفتاح المنشور للطرف ثم يوثّقه محلياً عند التطابق.
  static Future<VerifyScanResult> applyScannedVerify(
      String raw, String expectedUserId) async {
    final p = parseVerifyPayload(raw);
    if (p == null) return VerifyScanResult.invalid;
    final (uid, pubB64) = p;
    if (uid != expectedUserId) return VerifyScanResult.foreign;
    final published = await _publicKeyOf(expectedUserId);
    if (published == null) return VerifyScanResult.invalid;
    if (base64Encode(published.bytes) != pubB64) return VerifyScanResult.mismatch;
    await _storage.write(key: '$_verifyPrefix$expectedUserId', value: pubB64);
    return VerifyScanResult.verified;
  }

  /// هل الطرف موثّق وما زال مفتاحه المنشور هو ذاته الذي تم توثيقه؟
  /// (إذا غيّر الطرف مفتاحه يتلغى التوثيق تلقائياً بدون أي إجراء)
  static Future<bool> isVerified(String userId) async {
    if (!_ready) return false;
    final v = await _storage.read(key: '$_verifyPrefix$userId');
    if (v == null) return false;
    final pub = await _publicKeyOf(userId);
    if (pub == null) return false;
    return base64Encode(pub.bytes) == v;
  }

  /// إلغاء التوثيق يدوياً
  static Future<void> unverify(String userId) =>
      _storage.delete(key: '$_verifyPrefix$userId');

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
    final plain = await decryptDmText(conversationId, otherId, raw);
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
    final plain = await decryptGroupText(conversationId, raw);
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

  // ---------- السرية الأمامية (v2): مفاتيح أولية وجلسات متدرجة ----------

  static const _sessionPrefix = 'e2e_ratchet_';
  static const _prekeyPrivPrefix = 'e2e_prekey_priv_';

  /// حجم مخزون المفاتيح الأولية غير المستهلكة الذي نحافظ عليه
  static const _prekeyPool = 25;

  /// جلسات v2 بالذاكرة (محادثة ← حالة) — النسخة الدائمة في المخزن الآمن
  static final Map<String, RatchetState> _sessionCache = {};

  /// سلاسل تنفيذ لكل محادثة: تمنع فقدان تحديث حالة الجلسة بين await المتوازية
  static final Map<String, Future<void>> _sessionChains = {};

  static Future<T> _withSession<T>(
      String convId, Future<T> Function() body) {
    final prev = _sessionChains[convId] ?? Future.value();
    final done = Completer<void>();
    _sessionChains[convId] = done.future;
    return prev
        .then((_) => body())
        .whenComplete(() {
      done.complete();
      if (identical(_sessionChains[convId], done.future)) {
        _sessionChains.remove(convId);
      }
    });
  }

  static Future<RatchetState?> _loadSession(String convId) async {
    final hit = _sessionCache[convId];
    if (hit != null) return hit;
    final raw = await _storage.read(key: '$_sessionPrefix$convId');
    if (raw == null) return null;
    final st = RatchetState.tryDecode(raw);
    if (st == null) return null;
    _sessionCache[convId] = st;
    return st;
  }

  static Future<void> _saveSession(String convId, RatchetState st) async {
    _sessionCache[convId] = st;
    await _storage.write(key: '$_sessionPrefix$convId', value: st.encode());
  }

  static Future<void> _deleteSession(String convId) async {
    _sessionCache.remove(convId);
    try {
      await _storage.delete(key: '$_sessionPrefix$convId');
    } catch (_) {}
  }

  /// ينشر مخزون المفاتيح الأولية ويضبط e2e_version = 2 ويقلم المستهلكة القديمة.
  /// صامتة دائماً (ناريَ ونسيان) — تُستدعى بعد جاهزية الهوية.
  static Future<void> ensurePrekeys() async {
    if (!_ready) return;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await supabase
          .from('e2e_prekeys')
          .select('id, consumed_at, is_last_resort')
          .eq('user_id', uid);
      var unconsumed = 0;
      var hasLastResort = false;
      for (final r in rows) {
        if (r['is_last_resort'] == true) {
          hasLastResort = true;
        } else if (r['consumed_at'] == null) {
          unconsumed += 1;
        }
      }
      final toMake = <Map<String, dynamic>>[];
      var need = _prekeyPool - unconsumed;
      if (!hasLastResort) toMake.add({'is_last_resort': true});
      for (var i = 0; i < need && i < 60; i++) {
        toMake.add({'is_last_resort': false});
      }
      if (toMake.isNotEmpty) {
        // نولّد الأزواج محلياً ثم نرفعها ونعرف الخاص بمعرّف الخادم عبر مطابقة العام
        final pairs = <SimpleKeyPair>[];
        for (final row in toMake) {
          final p = await RatchetCrypto.newKeyPair();
          pairs.add(p);
          row['public_key'] =
              base64Encode((await p.extractPublicKey()).bytes);
        }
        final inserted = await supabase
            .from('e2e_prekeys')
            .insert(toMake)
            .select('id, public_key');
        for (final row in inserted) {
          final pub = row['public_key'] as String;
          for (final p in pairs) {
            if (base64Encode((await p.extractPublicKey()).bytes) == pub) {
              await _storage.write(
                key: '$_prekeyPrivPrefix${row['id']}',
                value: base64Encode(await p.extractPrivateKeyBytes()),
              );
              break;
            }
          }
        }
      }
      // رفع علم القدرة (v2) إن لم يُرفع
      final prof = await supabase
          .from('profiles')
          .select('e2e_version')
          .eq('id', uid)
          .maybeSingle();
      if (((prof?['e2e_version'] as int?) ?? 1) < 2) {
        await supabase.from('profiles').update({'e2e_version': 2}).eq('id', uid);
      }
      // تقليم: المستهلكة الأقدم من 30 يوماً (نظّام pg_cron ينظف أيضاً)
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final stale = rows
          .where((r) =>
              r['is_last_resort'] != true &&
              r['consumed_at'] is String &&
              (r['consumed_at'] as String).compareTo(cutoff) < 0)
          .map((r) => r['id'] as int)
          .toList();
      for (final id in stale) {
        await supabase.from('e2e_prekeys').delete().eq('id', id);
        await _storage.delete(key: '$_prekeyPrivPrefix$id');
      }
    } catch (_) {}
  }

  /// هل يدعم الطرف v2 (نشر مفاتيح أولية)؟
  static Future<bool> _peerSupportsV2(String otherUserId) async {
    try {
      final prof = await supabase
          .from('profiles')
          .select('e2e_version')
          .eq('id', otherUserId)
          .maybeSingle();
      return ((prof?['e2e_version'] as int?) ?? 1) >= 2;
    } catch (_) {
      return false;
    }
  }

  /// بدء جلسة من الصفر (المبادر): سحب مفتاح أولي + X3DH.
  /// القاعدة: الأصغر معرفاً يبدأ — تمنع سباق بدء مزدوج متنافر بلا وساطة.
  static Future<RatchetState?> _startSession(
      String convId, String otherUserId) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null || me.compareTo(otherUserId) >= 0) return null;
    if (!await _peerSupportsV2(otherUserId)) return null;
    final claimed = await supabase
        .rpc('e2e_claim_prekey', params: {'p_user_id': otherUserId});
    if (claimed is! List || claimed.isEmpty) return null;
    final row = claimed.first as Map<String, dynamic>;
    final keyId = ((row['o_key_id'] ?? row['key_id']) as num?)?.toInt();
    final pkB64 = (row['o_public_key'] ?? row['public_key']) as String?;
    if (keyId == null || pkB64 == null) return null;
    final other = await _publicKeyOf(otherUserId);
    if (other == null) return null;
    final my = await _loadMyPair();
    final ek = await RatchetCrypto.newKeyPair();
    final sk = await RatchetCrypto.initiatorSecret(
      identityMine: my,
      identityRemote: other,
      ephemeral: ek,
      prekeyRemote: RatchetCrypto.publicKeyFromB64(pkB64),
    );
    final st = await DoubleRatchet.startInitiator(
      sk: sk,
      remoteRatchetPub: RatchetCrypto.publicKeyFromB64(pkB64),
      ekB64: base64Encode((await ek.extractPublicKey()).bytes),
      prekeyId: keyId,
    );
    await _saveSession(convId, st);
    return st;
  }

  /// تبني رسالة افتتاحية من الطرف (المستجيب): فك الترويسة، تركيب X3DH من خاص
  /// المفتاح الأولي المسحوب بنا، فك الرسالة أولًا — لا جلسة إلا بعد نجاح الفك.
  static Future<String?> _adoptInitial(
      String convId, String otherUserId, String wire) async {
    final p = wire.split('.');
    if (p.length != 4) return null;
    final hdr = RatchetCrypto.decodeHeader(p[1]);
    if (hdr == null || hdr['e'] is! String || hdr['k'] is! int) return null;
    final privB64 =
        await _storage.read(key: '$_prekeyPrivPrefix${hdr['k']}');
    if (privB64 == null) return null;
    final other = await _publicKeyOf(otherUserId);
    if (other == null) return null;
    try {
      final my = await _loadMyPair();
      final prekeyPair =
          await RatchetCrypto.keyPairFromSeed(base64Decode(privB64));
      final sk = await RatchetCrypto.responderSecret(
        identityMine: my,
        identityRemote: other,
        prekeyMine: prekeyPair,
        ephemeralRemote:
            RatchetCrypto.publicKeyFromB64(hdr['e'] as String),
      );
      final st = await DoubleRatchet.startResponder(
          sk: sk, ratchetPair: prekeyPair);
      final plain = await DoubleRatchet.decrypt(st, convId, wire);
      if (plain == null) return null;
      await _saveSession(convId, st);
      return plain;
    } catch (_) {
      return null;
    }
  }

  /// تشفير نص محادثة خاصة: مسار v2 (سرية أمامية) إن أمكن، وإلا v1 الثابت.
  /// null = لا سبيل للتشفير (مفتاح مفقود) — يعرض المرسل رسالة واضحة.
  static Future<String?> encryptDmText(
      String conversationId, String otherUserId, String plain) async {
    if (!_ready) return null;
    final v2 = await _withSession(conversationId, () async {
      try {
        var st = await _loadSession(conversationId);
        st ??= await _startSession(conversationId, otherUserId);
        if (st == null) return null;
        return await DoubleRatchet.encrypt(st, conversationId, plain);
      } catch (_) {
        return null;
      }
    });
    if (v2 != null) return v2;
    // رجوع v1 الثابت (طرف قديم أو نفاد مفاتيح الطرف الأولية)
    final key = await dmKey(conversationId, otherUserId);
    if (key == null) return null;
    return encryptText(key, conversationId, plain);
  }

  /// فك نص محادثة خاصة: v2 (جلسة متدرجة) أو v1 (ثابت) أو نص قديم صريح.
  static Future<String?> decryptDmText(
      String conversationId, String otherUserId, String content) async {
    if (!isEncrypted(content)) return content;
    if (content.startsWith('v2.')) {
      if (!_ready) return null;
      return _withSession(conversationId, () async {
        final st = await _loadSession(conversationId);
        if (st != null) {
          String? plain;
          try {
            plain = await DoubleRatchet.decrypt(st, conversationId, content);
          } catch (_) {}
          // نحفظ دائماً: فشل فك بعد تدوير يحفظ الحالة المتسقة ذاتياً العلاج
          await _saveSession(conversationId, st);
          if (plain != null) return plain;
        }
        // رسالة افتتاحية: نتبناها فقط إن لم تكن جلستنا مستخدمة بعد
        // (يمنع رسالة قديمة معاد تشغيلها من تحطيم جلسة قائمة)
        if (DoubleRatchet.isInitialWire(content)) {
          final cur = await _loadSession(conversationId);
          if (cur == null || !cur.used) {
            return _adoptInitial(conversationId, otherUserId, content);
          }
        }
        return null;
      });
    }
    // v1
    final key = await dmKey(conversationId, otherUserId);
    if (key == null) return null;
    return decryptText(key, conversationId, content);
  }

  /// حذف جلسة محادثة (عند سحب رسالة/تغيّر مفتاح الطرف — تُعاد البداية تلقائياً)
  static Future<void> dropDmSession(String conversationId) =>
      _deleteSession(conversationId);

  // ---------- الحالات/القصص ----------

  /// المفتاح العام لأي مستخدم (لتغليف مفاتيح الحالات وفكّ أظرفها)
  static Future<SimplePublicKey?> publicKeyOf(String userId) => _publicKeyOf(userId);

  /// زوج هوية هذا الجهاز (لتغليف مفتاح حالة كصاحبها)
  static Future<SimpleKeyPair> identityPair() => _loadMyPair();

  /// مفتاح محتوى عشوائي 32B لحالة جديدة (AES-256)
  static Future<SecretKey> newContentKey() => _aes.newSecretKey();

  /// ظرفي في محادثة لإصدار مفتاح معيّن: (المغلَّف، مُغلِّفي)
  static Future<(String, String)?> _fetchMyEnvelope(String convId, String me, int version) async {
    final row = await supabase
        .from('conversation_key_envelopes')
        .select('wrapped_key, wrapped_by')
        .eq('conversation_id', convId)
        .eq('user_id', me)
        .eq('key_version', version)
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

  /// يغلّف مفتاحاً لقائمة أعضاء (من بلا مفتاح عام يُتخطّى ويُغلَّف له لاحقاً)
  static Future<List<Map<String, dynamic>>> _wrapForAll(
      String convId, SecretKey key, Iterable<String> memberIds) async {
    final me = supabase.auth.currentUser?.id;
    final my = await _loadMyPair();
    final myPub = await my.extractPublicKey();
    final payload = <Map<String, dynamic>>[];
    for (final id in memberIds) {
      final pub = id == me ? myPub : await _publicKeyOf(id);
      if (pub == null) continue;
      payload.add({
        'user_id': id,
        'wrapped_key': await wrapGroupKey(
            groupKey: key, conversationId: convId, wrapperPair: my, memberPub: pub),
      });
    }
    return payload;
  }

  /// من يملك المفتاح الحالي يغلّفه لمن بلا ظرف لهذا الإصدار (انضمام لاحق) — صامتة دائماً
  static Future<void> _topUpForMissingMembers(String convId, SecretKey key, int version) async {
    try {
      final members = (await _memberIds(convId)).toSet();
      final envRows = await supabase
          .from('conversation_key_envelopes')
          .select('user_id')
          .eq('conversation_id', convId)
          .eq('key_version', version);
      final covered = envRows.map((r) => r['user_id'] as String).toSet();
      final missing = members.difference(covered);
      if (missing.isEmpty) return;
      final payload = await _wrapForAll(convId, key, missing);
      if (payload.isEmpty) return;
      await supabase.rpc('e2e_wrap_for_members',
          params: {'p_conv': convId, 'p_envelopes': payload});
    } catch (_) {}
  }

  // ---------- تخزين المفاتيح محلياً (كل الإصدارات) ----------

  /// الإصدار 1 يبقى بالمفتاح القديم (توافق مع 0.1.4)، والإصدارات اللاحقة بلاحقة #v<n>
  static String _localKeyName(String convId, int version) =>
      version == 1 ? '$_groupKeyPrefix$convId' : '$_groupKeyPrefix$convId#v$version';
  static String _versionsName(String convId) => '$_groupKeyPrefix$convId#versions';

  static Future<Set<int>> _localVersions(String convId) async {
    final v = await _storage.read(key: _versionsName(convId));
    final out = <int>{};
    if (v != null) {
      for (final s in v.split(',')) {
        final n = int.tryParse(s);
        if (n != null) out.add(n);
      }
    }
    // مفتاح 0.1.4 المحفوظ بلا قائمة إصدارات
    if (!out.contains(1) && await _storage.containsKey(key: _localKeyName(convId, 1))) {
      out.add(1);
    }
    return out;
  }

  static Future<void> _persistGroupKey(String convId, int version, SecretKey key) async {
    await _storage.write(
        key: _localKeyName(convId, version), value: base64Encode(await key.extractBytes()));
    final vs = await _localVersions(convId)
      ..add(version);
    await _storage.write(key: _versionsName(convId), value: (vs.toList()..sort()).join(','));
  }

  static Future<SecretKey?> _localGroupKey(String convId, int version) async {
    final v = await _storage.read(key: _localKeyName(convId, version));
    return v == null ? null : SecretKeyData(base64Decode(v));
  }

  // ---------- حالة مفتاح المجموعة على الخادم ----------

  static final Map<String, (int, DateTime)> _verCache = {};

  /// (الإصدار الحالي، هل يحتاج تدويراً)
  static Future<(int, bool)> _keyState(String convId, {bool fresh = false}) async {
    final hit = _verCache[convId];
    if (!fresh && hit != null && DateTime.now().difference(hit.$2).inSeconds < 30) {
      return (hit.$1, false);
    }
    final row = await supabase
        .from('conversations')
        .select('group_key_version, needs_rekey')
        .eq('id', convId)
        .maybeSingle();
    final v = (row?['group_key_version'] as int?) ?? 1;
    final pending = (row?['needs_rekey'] as bool?) ?? false;
    if (!pending) _verCache[convId] = (v, DateTime.now());
    return (v, pending);
  }

  /// تدوير المفتاح بعد إزالة عضو أو مغادرته: مفتاح جديد يُغلَّف للأعضاء الحاليين فقط.
  /// يعيد المفتاح الجديد إن نجحنا، وnull إن سبقنا عضو آخر.
  static Future<SecretKey?> _rotate(String convId, int current) async {
    final members = await _memberIds(convId);
    final key = await _aes.newSecretKey();
    final payload = await _wrapForAll(convId, key, members);
    final me = supabase.auth.currentUser?.id;
    if (!payload.any((e) => e['user_id'] == me)) return null;
    final next = current + 1;
    final ok = await supabase.rpc('e2e_rotate_group_key',
        params: {'p_conv': convId, 'p_version': next, 'p_envelopes': payload});
    if (ok != true) return null;
    _groupKeyCache['$convId#v$next'] = key;
    await _persistGroupKey(convId, next, key);
    _verCache[convId] = (next, DateTime.now());
    return key;
  }

  /// مفتاح إصدار معيّن: الذاكرة ← ظرفي ← نسخة محلية
  static Future<SecretKey?> _keyForVersion(String convId, String me, int version) async {
    final ck = '$convId#v$version';
    final hit = _groupKeyCache[ck];
    if (hit != null) return hit;
    final env = await _fetchMyEnvelope(convId, me, version);
    if (env != null) {
      final key = await _unwrapEnvelope(convId, env);
      if (key != null) {
        _groupKeyCache[ck] = key;
        await _persistGroupKey(convId, version, key);
        return key;
      }
    }
    final local = await _localGroupKey(convId, version);
    if (local != null) _groupKeyCache[ck] = local;
    return local;
  }

  /// المفتاح الحالي لمجموعة خاصة (للإرسال).
  /// يدوّر المفتاح إن طُلب ذلك بعد إزالة/مغادرة، ثم: ظرفي ← نسخة محلية ← تثبيت أول (الإصدار 1 فقط).
  /// لا يستبدل أحدٌ مفتاحَ إصدار قائماً أبداً؛ العضو بلا ظرف ينتظر عضواً يملك المفتاح ليغلّفه له.
  static Future<SecretKey?> groupKey(String conversationId) async {
    if (!_ready) return null;
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return null;

      var (version, pending) = await _keyState(conversationId);
      if (pending) {
        final rotated = await _rotate(conversationId, version);
        if (rotated != null) return rotated;
        (version, pending) = await _keyState(conversationId, fresh: true);
        if (pending) return null; // التدوير لم يكتمل بعد: لا نرسل بالمفتاح القديم
      }

      final key = await _keyForVersion(conversationId, me, version);
      if (key != null) {
        unawaited(_topUpForMissingMembers(conversationId, key, version));
        return key;
      }
      if (version != 1) return null;

      // هل للمجموعة مفتاح أصلاً؟ إن وُجد أي ظرف فلا تثبيت: ننتظر عضواً يغلّف لنا
      final envAny = await supabase
          .from('conversation_key_envelopes')
          .select('user_id')
          .eq('conversation_id', conversationId)
          .limit(1);
      if (envAny.isNotEmpty) return null;

      // لا مفتاح بعد: المؤسس يثبّت (أو أي عضو في مجموعة قديمة بلا مؤسس)
      final conv = await supabase
          .from('conversations')
          .select('created_by')
          .eq('id', conversationId)
          .maybeSingle();
      final founder = conv?['created_by'] as String?;
      if (founder != null && founder != me) return null;

      final members = await _memberIds(conversationId);
      if (!members.contains(me) || members.length < 2) return null;
      final fresh = await _aes.newSecretKey();
      final payload = await _wrapForAll(conversationId, fresh, members);
      await supabase.rpc('e2e_set_group_key',
          params: {'p_conv': conversationId, 'p_envelopes': payload});

      // الحقيقة النهائية من القاعدة (إن سبقنا متسابق فمفتاحه هو المعتمد)
      final env = await _fetchMyEnvelope(conversationId, me, 1);
      if (env == null) return null;
      final truth = await _unwrapEnvelope(conversationId, env);
      if (truth == null) return null;
      _groupKeyCache['$conversationId#v1'] = truth;
      await _persistGroupKey(conversationId, 1, truth);
      return truth;
    } catch (_) {
      return null;
    }
  }

  static final Set<String> _allLoaded = {};

  /// كل مفاتيح المجموعة المعروفة لهذا الجهاز (الحالي أولاً) — لقراءة الرسائل القديمة بعد التدوير
  static Future<List<SecretKey>> groupKeys(String conversationId) async {
    if (!_ready) return const [];
    final me = supabase.auth.currentUser?.id;
    if (me == null) return const [];
    final out = <SecretKey>[];
    final current = await groupKey(conversationId);
    if (current != null) out.add(current);
    try {
      if (!_allLoaded.contains(conversationId)) {
        _allLoaded.add(conversationId);
        final rows = await supabase
            .from('conversation_key_envelopes')
            .select('key_version')
            .eq('conversation_id', conversationId)
            .eq('user_id', me);
        final versions = rows.map((r) => r['key_version'] as int).toSet()
          ..addAll(await _localVersions(conversationId));
        for (final v in versions) {
          await _keyForVersion(conversationId, me, v);
        }
      }
    } catch (_) {
      _allLoaded.remove(conversationId);
    }
    final prefix = '$conversationId#v';
    final versions = _groupKeyCache.keys
        .where((k) => k.startsWith(prefix))
        .map((k) => int.tryParse(k.substring(prefix.length)) ?? 0)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    for (final v in versions) {
      final k = _groupKeyCache['$prefix$v']!;
      if (!identical(k, current)) out.add(k);
    }
    return out;
  }

  /// يفك نص مجموعة بتجربة كل الإصدارات المعروفة (AES-GCM يرفض المفتاح الخطأ)
  static Future<String?> decryptGroupText(String conversationId, String content) async {
    if (!isEncrypted(content)) return content;
    for (final k in await groupKeys(conversationId)) {
      final p = await decryptText(k, conversationId, content);
      if (p != null) return p;
    }
    return null;
  }

  static Future<Uint8List?> decryptGroupBytes(String conversationId, Uint8List data) async {
    for (final k in await groupKeys(conversationId)) {
      final p = await decryptBytes(k, conversationId, data);
      if (p != null) return p;
    }
    return null;
  }

  /// مسح ذاكرة مفاتيح مجموعة (عند فشل فك رسالة أو تغيّر الأعضاء — يُعاد الجلب)
  static void invalidateGroupKey(String conversationId) {
    _verCache.remove(conversationId);
    _allLoaded.remove(conversationId);
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
