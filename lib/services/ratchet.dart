import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// السرية الأمامية للمحادثات الخاصة — النواة النقية (بلا Flutter ولا Supabase).
///
/// التصميم وفق مواصفة Double Ratchet (Marlinspike–Perrin) مع تبادل X3DH بثلاث
/// خطوات DH (بلا مفتاح توقيع مسبق — المفتاح الأولي العشوائي نفسه هو مفتاح
/// التدوير الأول، وانتحال الهوية يُكشف برمز الأمان وتوثيق QR المنفذ في 0.7.5):
///
///   DH1 = X25519(هوية المبادر، هوية الطرف)
///   DH2 = X25519(المؤقت، هوية الطرف)
///   DH3 = X25519(المؤقت، المفتاح الأولي المسحوب)
///   SK  = HKDF-SHA256(FF*32 || DH1 || DH2 || DH3, salt = 0*32, info = 'wasl-x3dh-v1')
///
/// ثم المزدوجة:
///   KDF_RK(rk, dh) = HKDF(ikm = dh, salt = rk, info = 'wasl-dr-rk-v1', 64 بايت)
///                    → (rk الجديد، مفتاح السلسلة)
///   KDF_CK(ck)     = (HMAC(ck, 0x01)، HMAC(ck, 0x02))  ← (مفتاح الرسالة، السلسلة التالية)
///   مفتاح الرسالة  = HKDF(ikm = mk, salt = 0*32, info = 'wasl-dr-msg-v1', 44 بايت)
///                    → (مفتاح AES-256، nonce 12 بايت) — مشتق لا عشوائي فلا تصادم
///
/// صيغة الرسالة على السلك:
///   v2.<b64(json الترويسة)>.<b64(نص التشفير)>.<b64(mac)>
///   الترويسة: {"d": مفتاح التدوير العام, "n": رقم الرسالة, "p": pn}
///   وأول رسالة (X3DH) تضيف: {"e": المفتاح المؤقت, "k": رقم المفتاح الأولي المسحوب}
///   AAD = "<conversation_id>|<نص الترويسة كما هو على السلك>" — يمنع نقل الرسالة
///   بين محادثتين ويعزل كل بايت من الترويسة عن التلاعب.
///
/// كل الدوال نقية وغير للجلسات هنا؛ التخزين والتزامن في E2eService.
class RatchetCrypto {
  RatchetCrypto._();

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hmac _hmacSha = Hmac.sha256();

  static const infoX3dh = 'wasl-x3dh-v1';
  static const infoRoot = 'wasl-dr-rk-v1';
  static const infoMsg = 'wasl-dr-msg-v1';
  static const _ff = 0xff;

  /// أقصى عدد مفاتيح متخطاة محفوظة لكل جلسة (رسائل وصلت بلا ترتيب)
  static const maxSkipped = 512;

