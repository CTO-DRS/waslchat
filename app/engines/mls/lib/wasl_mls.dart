/// محرك MLS للجمعات الضخمة — المحرك النقي الحادي عشر من محركات وصل
/// (المرحلة 21 — 1.19.0).
///
/// ينفذ نواة التصميم الموثق في `docs/MLS_DESIGN.md` (§5 خطوة 2 «النواة
/// النقية») وفق قواعد RFC 9420 المفحوصة من نص المعيار نفسه: شجرة تدوير
/// بتخطيط الكومة (الجذر 0، أبناء 2x+1/2x+2، الأوراق n-1..2n-2)، ومسار
/// مباشر يعاد تكييفه بكل كومت تحمله أظرفة **لعُقد resolution الطفل غير
/// المحدَّث** — والأوراق غير المدمجة (unmerged) تُحسب في الـresolution
/// (§7.2/§7.10.1) وهو ما يضمن أن العضو المنضم حديثاً بحامل مفتاح ورقته
/// وحده يفك الكومت التالي، والجدد في نفس الكومت مستثنون من الـresolution
/// كما يلزم المعيار. جدولة العهود: سر العهد يتقدم من سر جذر المسار الجديد
/// فلا مشتاق عكسي، ومفاتيح مرسل لكل ورقة بسلسلة أجيال، وتوقيع Ed25519
/// على الكومتات والترحيبات بهوية الكاتب المسجلة لا بما يرفقه الكومت.
/// الأوليات كلها نقية من `cryptography` (X25519 + HKDF-SHA256 +
/// AES-256-GCM + Ed25519) — بلا أي كود C، فوق النواة القائمة فعلاً كما
/// يصرح التصميم §4، بعلامات wasl-mls منفصلة عن علامات سلسلة الجلسات
/// (بوابة التوافق مع التشفير الحالي).
///
/// الصدق التصميمي: هذه **النواة الرياضية والحالية** لا صيغة الأسلاك:
/// التسلسل JSON موحد داخلياً (لا بنية MLSMessage الرسمية ولا HPKE RFC 9180
/// حرفياً — الكيفية بنمط وصل HKDF(X25519)+AES-GCM)، والشجرة سعة ثابتة
/// تُملأ بالأظرفة (لا نمو بعد الإنشاء)، وكل عضو يجب أن يعالج الكومتات
/// بترتيبها (المتأخر يعيد المزامنة عند التكامل). صيغة الأسلاك الرسمية
/// ومتجهات توافق IETF إصدار التكامل التالي كما قدّر التصميم بنفسه
/// («إصداران كاملان قبل أول مجموعة تعمل MLS حقيقياً»).
library;

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// ————— الأوليات النقية —————

/// أوليات MLS: X25519 للـKEM، HKDF-SHA256 للاشتقاق، AES-256-GCM للتشفير،
/// Ed25519 للتوقيع — كلها نقية من `cryptography` بعلامات wasl-mls منفصلة
/// عن علامات سلسلة الجلسات (بوابة التوافق مع التشفير الحالي).
class MlsCrypto {
  MlsCrypto._();

  static final X25519 _x = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Ed25519 _sig = Ed25519();

  static const infoEpoch = 'wasl-mls-epoch-v1';
  static const infoSender = 'wasl-mls-sender-v1';
  static const infoGen = 'wasl-mls-gen-v1';
  static const infoNode = 'wasl-mls-node-v1';
  static const infoKem = 'wasl-mls-kem-v1';

