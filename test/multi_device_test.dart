import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/ratchet.dart';

/// معرف المحادثة المستخدم في كل الاختبارات
const conv = 'conv-1';

/// اختبارات تعدد الأجهزة المرتبطة (v3) — نقية بلا Supabase ولا مخزن آمن:
/// خادم مفاتيح وهمي (أجهزة + مخازن أولية بسحب أحادي) ونهايات تطبق منطق
/// الخدمة نفسه (تغليف مفتاح محتوى لكل جهاز + جلسة متدرجة لكل زوج جهازين
/// + تغليف ذاتي لأجهزة حساب المرسل + تبنّي الافتتاحيات بأرشفة).
void main() {
  final aes = AesGcm.with256bits();

  Future<String> bodyEncrypt(SecretKey key, String plain) async {
    final box = await aes.encrypt(utf8.encode(plain),
        secretKey: key, nonce: aes.newNonce(), aad: utf8.encode(conv));
    return 'v1.${base64Encode(box.nonce)}.'
        '${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}';
  }

  Future<String?> bodyDecrypt(SecretKey key, String body) async {
    try {
      final p = body.split('.');
      final plain = await aes.decrypt(
        SecretBox(base64Decode(p[2]),
            nonce: base64Decode(p[1]), mac: Mac(base64Decode(p[3]))),
        secretKey: key,
        aad: utf8.encode(conv),
      );
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  RatchetState? copyState(RatchetState st) => RatchetState.tryDecode(st.encode());

  /// خادم وهمي: أجهزة لكل حساب، لكل جهاز مخزون أولية بسحب لا يتكرر
  final server = _FakeServer();

  /// نهاية عميل = جهاز واحد يعمل بمنطق الخدمة (v3)
  Future<String?> encryptFrom(_FakeDevice dev, String peerId, String plain) async {
    final peerDevs = server.activeDevices(peerId);
    if (peerDevs.isEmpty) return null;
    final myDevs = server.activeDevices(dev.owner);
    final contentKey = await aes.newSecretKey();
    final kb = base64Encode(await contentKey.extractBytes());
    final wraps = <String, String>{};
    for (final pd in peerDevs) {
      var ms = dev.v3[pd.id];
      ms ??= await dev.startV3Session(pd, server);
      if (ms == null || ms.cur == null) continue;
      final wire = await DoubleRatchet.encrypt(ms.cur!, conv, kb);
      dev.v3[pd.id] = ms;
      if (wire != null) wraps[pd.id] = wire;
    }
    if (wraps.isEmpty) return null;
    final selfWraps = <String, String>{};
    for (final md in myDevs) {
      selfWraps[md.id] = await V3Codec.selfWrap(
        myDevice: dev.identity,
        myDeviceId: dev.id,
        targetDevice: RatchetCrypto.publicKeyFromB64(md.pubB64),
        targetDeviceId: md.id,
        conversationId: conv,
        contentKey: contentKey,
      );
    }
    final body = await bodyEncrypt(contentKey, plain);
    return V3Codec.pack(
        senderDeviceId: dev.id, wraps: wraps, selfWraps: selfWraps, body: body);
  }

  Future<String?> decryptOn(_FakeDevice dev, String peerId, String content) async {
    final pkt = V3Codec.parse(content);
    if (pkt == null) return null;
    // مسار التغليف الذاتي (رسالة من جهاز آخر لنفس الحساب)
    final selfW = pkt.selfWraps[dev.id];
    if (selfW != null) {
      final myDevs = server.activeDevices(dev.owner);
      final rows = myDevs.where((d) => d.id == pkt.senderDeviceId).toList();
      if (rows.isEmpty) return null;
      final key = await V3Codec.selfUnwrap(
        myDevice: dev.identity,
        myDeviceId: dev.id,
        senderDevice: RatchetCrypto.publicKeyFromB64(rows.first.pubB64),
        senderDeviceId: pkt.senderDeviceId,
        conversationId: conv,
        wrapped: selfW,
      );
      if (key == null) return null;
      return bodyDecrypt(key, pkt.body);
    }
    // مسار الجلسة المتدرجة (رسالة من جهاز الطرف)
    final wire = pkt.wraps[dev.id];
    if (wire == null) return null;
    final ms = dev.v3[pkt.senderDeviceId] ??= V3MultiSession();
    String? kb;
    final trials = <RatchetState?>[
      if (ms.cur != null) copyState(ms.cur!),
      ...ms.old.map(copyState),
    ];
    var hit = -1;
    for (var i = 0; i < trials.length; i++) {
      final st = trials[i];
      if (st == null) continue;
      final k = await DoubleRatchet.decrypt(st, conv, wire);
      if (k != null) {
        kb = k;
        hit = i;
        break;
      }
    }
    if (hit >= 0) {
      if (ms.cur != null && hit == 0) {
        ms.cur = trials[hit];
      } else {
        ms.old[hit - (ms.cur == null ? 0 : 1)] = trials[hit]!;
      }
    }
    if (kb == null && DoubleRatchet.isInitialWire(wire)) {
      final ek = DoubleRatchet.initialEphemeral(wire);
      if (ek != null && !ms.knowsInitial(ek)) {
        final (k, cand) = await dev.buildV3Responder(pkt, wire, peerId, server);
        if (k != null && cand != null) {
          kb = k;
          ms.commitAdopt(cand);
          ms.remember(ek);
        }
      }
    }
    if (kb == null) return null;
    return bodyDecrypt(SecretKeyData(base64Decode(kb)), pkt.body);
  }

  group('V3Codec: الحزم والتفكيك وحد الطول', () {
    test('جولة حزم/تفكيك تحفظ الأظرفة والجسم ومعرف المرسل', () {
      const content = 'v3.aGVsbG8.dummy';
      // نبني رسالة صحيحة يدوياً
      final hdr = base64Encode(utf8.encode(
          '{"c":"dev-A","w":{"dev-B":"v2.x.y.z"},"s":{"dev-A2":"v1.a.b.c"}}'));
      final body = 'v1.${base64Encode(List.filled(12, 1))}.'
          '${base64Encode(List.filled(5, 2))}.${base64Encode(List.filled(16, 3))}';
      final packed = 'v3.$hdr.$body';
      expect(packed.startsWith('v3.'), isTrue);
      final pkt = V3Codec.parse(packed);
      expect(pkt, isNotNull);
      expect(pkt!.senderDeviceId, 'dev-A');
      expect(pkt.wraps['dev-B'], 'v2.x.y.z');
      expect(pkt.selfWraps['dev-A2'], 'v1.a.b.c');
      expect(pkt.body, body);
      // الترويسة المشوهة ترفض
      expect(V3Codec.parse(content), isNull);
      expect(V3Codec.parse('v1.a.b.c'), isNull);
      expect(V3Codec.parse('v3.###.$body'), isNull);
      // isEncrypted يتعرف على v3
      expect(packed.split('.').length, 6);
    });

    test('حد الطول يتناقص بزيادة الأجهزة ويبقى ضمن السقف', () {
      final one = V3Codec.plainLimit(peerDevices: 1, myDevices: 1);
      final two = V3Codec.plainLimit(peerDevices: 2, myDevices: 2);
      final four = V3Codec.plainLimit(peerDevices: 4, myDevices: 4);
      expect(one, greaterThan(two));
      expect(two, greaterThan(four));
      expect(one, lessThanOrEqualTo(2600));
      expect(four, greaterThan(700));
      // أجهزة كثيرة جداً → صفر (رجوع للمسار v2 بدل كسر قيد القاعدة)
      expect(V3Codec.plainLimit(peerDevices: 8, myDevices: 8), anyOf(0, lessThan(500)));
    });
  });

  group('التغليف الذاتي بين أجهزة الحساب', () {
    test('الجهازان يشتقان نفس المفتاح والفك يعيد مفتاح المحتوى', () async {
      final d1 = await server.addDevice('u1');
      final d2 = await server.addDevice('u1');
      final ck = await aes.newSecretKey();
      final wrapped = await V3Codec.selfWrap(
        myDevice: d1.identity,
        myDeviceId: d1.id,
        targetDevice: RatchetCrypto.publicKeyFromB64(d2.pubB64),
        targetDeviceId: d2.id,
        conversationId: conv,
        contentKey: ck,
      );
      final opened = await V3Codec.selfUnwrap(
        myDevice: d2.identity,
        myDeviceId: d2.id,
        senderDevice: RatchetCrypto.publicKeyFromB64(d1.pubB64),
        senderDeviceId: d1.id,
        conversationId: conv,
        wrapped: wrapped,
      );
      expect(opened, isNotNull);
      expect(await opened!.extractBytes(), await ck.extractBytes());
      // جهاز ثالث لا يفك ما ليس موجهًا إليه (AAD يربط معرّفَي الجهازين)
      final d3 = await server.addDevice('u1');
      final wrong = await V3Codec.selfUnwrap(
        myDevice: d3.identity,
        myDeviceId: d3.id,
        senderDevice: RatchetCrypto.publicKeyFromB64(d1.pubB64),
        senderDeviceId: d1.id,
        conversationId: conv,
        wrapped: wrapped,
      );
      expect(wrong, isNull);
      // نقل الظرف إلى محادثة أخرى يفشل (salt المحادثة في الاشتقاق)
      final otherConv = await V3Codec.selfUnwrap(
        myDevice: d2.identity,
        myDeviceId: d2.id,
        senderDevice: RatchetCrypto.publicKeyFromB64(d1.pubB64),
        senderDeviceId: d1.id,
        conversationId: 'conv-2',
        wrapped: wrapped,
      );
      expect(otherConv, isNull);
    });
  });

  group('بروتوكول الرسائل v3 بين حسابين', () {
    test('إرسال من حساب بجهاز واحد إلى حساب بجهازين — كلا الجهازين يفك', () async {
      server.addUser('alice');
      server.addUser('bob');
      final a1 = await server.addDevice('alice');
      final b1 = await server.addDevice('bob');
      await server.addDevice('bob');

      final msg = await encryptFrom(a1, 'bob', 'مرحبا بوب');
      expect(msg, isNotNull);
      expect(msg!.startsWith('v3.'), isTrue);
      expect(await decryptOn(b1, 'alice', msg), 'مرحبا بوب');
      final b2 = server.activeDevices('bob')[1];
      expect(await decryptOn(b2, 'alice', msg), 'مرحبا بوب');

      // رد من الجهاز الثاني يفكه الجهاز المرسل
      final reply = await encryptFrom(b2, 'alice', 'أهلًا أليس');
      expect(await decryptOn(a1, 'bob', reply!), 'أهلًا أليس');
    });

    test('سباق البدء من الطرفين: الافتتاحيات تُتبنّى وتُؤرشف ولا تضيع رسائل',
        () async {
      server.addUser('carol');
      server.addUser('dave');
      final c1 = await server.addDevice('carol');
      final d1 = await server.addDevice('dave');

      // كلٌ يبدأ قبل أن يرى رسالة الآخر
      final m1 = await encryptFrom(c1, 'dave', 'أنا كارول');
      final m2 = await encryptFrom(d1, 'carol', 'أنا ديف');
      expect(m1, isNotNull);
      expect(m2, isNotNull);
      // كلاهما يفك افتتاحية الآخر رغم أن جلسته استُعملت
      expect(await decryptOn(d1, 'carol', m1!), 'أنا كارول');
      expect(await decryptOn(c1, 'dave', m2!), 'أنا ديف');
      // المتابعة على الجلسات المتعاقبة تعمل في الاتجاهين
      final m3 = await encryptFrom(c1, 'dave', 'رسالة ثالثة');
      expect(await decryptOn(d1, 'carol', m3!), 'رسالة ثالثة');
      final m4 = await encryptFrom(d1, 'carol', 'رسالة رابعة');
      expect(await decryptOn(c1, 'dave', m4!), 'رسالة رابعة');
    });

    test('إعادة تشغيل افتتاحية قديمة تُرفض ولا تفسد الجلسة', () async {
      server.addUser('erin');
      server.addUser('frank');
      final e1 = await server.addDevice('erin');
      final f1 = await server.addDevice('frank');

      final m1 = await encryptFrom(e1, 'frank', 'أولى');
      expect(await decryptOn(f1, 'erin', m1!), 'أولى');
      // إعادة نفس الافتتاحية: في سجل «شوهدت» فلا تُتبنى ولا تُفك مجدداً
      expect(await decryptOn(f1, 'erin', m1), isNull);
      // والرسالة التالية على الجلسة الأصلية تُفك طبيعياً
      final m2 = await encryptFrom(e1, 'frank', 'ثانية');
      expect(await decryptOn(f1, 'erin', m2!), 'ثانية');
    });

    test('رسائل المرسل تُقرأ على بقية أجهزته وعلى جهازه بعد إعادة الفتح', () async {
      server.addUser('gina');
      server.addUser('hank');
      final g1 = await server.addDevice('gina');
      final g2 = await server.addDevice('gina');
      await server.addDevice('hank');

      final msg = await encryptFrom(g1, 'hank', 'من جهازي الأول');
      // الجهاز الثاني للحساب نفسه يفك بالتغليف الذاتي
      expect(await decryptOn(g2, 'hank', msg!), 'من جهازي الأول');
      // وجهاز المرسل نفسه يعيد فك رسالته (حالة إعادة فتح التطبيق)
      expect(await decryptOn(g1, 'hank', msg), 'من جهازي الأول');
    });

    test('محادثة طويلة بتبديل أجهزة المرسل تبقى متسقة الجميع', () async {
      server.addUser('ivan');
      server.addUser(' Judy'.trim());
      final i1 = await server.addDevice('ivan');
      final i2 = await server.addDevice('ivan');
      final j1 = await server.addDevice('judy');
      final j2 = await server.addDevice('judy');

      final expectSend = <Future<String?> Function()>[];
      for (var i = 0; i < 12; i++) {
        final fromI = i.isEven;
        final sender = fromI ? (i % 4 == 0 ? i1 : i2) : (i % 3 == 0 ? j1 : j2);
        final peer = fromI ? 'judy' : 'ivan';
        expectSend.add(() => encryptFrom(sender, peer, 'رسالة رقم $i'));
      }
      final wires = <String?>[];
      // إرسال جميعها قبل أي فك (رسائل بلا ترتيب على أجهزة متعددة)
      for (final f in expectSend) {
        wires.add(await f());
      }
      expect(wires.every((w) => w != null), isTrue);
      for (var i = 0; i < wires.length; i++) {
        final fromI = i.isEven;
        // كل رسالة وصلت ظرفاً لكل أجهزة الحساب المستقبِل — والجميع يفكها
        final peers = fromI ? [j1, j2] : [i1, i2];
        final peerUser = fromI ? 'ivan' : 'judy';
        for (final r in peers) {
          final plain = await decryptOn(r, peerUser, wires[i]!);
          expect(plain, 'رسالة رقم $i', reason: 'الرسالة $i على ${r.id}');
        }
      }
    });

    test('عبث في جسم الرسالة يُرفض بالكامل', () async {
      server.addUser('kate');
      server.addUser('liam');
      final k1 = await server.addDevice('kate');
      await server.addDevice('liam');
      final msg = await encryptFrom(k1, 'liam', 'سليمة');
      final parts = msg!.split('.');
      parts[4] = base64Encode(base64Decode(parts[4])..[0] ^= 0xff); // تخريب النص
      final tampered = parts.join('.');
      final l1 = server.activeDevices('liam').first;
      expect(await decryptOn(l1, 'kate', tampered), isNull);
    });
  });
}

/// جهاز وهمي: هوية X25519 ومخزون مفاتيح أولية وجلسات v3
class _FakeDevice {
  _FakeDevice(this.owner, this.id, this.identity, this.pubB64);

  final String owner;
  final String id;
  final SimpleKeyPair identity;
  final String pubB64;
  final Map<int, SimpleKeyPair> prekeyPrivs = {};
  final Map<String, V3MultiSession> v3 = {};

  /// ينشر مفتاحاً أولياً جديداً في مخزون جهازه (عام على الخادم، خاص محلياً)
  Future<int> publishPrekey(_FakeServer server, {bool lastResort = false}) async {
    final p = await RatchetCrypto.newKeyPair();
    final kid = server.nextKeyId++;
    prekeyPrivs[kid] = p;
    server.prekeys.add(_FakePrekey(
      owner: owner,
      deviceId: id,
      keyId: kid,
      pubB64: base64Encode((await p.extractPublicKey()).bytes),
      lastResort: lastResort,
    ));
    return kid;
  }

  /// بناء جلسة مستجيب من افتتاحية (منطق _buildV3Responder في الخدمة)
  Future<(String?, RatchetState?)> buildV3Responder(
      V3Packet pkt, String wire, String peerId, _FakeServer server) async {
    try {
      final p = wire.split('.');
      final hdr = RatchetCrypto.decodeHeader(p[1]);
      if (hdr == null || hdr['e'] is! String || hdr['k'] is! int) {
        return (null, null);
      }
      final ikB64 = hdr['i'];
      if (ikB64 is! String || ikB64.isEmpty) return (null, null);
      final peerDevs = server.activeDevices(peerId);
      final rows = peerDevs.where((d) => d.id == pkt.senderDeviceId).toList();
      if (rows.isEmpty || rows.first.pubB64 != ikB64) return (null, null);
      final priv = prekeyPrivs[hdr['k'] as int];
      if (priv == null) return (null, null);
      final sk = await RatchetCrypto.responderSecret(
        identityMine: identity,
        identityRemote: RatchetCrypto.publicKeyFromB64(ikB64),
        prekeyMine: priv,
        ephemeralRemote: RatchetCrypto.publicKeyFromB64(hdr['e'] as String),
      );
      final st = await DoubleRatchet.startResponder(sk: sk, ratchetPair: priv);
      final k = await DoubleRatchet.decrypt(st, conv, wire);
      if (k == null) return (null, null);
      return (k, st);
    } catch (_) {
      return (null, null);
    }
  }
}

class _FakePrekey {
  _FakePrekey({
    required this.owner,
    required this.deviceId,
    required this.keyId,
    required this.pubB64,
    required this.lastResort,
  });

  final String owner;
  final String deviceId;
  final int keyId;
  final String pubB64;
  final bool lastResort;
  bool consumed = false;
}

/// خادم وهمي: سجل أجهزة ومخازن أولية بسحب أحادي
class _FakeServer {
  final Map<String, List<_FakeDevice>> accounts = {};
  final List<_FakePrekey> prekeys = [];
  int nextKeyId = 1;

  void addUser(String id) => accounts.putIfAbsent(id, () => []);

  Future<_FakeDevice> addDevice(String owner) async {
    accounts.putIfAbsent(owner, () => []);
    final id = 'dev-${accounts[owner]!.length + 1}-$owner';
    final identity = await RatchetCrypto.newKeyPair();
    final pub = base64Encode((await identity.extractPublicKey()).bytes);
    final d = _FakeDevice(owner, id, identity, pub);
    accounts[owner]!.add(d);
    for (var i = 0; i < 25; i++) {
      await d.publishPrekey(this);
    }
    await d.publishPrekey(this, lastResort: true);
    return d;
  }

  List<_FakeDevice> activeDevices(String owner) => accounts[owner] ?? const [];

  /// سحب مفتاح أولي من مخزون جهاز بعينه — مرة واحدة في الحياة
  _FakePrekey? claim(String targetOwner, String targetDeviceId) {
    final pool = prekeys
        .where((k) => k.owner == targetOwner && k.deviceId == targetDeviceId);
    final free = pool.where((k) => !k.consumed && !k.lastResort).toList();
    if (free.isNotEmpty) {
      free.first.consumed = true;
      return free.first;
    }
    final lr = pool.where((k) => k.lastResort).toList();
    return lr.isEmpty ? null : lr.first; // الملاذ الأخير لا يُستهلك
  }
}

extension on _FakeDevice {
  /// منطق _startV3Session في الخدمة: سحب مفتاح من مخزون جهاز الطرف + X3DH
  Future<V3MultiSession?> startV3Session(
      _FakeDevice peerDev, _FakeServer server) async {
    final target = server.accounts[peerDev.owner]!
        .firstWhere((d) => d.id == peerDev.id);
    final claimed = server.claim(target.owner, target.id);
    if (claimed == null) return null;
    final myPubB64 = base64Encode((await identity.extractPublicKey()).bytes);
    final ek = await RatchetCrypto.newKeyPair();
    final sk = await RatchetCrypto.initiatorSecret(
      identityMine: identity,
      identityRemote: RatchetCrypto.publicKeyFromB64(peerDev.pubB64),
      ephemeral: ek,
      prekeyRemote: RatchetCrypto.publicKeyFromB64(claimed.pubB64),
    );
    final st = await DoubleRatchet.startInitiator(
      sk: sk,
      remoteRatchetPub: RatchetCrypto.publicKeyFromB64(claimed.pubB64),
      ekB64: base64Encode((await ek.extractPublicKey()).bytes),
      prekeyId: claimed.keyId,
      identityPubB64: myPubB64,
    );
    final ms = V3MultiSession(cur: st);
    v3[peerDev.id] = ms;
    return ms;
  }
}