  // ---------- أدوات أساسية ----------

  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) =>
      _x25519.newKeyPairFromSeed(seed);

  static SimplePublicKey publicKeyFromB64(String b64) =>
      SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);

  static Future<Uint8List> dh(SimpleKeyPair pair, SimplePublicKey remote) async {
    final shared = await _x25519.sharedSecretKey(keyPair: pair, remotePublicKey: remote);
    return Uint8List.fromList(await shared.extractBytes());
  }

  static Future<Uint8List> dhRaw(List<int> privSeed, SimplePublicKey remote) async {
    final pair = await keyPairFromSeed(privSeed);
    return dh(pair, remote);
  }

  static Future<(Uint8List, Uint8List)> _hkdf64(
      List<int> ikm, List<int> salt, String info) async {
    final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final out = await kdf.deriveKey(
      secretKey: SecretKeyData(ikm),
      nonce: salt,
      info: utf8.encode(info),
    );
    final b = await out.extractBytes();
    return (Uint8List.fromList(b.sublist(0, 32)), Uint8List.fromList(b.sublist(32, 64)));
  }

  /// KDF_RK: (rk الجديد، مفتاح سلسلة)
  static Future<(Uint8List, Uint8List)> kdfRoot(Uint8List rk, Uint8List dhOut) =>
      _hkdf64(dhOut, rk, infoRoot);

  static Future<Uint8List> _hmac(List<int> key, List<int> msg) async {
    final mac = await _hmacSha.calculateMac(msg, secretKey: SecretKeyData(key));
    return Uint8List.fromList(mac.bytes);
  }

  /// KDF_CK: (مفتاح الرسالة، مفتاح السلسلة التالي)
  static Future<(Uint8List, Uint8List)> kdfChain(Uint8List ck) async {
    final mk = await _hmac(ck, const [0x01]);
    final next = await _hmac(ck, const [0x02]);
    return (mk, next);
  }

  /// مفتاح رسالة → (مفتاح AES-256، nonce 12)
  static Future<(Uint8List, Uint8List)> messageKey(Uint8List mk) async {
    final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 44);
    final out = await kdf.deriveKey(
      secretKey: SecretKeyData(mk),
      nonce: Uint8List(32),
      info: utf8.encode(infoMsg),
    );
    final b = await out.extractBytes();
    return (
      Uint8List.fromList(b.sublist(0, 32)),
      Uint8List.fromList(b.sublist(32, 44)),
    );
  }

  // ---------- X3DH ----------

  static Future<Uint8List> _x3dhSecret(
      List<List<int>> dhParts) async {
    final ikm = BytesBuilder(copy: false)
      ..add(List<int>.filled(32, _ff));
    for (final p in dhParts) {
      ikm.add(p);
    }
    final (sk, _) = await _hkdf64(ikm.toBytes(), Uint8List(32), infoX3dh);
    return sk;
  }

  /// سر المبادر: يملك هويته وزوجَه المؤقت ويعرف هوية الطرف ومفتاحه الأولي.
  static Future<Uint8List> initiatorSecret({
    required SimpleKeyPair identityMine,
    required SimplePublicKey identityRemote,
    required SimpleKeyPair ephemeral,
    required SimplePublicKey prekeyRemote,
  }) async =>
      _x3dhSecret([
        await dh(identityMine, identityRemote), // DH1
        await dh(ephemeral, identityRemote), // DH2
        await dh(ephemeral, prekeyRemote), // DH3
      ]);

  /// سر المستجيب: يملك هويته والمفتاح الأولي المسحوب (خاصه) ويعرف هوية المبادر
  /// وزوجَه المؤقت (من ترويسة أول رسالة).
  static Future<Uint8List> responderSecret({
    required SimpleKeyPair identityMine,
    required SimplePublicKey identityRemote,
    required SimpleKeyPair prekeyMine,
    required SimplePublicKey ephemeralRemote,
  }) async =>
      _x3dhSecret([
        await dh(identityMine, identityRemote), // DH1 (تماثل DH1 للمبادر)
        await dh(identityMine, ephemeralRemote), // DH2 (تماثل DH2)
        await dh(prekeyMine, ephemeralRemote), // DH3 (تماثل DH3)
      ]);

  // ---------- الترويسة ----------

  static String encodeHeader(Map<String, dynamic> json) =>
      base64Encode(utf8.encode(jsonEncode(json)));

  static Map<String, dynamic>? decodeHeader(String b64) {
    try {
      final v = jsonDecode(utf8.decode(base64Decode(b64)));
      if (v is! Map<String, dynamic>) return null;
      if (v['d'] is! String || v['n'] is! int || v['p'] is! int) return null;
      return v;
    } catch (_) {
      return null;
    }
  }
}

/// حالة جلسة Double Ratchet لكل محادثة — قابلة للتسلسل JSON (تُخزَّن محلياً مشفّرة
/// بدرجة تخزين النظام عبر flutter_secure_storage).
class RatchetState {
  RatchetState({
    required this.rk,
    required this.spub,
    this.spriv,
    this.rpub,
    this.cks,
    this.ckr,
    this.ns = 0,
    this.nr = 0,
    this.pn = 0,
    this.used = false,
    this.ekB64,
    this.prekeyId,
    Map<String, Uint8List>? skipped,
  }) : skipped = skipped ?? {};

  Uint8List rk; // المفتاح الجذري
  Uint8List spub; // مفتاح التدوير العام الخاص بي
  Uint8List? spriv; // خاصه (يبقى محلياً)
  Uint8List? rpub; // مفتاح التدوير العام للطرف
  Uint8List? cks; // سلسلة الإرسال
  Uint8List? ckr; // سلسلة الاستقبال
  int ns; // عدد الرسائل المرسلة في السلسلة الحالية
  int nr; // عدد الرسائل المستقبلة في السلسلة الحالية
  int pn; // عدد رسائل السلسلة السابقة
  bool used; // جرحت الجلسة نجاحاً ولو مرة (يمنع استبدالها برسالة أولى معاد تشغيلها)
  String? ekB64; // المفتاح المؤقت لأول رسالة (يُمسح بعد أول إرسال)
  int? prekeyId; // رقم المفتاح الأولي المسحوب لأول رسالة
  final Map<String, Uint8List> skipped; // "<rpubB64>:<n>" -> مفتاح الرسالة

  Map<String, dynamic> toJson() => {
        'rk': base64Encode(rk),
        'spub': base64Encode(spub),
        'spriv': spriv == null ? null : base64Encode(spriv!),
        'rpub': rpub == null ? null : base64Encode(rpub!),
        'cks': cks == null ? null : base64Encode(cks!),
        'ckr': ckr == null ? null : base64Encode(ckr!),
        'ns': ns,
        'nr': nr,
        'pn': pn,
        'used': used,
        'ek': ekB64,
        'pk': prekeyId,
        'sk': skipped.map((k, v) => MapEntry(k, base64Encode(v))),
      };