  static Future<Uint8List> hkdf(
      List<int> ikm, List<int> salt, String info, int len) async {
    final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: len);
    final out = await kdf.deriveKey(
      secretKey: SecretKeyData(ikm),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await out.extractBytes());
  }

  /// سر عقدة الشجرة → زوج X25519 للعقدة (اشتقاق بذرة موقعها بالفهرس).
  static Future<SimpleKeyPair> nodePair(
      List<int> nodeSecret, int nodeIdx) async {
    final seed = await hkdf(nodeSecret, [nodeIdx & 0xff, (nodeIdx >> 8) & 0xff],
        infoNode, 32);
    return _x.newKeyPairFromSeed(seed);
  }

  static Future<List<int>> pubOf(SimpleKeyPair pair) async =>
      (await pair.extractPublicKey()).bytes;

  /// غلاف KEM بنمط وصل: X25519 مؤقت + HKDF + AES-GCM — AAD يربط الغلاف
  /// بمكانه في الشجرة فلا يُنقل غلاف لسياق آخر.
  static Future<Uint8List> seal(
      List<int> targetPub, List<int> plaintext, List<int> aad) async {
    final eph = await _x.newKeyPair();
    final shared = await _x.sharedSecretKey(
        keyPair: eph,
        remotePublicKey: SimplePublicKey(targetPub, type: KeyPairType.x25519));
    final sharedBytes = await shared.extractBytes();
    final ephPub = (await eph.extractPublicKey()).bytes;
    final kn = await hkdf(sharedBytes, [...ephPub, ...targetPub], infoKem, 44);
    final box = await _aes.encrypt(plaintext,
        secretKey: SecretKeyData(kn.sublist(0, 32)),
        nonce: kn.sublist(32, 44),
        aad: aad);
    return Uint8List.fromList(
        [...ephPub, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// فك الغلاف — null عند أي فشل (مفتاح خاطئ/عبث) بلا استثناءات مسربة.
  static Future<Uint8List?> open(
      SimpleKeyPair myPair, Uint8List sealed, List<int> aad) async {
    if (sealed.length < 32 + 12 + 16) return null;
    try {
      final ephPub = sealed.sublist(0, 32);
      final nonce = sealed.sublist(32, 44);
      final ct = sealed.sublist(44, sealed.length - 16);
      final mac = sealed.sublist(sealed.length - 16);
      final myPub = (await myPair.extractPublicKey()).bytes;
      final shared = await _x.sharedSecretKey(
          keyPair: myPair,
          remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519));
      final sharedBytes = await shared.extractBytes();
      final kn = await hkdf(sharedBytes, [...ephPub, ...myPub], infoKem, 44);
      final pt = await _aes.decrypt(
        SecretBox(ct, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKeyData(kn.sublist(0, 32)),
        aad: aad,
      );
      return Uint8List.fromList(pt);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> aesEncrypt(
      List<int> key32, List<int> nonce12, List<int> pt, List<int> aad) async {
    final box = await _aes.encrypt(pt,
        secretKey: SecretKeyData(key32), nonce: nonce12, aad: aad);
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  /// null عند فشل التوثيق (مفتاح خاطئ أو عبث) — لا استثناءات.
  static Future<Uint8List?> aesDecrypt(List<int> key32, List<int> nonce12,
      Uint8List ctMac, List<int> aad) async {
    if (ctMac.length < 16) return null;
    try {
      final pt = await _aes.decrypt(
        SecretBox(ctMac.sublist(0, ctMac.length - 16),
            nonce: nonce12, mac: Mac(ctMac.sublist(ctMac.length - 16))),
        secretKey: SecretKeyData(key32),
        aad: aad,
      );
      return Uint8List.fromList(pt);
    } catch (_) {
      return null;
    }
  }

  static Future<SimpleKeyPair> sigPairFromSeed(List<int> seed32) =>
      _sig.newKeyPairFromSeed(seed32);

  static Future<SimpleKeyPair> sigNewPair() => _sig.newKeyPair();

  static Future<List<int>> sign(List<int> msg, SimpleKeyPair pair) async =>
      (await _sig.sign(msg, keyPair: pair)).bytes;

  static Future<bool> verify(
          List<int> msg, List<int> signature, List<int> pub) async =>
      _sig.verify(msg,
          signature: Signature(signature,
              publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)));

  static Future<SimpleKeyPair> kemPairFromSeed(List<int> seed32) =>
      _x.newKeyPairFromSeed(seed32);

  static Future<SimpleKeyPair> kemNewPair() => _x.newKeyPair();
}

// ————— رياضيات الشجرة (تخطيط الكومة كما في RFC 9420 §2.5.1) —————

/// فهرس عقدة الورقة i في شجرة n أوراق: الأوراق تحتل n-1..2n-2.
int leafNodeIndex(int leafIdx, int n) => (n - 1) + leafIdx;

/// فهرس ورقة من فهرس عقدة ورقة.
int leafIndexOfNode(int nodeIdx, int n) => nodeIdx - (n - 1);

/// عدد عقد الشجرة.
int nodeCount(int n) => 2 * n - 1;

/// أب العقدة (null للجذر).
int? parentNode(int nodeIdx) => nodeIdx == 0 ? null : (nodeIdx - 1) ~/ 2;

/// أبناء العقدة الداخلية.
List<int> childNodes(int nodeIdx) => [2 * nodeIdx + 1, 2 * nodeIdx + 2];

/// المسار المباشر للورقة: من الورقة حتى الجذر شاملاً.
List<int> directPath(int leafIdx, int n) {
  final path = <int>[];
  var x = leafNodeIndex(leafIdx, n);
  while (true) {
    path.add(x);
    final p = parentNode(x);
    if (p == null) break;
    x = p;
  }
  return path;
}

// ————— الحزم —————

/// حزمة مفاتيح عضو — تُنشر لمن يضيفه: مفتاح KEM لورقته ومفتاح توقيع هويته
/// (كما يطلب التصميم: أوراق الشجرة موقعة بمفاتيح توقيع الأعضاء).
class MlsKeyPackage {
  MlsKeyPackage({
    required this.memberId,
    required this.kemPub,
    required this.sigPub,
  });

  final String memberId;
  final List<int> kemPub;
  final List<int> sigPub;

  Map<String, Object> toJson() => {
        'm': memberId,
        'k': base64Encode(kemPub),
        's': base64Encode(sigPub),
      };

  static MlsKeyPackage fromJson(Map<String, Object?> j) => MlsKeyPackage(
        memberId: j['m'] as String,
        kemPub: base64Decode(j['k'] as String),
        sigPub: base64Decode(j['s'] as String),
      );
}

/// كومت موقّع: مقترحات (إضافة/إزالة) + مسار كاتب محدَّث + أظرفة أسرار
/// المسار لعُقد resolution الأطفال + توقيع Ed25519.
class MlsCommit {
  MlsCommit({
    required this.epoch,
    required this.updaterLeaf,
    required this.adds,
    required this.removes,
    required this.pathPubs,
    required this.envelopes,
    required this.sigPub,
    required this.signature,
  });

  final int epoch;
  final int updaterLeaf;
  final List<(int, MlsKeyPackage)> adds; // (ورقة, حزمة مفاتيح)
  final List<int> removes; // أوراق
  final List<(int, List<int>)> pathPubs; // (عقدة, مفتاح عام)
  final List<(int, int, Uint8List)> envelopes; // (عقدة الهدف, عقدة المسار, مظروف ps)
  final List<int> sigPub;
  final List<int> signature;

  /// الحمولة الكنسية الموقعة — كل الحقول إلا التوقيع ومفتاح التوقيع
  Map<String, Object> payload() => {
        'v': 1,
        'e': epoch,
        'u': updaterLeaf,
        'a': [
          for (final (slot, kp) in adds)
            <String, Object>{'l': slot, 'kp': kp.toJson()}
        ],
        'r': removes,
        'p': [
          for (final (idx, pub) in pathPubs)
            <String, Object>{'n': idx, 'k': base64Encode(pub)}
        ],
        'x': [
          for (final (t, p, sealed) in envelopes)
            <String, Object>{'n': t, 'p': p, 'c': base64Encode(sealed)}
        ],
      };

  Uint8List serialize() => utf8.encode(jsonEncode(<String, Object>{
        ...payload(),
        'sp': base64Encode(sigPub),
        'sg': base64Encode(signature),
      }));

  /// فك البنية — التحقق من التوقيع يجري في applyCommit بهوية الكاتب المسجلة.
  static MlsCommit? parse(Uint8List bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return MlsCommit(
        epoch: j['e'] as int,
        updaterLeaf: j['u'] as int,
        adds: [
          for (final a in (j['a'] as List))
            (
              (a as Map)['l'] as int,
              MlsKeyPackage.fromJson(
                  Map<String, Object?>.from(a['kp'] as Map))
            )
        ],
        removes: [...(j['r'] as List).cast<int>()],
        pathPubs: [
          for (final p in (j['p'] as List))
            ((p as Map)['n'] as int, base64Decode(p['k'] as String))
        ],
        envelopes: [
          for (final Map row in (j['x'] as List))
            (
              row['n'] as int,
              row['p'] as int,
              base64Decode(row['c'] as String)
            )
        ],
        sigPub: base64Decode(j['sp'] as String),
        signature: base64Decode(j['sg'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// ترحيب عضو جديد: السعة + لقطة الشجرة العامة + سر العهد الجديد مغلفاً
/// بحزمة مفاتيحه — لا يقرأ ما قبل عهده (سرية أمامية مقصودة، التصميم §7).
class MlsWelcome {
  MlsWelcome({
    required this.groupId,
    required this.capacity,
    required this.epoch,
    required this.myLeaf,
    required this.members,
    required this.treePubs,
    required this.sealedEpochSecret,
    required this.sigPub,
    required this.signature,
  });

  final String groupId;
  final int capacity;
  final int epoch;
  final int myLeaf;
  final List<(int, MlsKeyPackage)> members;
  final List<(int, List<int>)> treePubs;
  final Uint8List sealedEpochSecret;
  final List<int> sigPub;
  final List<int> signature;

  Map<String, Object> payload() => {
        'v': 1,
        'g': groupId,
        'n': capacity,
        'e': epoch,
        'l': myLeaf,
        'm': [
          for (final (slot, kp) in members)
            <String, Object>{'l': slot, 'kp': kp.toJson()}
        ],
        't': [
          for (final (idx, pub) in treePubs)
            <String, Object>{'n': idx, 'k': base64Encode(pub)}
        ],
        'w': base64Encode(sealedEpochSecret),
      };

  Uint8List serialize() => utf8.encode(jsonEncode(<String, Object>{
        ...payload(),
        'sp': base64Encode(sigPub),
        'sg': base64Encode(signature),
      }));

  static MlsWelcome? parse(Uint8List bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return MlsWelcome(
        groupId: j['g'] as String,
        capacity: j['n'] as int,
        epoch: j['e'] as int,
        myLeaf: j['l'] as int,
        members: [
          for (final a in (j['m'] as List))
            (
              (a as Map)['l'] as int,
              MlsKeyPackage.fromJson(Map<String, Object?>.from(a['kp'] as Map))
            )
        ],
        treePubs: [
          for (final p in (j['t'] as List))
            ((p as Map)['n'] as int, base64Decode(p['k'] as String))
        ],
        sealedEpochSecret: Uint8List.fromList(base64Decode(j['w'] as String)),
        sigPub: base64Decode(j['sp'] as String),
        signature: base64Decode(j['sg'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

// ————— حالة الشجرة والمجموعة —————

class _Node {
  List<int>? pub; // مفتاح X25519 العام للعقدة (null = فارغة)
  List<int>? seed; // سر العقدة — يحمله من اشتقاقه/فكه فقط
  List<int> unmerged = <int>[]; // أوراق أضيفت تحته وهو عاملاً (RFC §7.2)

  bool get blank => pub == null;
}

/// مجموعة MLS — الحالة الحالية لعضو واحد (كل عضو يبني نفسها من الكومتات).
class MlsGroup {
  MlsGroup._({
    required this.groupId,
    required this.nLeaves,
    required this.myLeaf,
    required this.sigPair,
  })  : nodes = List<_Node>.generate(nodeCount(nLeaves), (_) => _Node()),
        members = List<MlsKeyPackage?>.filled(nLeaves, null, growable: false);

  final String groupId;
  final int nLeaves;
  int myLeaf;
  int epoch = 0;
  Uint8List epochSecret = Uint8List(0);
  final List<_Node> nodes;
  final List<MlsKeyPackage?> members;
  final SimpleKeyPair sigPair; // توقيع الهوية — ثابت عبر العهود

  /// زوج KEM ورقتي الحالي (من حزمة مفاتيحي عند الانضمام، ومن كومتي عند
  /// كل تحديث) — به أفك الأظرفة الموجهة لورقتي.
  SimpleKeyPair? _ownLeafKem;
  int _myGen = 0;
  final Map<int, int> _seenMaxGen = <int, int>{};
  final List<(int, MlsKeyPackage)> _pendingAdds = <(int, MlsKeyPackage)>[];
  final List<int> _pendingRemoves = <int>[];

  // ————— الإنشاء والانضمام —————

  /// إنشاء مجموعة جديدة بسعة ثابتة — المنشئ في الورقة 0 ويكيّف مساره
  /// كاملاً؛ سر المجموعة الأولي عشوائي مستقل عن سر ورقته.
  static Future<MlsGroup> create({
    required String groupId,
    required SimpleKeyPair sigPair,
    required String myMemberId,
    int capacity = 8,
  }) async {
    if (capacity < 1) {
      throw ArgumentError('سعة المجموعة يجب أن تكون 1 على الأقل');
    }
    final g = MlsGroup._(
        groupId: groupId, nLeaves: capacity, myLeaf: 0, sigPair: sigPair);
    final initSecret = _secureRandom(32);
    final leafSecret = _secureRandom(32);
    final spk = (await sigPair.extractPublicKey()).bytes;
    g.members[0] = MlsKeyPackage(
      memberId: myMemberId,
      kemPub: const [],
      sigPub: spk,
    );
    await g._rekeyPath(leafSecret);
    g.epochSecret = await MlsCrypto.hkdf(
        initSecret, utf8.encode(groupId), MlsCrypto.infoEpoch, 32);
    return g;
  }

  /// إعادة تكييف مساري الحالي بسر ورقة جديد — بدون أظرفة ولا تقدم عهد
  /// (تستعمله لحظة الإنشاء؛ الكومت يستعمل مساراً مماثلاً بأظرفة).
  Future<void> _rekeyPath(List<int> leafSecret) async {
    final path = directPath(myLeaf, nLeaves);
    var secret = Uint8List.fromList(leafSecret);
    for (var i = 0; i < path.length; i++) {
      final idx = path[i];
      if (i > 0) {
        secret = await MlsCrypto.hkdf(secret,
            [idx & 0xff, (idx >> 8) & 0xff], MlsCrypto.infoNode, 32);
      }
      final pair = await MlsCrypto.nodePair(secret, idx);
      nodes[idx]
        ..seed = Uint8List.fromList(secret)
        ..pub = await MlsCrypto.pubOf(pair)
        ..unmerged = <int>[];
      if (idx == path.first) _ownLeafKem = pair;
    }
  }

  /// انضمام من ترحيب: لقطة الشجرة + سر العهد مغلفاً بحزمة مفاتيحي —
  /// أملك سر ورقتي (زوج حزمتي) فأفك الأظرفة الموجهة لورقتي لاحقاً،
  /// ولا شيء يصلني من ما قبل عهدي.
  static Future<MlsGroup?> joinFromWelcome({
    required Uint8List welcomeBytes,
    required SimpleKeyPair sigPair,
    required SimpleKeyPair myLeafKem,
    required String myMemberId,
  }) async {
    final w = MlsWelcome.parse(welcomeBytes);
    if (w == null) return null;
    final n = w.capacity;
    if (n < 1 || w.myLeaf < 0 || w.myLeaf >= n) return null;
    final g = MlsGroup._(
        groupId: w.groupId, nLeaves: n, myLeaf: w.myLeaf, sigPair: sigPair);
    g.epoch = w.epoch;
    g._ownLeafKem = myLeafKem;
    final myPub = (await myLeafKem.extractPublicKey()).bytes;
    for (final (slot, kp) in w.members) {
      if (slot < 0 || slot >= n) return null;
      g.members[slot] = kp;
      if (kp.memberId == myMemberId) {
        g.myLeaf = slot;
        // حزمتي المسجلة يجب أن تطابق زوجي الذي أتيت به
        if (!_bytesEqual(kp.kemPub, myPub)) return null;
      }
    }
    if (g.members[g.myLeaf] == null) return null;
    for (final (idx, pub) in w.treePubs) {
      if (idx < 0 || idx >= nodeCount(n)) return null;
      g.nodes[idx].pub = pub;
    }
    final secret = await MlsCrypto.open(
      myLeafKem,
      w.sealedEpochSecret,
      _welcomeAad(w.groupId, w.epoch, w.myLeaf),
    );
    if (secret == null || secret.length != 32) return null;
    g.epochSecret = secret;
    return g;
  }

  // ————— المقترحات والكومت —————

  /// إضافة عضو: أول ورقة فارغة — null إن امتلأت السعة
  int? addProposal(MlsKeyPackage kp) {
    for (var i = 0; i < nLeaves; i++) {
      if (members[i] == null) {
        _pendingAdds.add((i, kp));
        return i;
      }
    }
    return null;
  }

  /// إزالة عضو بورقته (من يكوم ينفذ المقترحات المعلقة)
  void removeProposal(int leafIdx) {
    if (leafIdx == myLeaf) {
      throw ArgumentError('لا يمكن إزالة نفسي بمقترح');
    }
    if (members[leafIdx] != null) _pendingRemoves.add(leafIdx);
  }

  /// الكومت: يطبق المقترحات المعلقة + يعيد تكييف مسار الكاتب كاملاً +
  /// يغلف أسرار المسار لعُقد resolution الأطفال ويسجل كل شيء بتوقيعه —
  /// ثم يتقدم العهد. يعيد (الكومت، الترحيبات للجدد).
  Future<(MlsCommit, List<MlsWelcome>)?> commit() async {
    final adds = [..._pendingAdds];
    final removes = [..._pendingRemoves];
    _pendingAdds.clear();
    _pendingRemoves.clear();
    for (final (slot, kp) in adds) {
      members[slot] = kp;
      nodes[leafNodeIndex(slot, nLeaves)].pub = kp.kemPub;
      for (final a in _ancestorsOf(leafNodeIndex(slot, nLeaves))) {
        if (!nodes[a].blank) nodes[a].unmerged.add(slot);
      }
    }
    for (final slot in removes) {
      members[slot] = null;
      nodes[leafNodeIndex(slot, nLeaves)].pub = null;
      nodes[leafNodeIndex(slot, nLeaves)].seed = null;
    }
    final leafSecret = _secureRandom(32);
    final prevEpochSecret = epochSecret;
    final (commit, welcomes) = await _buildCommit(
        leafSecret, adds, removes, prevEpochSecret);
    epoch++;
    return (commit, welcomes);
  }

  Future<(MlsCommit, List<MlsWelcome>)> _buildCommit(
    List<int> leafSecret,
    List<(int, MlsKeyPackage)> adds,
    List<int> removes,
    Uint8List prevEpochSecret,
  ) async {
    final path = directPath(myLeaf, nLeaves);
    // أسرار المسار: ورقة → جذر بالاشتقاق الموقع بالفهرس
    final pathSecrets = <int, List<int>>{path.first: leafSecret};
    for (var i = 1; i < path.length; i++) {
      final child = path[i - 1];
      final parent = path[i];
      pathSecrets[parent] = await MlsCrypto.hkdf(
          pathSecrets[child]!,
          [parent & 0xff, (parent >> 8) & 0xff],
          MlsCrypto.infoNode,
          32);
    }
    final pathPubs = <(int, List<int>)>[];
    for (final idx in path) {
      final pair = await MlsCrypto.nodePair(pathSecrets[idx]!, idx);
      pathPubs.add((idx, await MlsCrypto.pubOf(pair)));
      if (idx == path.first) _ownLeafKem = pair; // زوج ورقتي الجديد
      nodes[idx]
        ..seed = Uint8List.fromList(pathSecrets[idx]!)
        ..pub = pathPubs.last.$2
        ..unmerged = <int>[]; // عقدة أُعيد تكييفها — أوراقها المدمجة تُصفّر
    }

    // الأظرفة: لكل عقدة مسار P (عدا الورقة): resolution للطفل غير
    // المحدَّث — الجدد في نفس الكومت مستثنون (RFC §7.10.1)
    final envelopes = <(int, int, Uint8List)>[];
    final newLeafSlots = adds.map((e) => e.$1).toSet();
    for (var i = 1; i < path.length; i++) {
      final p = path[i];
      final childOnPath = path[i - 1];
      final copathChild =
          childNodes(p).firstWhere((c) => c != childOnPath);
      final res = _resolutionExcluding(copathChild, newLeafSlots);
      final ps = pathSecrets[p]!;
      for (final t in res) {
        final targetPub = nodes[t].pub;
        if (targetPub == null) continue;
        final sealed =
            await MlsCrypto.seal(targetPub, ps, _envelopeAad(p, t));
        envelopes.add((t, p, sealed));
      }
    }

    // سر العهد الجديد من سر جذر المسار — لا مشتاق عكسي
    final newEpochSecret = await MlsCrypto.hkdf(
        pathSecrets[path.last]!, prevEpochSecret, MlsCrypto.infoEpoch, 32);
    epochSecret = newEpochSecret;
    _myGen = 0;
    _seenMaxGen.clear();

    // الترحيبات للجدد: سر العهد الجديد مغلفاً بحزمة مفاتيح كل مضاف
    final spk = (await sigPair.extractPublicKey()).bytes;
    final welcomes = <MlsWelcome>[];
    for (final (slot, kp) in adds) {
      final sealedEpoch = await MlsCrypto.seal(
        kp.kemPub,
        newEpochSecret,
        _welcomeAad(groupId, epoch + 1, slot),
      );
      final w = MlsWelcome(
        groupId: groupId,
        capacity: nLeaves,
        epoch: epoch + 1,
        myLeaf: slot,
        members: [
          for (var i = 0; i < nLeaves; i++)
            if (members[i] != null) (i, members[i]!)
        ],
        treePubs: [
          for (var i = 0; i < nodes.length; i++)
            if (!nodes[i].blank) (i, nodes[i].pub!)
        ],
        sealedEpochSecret: sealedEpoch,
        sigPub: spk,
        signature: const [],
      );
      welcomes.add(MlsWelcome(
        groupId: w.groupId,
        capacity: w.capacity,
        epoch: w.epoch,
        myLeaf: w.myLeaf,
        members: w.members,
        treePubs: w.treePubs,
        sealedEpochSecret: w.sealedEpochSecret,
        sigPub: w.sigPub,
        signature: await MlsCrypto.sign(utf8.encode(jsonEncode(w.payload())), sigPair),
      ));
    }

    final commit = MlsCommit(
      epoch: epoch,
      updaterLeaf: myLeaf,
      adds: adds,
      removes: removes,
      pathPubs: pathPubs,
      envelopes: envelopes,
      sigPub: spk,
      signature: const [],
    );
    final signed = MlsCommit(
      epoch: commit.epoch,
      updaterLeaf: commit.updaterLeaf,
      adds: commit.adds,
      removes: commit.removes,
      pathPubs: commit.pathPubs,
      envelopes: commit.envelopes,
      sigPub: commit.sigPub,
      signature:
          await MlsCrypto.sign(utf8.encode(jsonEncode(commit.payload())), sigPair),
    );
    return (signed, welcomes);
  }

  /// تطبيق كومت صادر عن عضو آخر — تحقق التوقيع بهوية الكاتب **المسجلة**
  /// (لا بما يرفقه الكومت)، ثم فك أعمق غلاف أملك مفتاح عقدته، ثم اشتقاق
  /// الأعلى مع مطابقة العموميات المرسلة (تحقق RFC §7.10.1)، ثم تقدم العهد.
  /// false عند عبث/عهد خاطئ/تعذر الفك.
  Future<bool> applyCommit(Uint8List commitBytes) async {
    final c = MlsCommit.parse(commitBytes);
    if (c == null) return false;
    if (c.epoch != epoch) return false; // الكومت للعهد الحالي حصراً
    if (c.updaterLeaf == myLeaf) return false; // كومتي أطبقه لا أستقبله
    final updater = members[c.updaterLeaf];
    if (updater == null) return false;
    if (!_bytesEqual(updater.sigPub, c.sigPub)) return false;
    if (!await MlsCrypto.verify(
        utf8.encode(jsonEncode(c.payload())), c.signature, updater.sigPub)) {
      return false;
    }

    // 1) المقترحات بنفس ترتيب الكاتب
    for (final (slot, kp) in c.adds) {
      members[slot] = kp;
      nodes[leafNodeIndex(slot, nLeaves)].pub = kp.kemPub;
      for (final a in _ancestorsOf(leafNodeIndex(slot, nLeaves))) {
        if (!nodes[a].blank) nodes[a].unmerged.add(slot);
      }
    }
    for (final slot in c.removes) {
      members[slot] = null;
      nodes[leafNodeIndex(slot, nLeaves)].pub = null;
      nodes[leafNodeIndex(slot, nLeaves)].seed = null;
    }

    // 2) دمج المسار: أفرغ مسار الكاتب القديم وأضع عموميات الجديد
    for (final idx in directPath(c.updaterLeaf, nLeaves)) {
      nodes[idx]
        ..pub = null
        ..seed = null
        ..unmerged = <int>[];
    }
    for (final (idx, pub) in c.pathPubs) {
      nodes[idx].pub = pub; // السر ليس لي إلا ما أفكه أدناه
    }

    // 3) فك أسرار المسار: أول غلاف لعقدة أملك مفتاحها
    List<int>? foundSecret;
    int? foundNode;
    for (final (t, p, sealed) in c.envelopes) {
      final pair = await _heldPairFor(t);
      if (pair == null) continue;
      final ps = await MlsCrypto.open(pair, sealed, _envelopeAad(p, t));
      if (ps != null && ps.length == 32) {
        foundSecret = ps;
        foundNode = t;
        break;
      }
    }
    if (foundSecret == null || foundNode == null) return false;

    // 4) عقدة المسار P التي كان فكّي لسرها (T داخل طفلها غير المحدَّث)
    final cPath = directPath(c.updaterLeaf, nLeaves);
    int? pIdx;
    for (var i = 1; i < cPath.length; i++) {
      final childOnPath = cPath[i - 1];
      final copathChild =
          childNodes(cPath[i]).firstWhere((x) => x != childOnPath);
      if (_subtreeContains(copathChild, foundNode)) {
        pIdx = cPath[i];
        break;
      }
    }
    if (pIdx == null) return false;

    // 5) اشتقاق الأعلى من P حتى الجذر مع مطابقة العموميات المرسلة
    var secret = Uint8List.fromList(foundSecret);
    final startIdx = cPath.indexOf(pIdx);
    for (var i = startIdx; i < cPath.length; i++) {
      final idx = cPath[i];
      final pair = await MlsCrypto.nodePair(secret, idx);
      final pub = await MlsCrypto.pubOf(pair);
      final sent = nodes[idx].pub;
      if (sent == null || !_bytesEqual(sent, pub)) return false;
      nodes[idx].seed = Uint8List.fromList(secret);
      if (i + 1 < cPath.length) {
        final parent = cPath[i + 1];
        secret = await MlsCrypto.hkdf(secret,
            [parent & 0xff, (parent >> 8) & 0xff], MlsCrypto.infoNode, 32);
      }
    }

    // 6) تقدم العهد من سر الجذر
    epochSecret =
        await MlsCrypto.hkdf(secret, epochSecret, MlsCrypto.infoEpoch, 32);
    epoch++;
    _myGen = 0;
    _seenMaxGen.clear();
    return true;
  }

  // ————— حماية الرسائل بمفتاح المرسل وسلسلة الأجيال —————

  /// حماية رسالة تطبيقية: مفتاح مرسل ورقتي بسلسلة أجيال، AAD يربط
  /// المجموعة والعهد والورقة والجيل — إطار (leaf|gen|nonce|ct|mac).
  Future<Uint8List> protect(List<int> plaintext) async {
    for (final b in plaintext) {
      if (b < 0 || b > 255) {
        throw ArgumentError('الحمولة بايتات حصراً — مرر utf8.encode لا codeUnits');
      }
    }
    final senderSecret = await MlsCrypto.hkdf(
        epochSecret,
        [myLeaf & 0xff, (myLeaf >> 8) & 0xff],
        MlsCrypto.infoSender,
        32);
    final gen = _myGen;
    final kn = await MlsCrypto.hkdf(senderSecret,
        [gen & 0xff, (gen >> 8) & 0xff], MlsCrypto.infoGen, 44);
    final ct = await MlsCrypto.aesEncrypt(
        kn.sublist(0, 32), kn.sublist(32, 44), plaintext, _frameAad(myLeaf, gen));
    _myGen++;
    final head = ByteData(8)
      ..setUint32(0, myLeaf, Endian.little)
      ..setUint32(4, gen, Endian.little);
    return Uint8List.fromList(
        [...head.buffer.asUint8List(), ...ct]);
  }

  /// فك إطار — null عند مفتاح خاطئ (مزال/عهد قديم/مجموعة أخرى) أو عبث
  /// أو إعادة عرض داخل العهد (الجيل لا يتراجع لكل مرسل).
  Future<Uint8List?> unprotect(Uint8List frame) async {
    if (frame.length < 8 + 16) return null;
    final bd = ByteData.sublistView(frame);
    final leaf = bd.getUint32(0, Endian.little);
    final gen = bd.getUint32(4, Endian.little);
    if (leaf >= nLeaves || members[leaf] == null) return null;
    if (gen <= (_seenMaxGen[leaf] ?? -1)) return null;
    final senderSecret = await MlsCrypto.hkdf(
        epochSecret,
        [leaf & 0xff, (leaf >> 8) & 0xff],
        MlsCrypto.infoSender,
        32);
    final kn = await MlsCrypto.hkdf(senderSecret,
        [gen & 0xff, (gen >> 8) & 0xff], MlsCrypto.infoGen, 44);
    final pt = await MlsCrypto.aesDecrypt(
      kn.sublist(0, 32),
      kn.sublist(32, 44),
      frame.sublist(8),
      _frameAad(leaf, gen),
    );
    if (pt == null) return null;
    _seenMaxGen[leaf] = gen;
    return pt;
  }

  // ————— أدوات داخلية —————

  /// resolution لعقدة (RFC §2.5.3): عاملة = [العقدة + أوراقها غير المدمجة]،
  /// ورقة فارغة = []، داخلية فارغة = دمج أبنائها — مع استثناء أوراق الجدد
  /// في نفس الكومت.
  List<int> _resolutionExcluding(int nodeIdx, Set<int> excludeLeaves) {
    final node = nodes[nodeIdx];
    if (nodeIdx >= nLeaves - 1) {
      if (node.blank) return const [];
      final leaf = leafIndexOfNode(nodeIdx, nLeaves);
      return excludeLeaves.contains(leaf) ? const [] : [nodeIdx];
    }
    if (!node.blank) {
      final out = <int>[nodeIdx];
      for (final leafSlot in node.unmerged) {
        final leafIdx = leafNodeIndex(leafSlot, nLeaves);
        if (!excludeLeaves.contains(leafSlot)) out.add(leafIdx);
      }
      return out;
    }
    final out = <int>[];
    for (final c in childNodes(nodeIdx)) {
      out.addAll(_resolutionExcluding(c, excludeLeaves));
    }
    return out;
  }

  /// زوجي الخاص لعقدة الهدف: ورقتي (زوجي الحالي) أو عقدة أحمل سرها
  Future<SimpleKeyPair?> _heldPairFor(int nodeIdx) async {
    if (nodeIdx >= nLeaves - 1) {
      final leaf = leafIndexOfNode(nodeIdx, nLeaves);
      return leaf == myLeaf ? _ownLeafKem : null;
    }
    final seed = nodes[nodeIdx].seed;
    if (seed == null) return null;
    return MlsCrypto.nodePair(seed, nodeIdx);
  }

  bool _subtreeContains(int rootIdx, int nodeIdx) {
    if (nodeIdx == rootIdx) return true;
    var cur = nodeIdx;
    while (cur > rootIdx) {
      final p = parentNode(cur);
      if (p == null) return false;
      if (p == rootIdx) return true;
      cur = p;
    }
    return false;
  }

  List<int> _ancestorsOf(int nodeIdx) {
    final out = <int>[];
    var cur = nodeIdx;
    while (true) {
      final p = parentNode(cur);
      if (p == null) break;
      out.add(p);
      cur = p;
    }
    return out;
  }

  List<int> _envelopeAad(int pathNodeIdx, int targetIdx) =>
      utf8.encode('wasl-mls-env|$groupId|$epoch|$pathNodeIdx|$targetIdx');

  static List<int> _welcomeAad(String groupId, int epoch, int leaf) =>
      utf8.encode('wasl-mls-welcome|$groupId|$epoch|$leaf');

  List<int> _frameAad(int leaf, int gen) =>
      utf8.encode('wasl-mls-frame|$groupId|$epoch|$leaf|$gen');

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// عشوائية تشفيرية من الخدمة الآمنة للنظام — بلا بذور قابلة للتكرار.
Uint8List _secureRandom(int len) {
  final rng = Random.secure();
  return Uint8List.fromList(
      List<int>.generate(len, (_) => rng.nextInt(256)));
}