  static RatchetState fromJson(Map<String, dynamic> j) {
    Uint8List? b(String? s) => s == null ? null : Uint8List.fromList(base64Decode(s));
    final sk = <String, Uint8List>{};
    final raw = j['sk'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is String) sk[k] = Uint8List.fromList(base64Decode(v));
      });
    }
    return RatchetState(
      rk: b(j['rk'])!,
      spub: b(j['spub'])!,
      spriv: b(j['spriv']),
      rpub: b(j['rpub']),
      cks: b(j['cks']),
      ckr: b(j['ckr']),
      ns: (j['ns'] as num?)?.toInt() ?? 0,
      nr: (j['nr'] as num?)?.toInt() ?? 0,
      pn: (j['pn'] as num?)?.toInt() ?? 0,
      used: j['used'] == true,
      ekB64: j['ek'] as String?,
      prekeyId: (j['pk'] as num?)?.toInt(),
      skipped: sk,
    );
  }

  String encode() => jsonEncode(toJson());

  static RatchetState? tryDecode(String s) {
    try {
      final v = jsonDecode(s);
      if (v is! Map<String, dynamic>) return null;
      if (v['rk'] is! String || v['spub'] is! String) return null;
      return fromJson(v);
    } catch (_) {
      return null;
    }
  }
}

/// محرك الجلسة — تهيئة وتشفير وفك، بتعديل الحالة الممررة مباشرة.
class DoubleRatchet {
  DoubleRatchet._();

  /// جلسة المبادر (بعد X3DH): يولّد مفتاح تدوير جديداً ويسلسل مع المفتاح الأولي للطرف.
  /// [ekB64] و[prekeyId] بيانات أول رسالة (توضع في ترويستها ثم تُمسح).
  static Future<RatchetState> startInitiator({
    required Uint8List sk,
    required SimplePublicKey remoteRatchetPub,
    String? ekB64,
    int? prekeyId,
  }) async {
    final pair = await RatchetCrypto.newKeyPair();
    final pub = await pair.extractPublicKey();
    final priv = await pair.extractPrivateKeyBytes();
    final dh = await RatchetCrypto.dh(pair, remoteRatchetPub);
    final (rk, cks) = await RatchetCrypto.kdfRoot(sk, dh);
    return RatchetState(
      rk: rk,
      spub: Uint8List.fromList(pub.bytes),
      spriv: Uint8List.fromList(priv),
      rpub: Uint8List.fromList(remoteRatchetPub.bytes),
      cks: cks,
      ckr: null,
      used: false,
      ekB64: ekB64,
      prekeyId: prekeyId,
    );
  }

  /// جلسة المستجيب (بعد X3DH): مفتاح التدوير هو المفتاح الأولي الذي ملكه أصلاً.
  static Future<RatchetState> startResponder({
    required Uint8List sk,
    required SimpleKeyPair ratchetPair,
  }) async {
    final pub = await ratchetPair.extractPublicKey();
    final priv = await ratchetPair.extractPrivateKeyBytes();
    return RatchetState(
      rk: sk,
      spub: Uint8List.fromList(pub.bytes),
      spriv: Uint8List.fromList(priv),
      rpub: null,
      cks: null,
      ckr: null,
      used: false,
    );
  }

  /// يشفّر نصاً ويعيد رسالة السلك الكاملة v2 (null إن لم تكن سلسلة الإرسال جاهزة).
  static Future<String?> encrypt(
      RatchetState st, String conversationId, String plain) async {
    final cks = st.cks;
    if (cks == null) return null;
    final (mk, next) = await RatchetCrypto.kdfChain(cks);
    final header = <String, dynamic>{
      'd': base64Encode(st.spub),
      'n': st.ns,
      'p': st.pn,
    };
    if (st.ekB64 != null && st.prekeyId != null) {
      header['e'] = st.ekB64;
      header['k'] = st.prekeyId;
    }
    final hdrB64 = RatchetCrypto.encodeHeader(header);
    st.cks = next;
    st.ns += 1;
    st.ekB64 = null;
    st.prekeyId = null;
    st.used = true;
    final (key, nonce) = await RatchetCrypto.messageKey(mk);
    final box = await RatchetCrypto._aes.encrypt(
      utf8.encode(plain),
      secretKey: SecretKeyData(key),
      nonce: nonce,
      aad: utf8.encode('$conversationId|$hdrB64'),
    );
    return 'v2.$hdrB64.'
        '${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}';
  }

  /// يفك رسالة v2 ويحدّث الحالة. null عند الفشل أو العبث أو التكرار.
  static Future<String?> decrypt(
      RatchetState st, String conversationId, String wire) async {
    final p = wire.split('.');
    if (p.length != 4 || p[0] != 'v2') return null;
    final hdr = RatchetCrypto.decodeHeader(p[1]);
    if (hdr == null) return null;
    final dBytes = Uint8List.fromList(base64Decode(hdr['d'] as String));
    final n = hdr['n'] as int;
    final pn = hdr['p'] as int;
    final aad = utf8.encode('$conversationId|${p[1]}');

    // 1) مفتاح متخطى (رسالة وصلت متأخرة) — لا تغيير على السلاسل
    final skKey = '${base64Encode(dBytes)}:$n';
    final skipped = st.skipped.remove(skKey);
    if (skipped != null) {
      final plain = await _open(skipped, p[2], p[3], aad);
      if (plain != null) st.used = true;
      return plain;
    }

    // 2) تدوير DH إن تغيّر مفتاح الطرف (أو أول رسالة تصل)
    if (st.rpub == null || !_bytesEqual(st.rpub!, dBytes)) {
      await _skipMessageKeys(st, pn);
      await _dhRatchet(st, dBytes);
    }

    // 3) التقدم حتى رقم الرسالة (تخزين المفاتيح المتخطاة)
    await _skipMessageKeys(st, n);

    // 4) فك بالمفتاح الحالي — نتحرك في السلسلة فقط عند النجاح (تكرار/عبث لا يفسد الحالة)
    final ckr = st.ckr;
    if (ckr == null) return null;
    final (mk, ckrNext) = await RatchetCrypto.kdfChain(ckr);
    final plain = await _open(mk, p[2], p[3], aad);
    if (plain == null) return null;
    st.ckr = ckrNext;
    st.nr += 1;
    st.used = true;
    return plain;
  }

  /// هل هذه رسالة افتتاحية X3DH (تحمل مفتاحاً مؤقتاً ورقم مفتاح أولي)؟
  static bool isInitialWire(String wire) {
    if (!wire.startsWith('v2.')) return false;
    final p = wire.split('.');
    if (p.length != 4) return false;
    final hdr = RatchetCrypto.decodeHeader(p[1]);
    return hdr != null && hdr['e'] is String && hdr['k'] is int;
  }

  static Future<void> _skipMessageKeys(RatchetState st, int until) async {
    final rpub = st.rpub;
    if (rpub == null) return;
    final rB64 = base64Encode(rpub);
    while (st.nr < until) {
      if (st.ckr == null) return;
      if (st.skipped.length >= RatchetCrypto.maxSkipped) {
        st.skipped.remove(st.skipped.keys.first);
      }
      final (mk, next) = await RatchetCrypto.kdfChain(st.ckr!);
      st.skipped['$rB64:${st.nr}'] = mk;
      st.ckr = next;
      st.nr += 1;
    }
  }

  static Future<void> _dhRatchet(RatchetState st, Uint8List remotePub) async {
    final remote = SimplePublicKey(remotePub, type: KeyPairType.x25519);
    // (rk، سلسلة استقبال) من مفتاحي الحالي مقابل المفتاح الجديد للطرف
    final myPair = await RatchetCrypto.keyPairFromSeed(st.spriv!);
    final dh1 = await RatchetCrypto.dh(myPair, remote);
    final (rk1, ckr) = await RatchetCrypto.kdfRoot(st.rk, dh1);
    st.rk = rk1;
    st.rpub = Uint8List.fromList(remotePub);
    st.pn = st.ns;
    st.ns = 0;
    st.nr = 0;

    // مفتاح إرسال جديد تماماً (خطوة التدوير الثانية — كما في المواصفة)
    final fresh = await RatchetCrypto.newKeyPair();
    final priv = await fresh.extractPrivateKeyBytes();
    final pub = await fresh.extractPublicKey();
    final dh2 = await RatchetCrypto.dh(fresh, remote);
    final (rk2, cks) = await RatchetCrypto.kdfRoot(rk1, dh2);
    st.rk = rk2;
    st.spriv = Uint8List.fromList(priv);
    st.spub = Uint8List.fromList(pub.bytes);
    st.cks = cks;
    st.ckr = ckr;
  }

  static Future<String?> _open(
      Uint8List mk, String ctB64, String macB64, List<int> aad) async {
    try {
      final (key, nonce) = await RatchetCrypto.messageKey(mk);
      final plain = await RatchetCrypto._aes.decrypt(
        SecretBox(base64Decode(ctB64), nonce: nonce, mac: Mac(base64Decode(macB64))),
        secretKey: SecretKeyData(key),
        aad: aad,
      );
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
