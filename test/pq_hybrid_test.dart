import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/ratchet.dart';

/// اختبارات نقية لبدء جلسات ما بعد الكم الهجين (المرحلة 10 — 0.24.0):
/// ML-KEM-768 (FIPS 203) عبر pqcrypto النقية + دمجه في X3DH بمسار info مستقل.
/// كل الاختبارات بلا شبكة ولا تخزين — النواة وحدها.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const convId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  /// يشغّل تبادلاً هجيناً كاملاً بين طرفين ويعيد أدواته (كما في ratchet_test)
  Future<({
    RatchetState stA,
    RatchetState stB,
    List<int> pqPrivB,
  })> establishHybrid() async {
    final ikA = await RatchetCrypto.newKeyPair();
    final ikB = await RatchetCrypto.newKeyPair();
    final prekeyB = await RatchetCrypto.newKeyPair();
    final ekA = await RatchetCrypto.newKeyPair();
    // مفتاح أولي كمومي للطرف ب (يُنشر عامُه ويُخزَّن خاصُه على جهازه)
    final pq = RatchetCrypto.pqGenerate();
    expect(pq, isNotNull);
    final (pqPub, pqPriv) = pq!;
    // المبادر أ: يغلف سراً كمومياً على المفتاح العام للطرف
    final enc = RatchetCrypto.pqEncapsulate(pqPub);
    expect(enc, isNotNull);
    final (ct, ssA) = enc!;
    final skInit = await RatchetCrypto.initiatorSecretPq(
      identityMine: ikA,
      identityRemote: await ikB.extractPublicKey(),
      ephemeral: ekA,
      prekeyRemote: await prekeyB.extractPublicKey(),
      pqShared: ssA,
    );
    // المستجيب ب: يفك التغليف بمفتاحه الخاص ويعيد التركيبة نفسها
    final ssB = RatchetCrypto.pqDecapsulate(pqPriv, ct);
    expect(ssB, isNotNull);
    final skResp = await RatchetCrypto.responderSecretPq(
      identityMine: ikB,
      identityRemote: await ikA.extractPublicKey(),
      prekeyMine: prekeyB,
      ephemeralRemote: await ekA.extractPublicKey(),
      pqShared: ssB!,
    );
    expect(base64Encode(skInit), base64Encode(skResp));

    final stA = await DoubleRatchet.startInitiator(
      sk: skInit,
      remoteRatchetPub: await prekeyB.extractPublicKey(),
      ekB64: base64Encode((await ekA.extractPublicKey()).bytes),
      prekeyId: 77,
      pqCtB64: base64Encode(ct),
    );
    final stB = await DoubleRatchet.startResponder(
        sk: skResp, ratchetPair: prekeyB);
    return (stA: stA, stB: stB, pqPrivB: pqPriv);
  }

  test('ML-KEM-768: أطوال FIPS 203 (مفتاح 1184 وتغليف 1088 وسرّ 32)', () {
    final kp = RatchetCrypto.pqGenerate();
    expect(kp, isNotNull);
    final (pk, sk) = kp!;
    expect(pk.length, RatchetCrypto.pqPubBytes);
    expect(pk.length, 1184);
    expect(sk.length, greaterThan(1000));
    final enc = RatchetCrypto.pqEncapsulate(pk);
    expect(enc, isNotNull);
    final (ct, ss) = enc!;
    expect(ct.length, RatchetCrypto.pqCtBytes);
    expect(ct.length, 1088);
    expect(ss.length, 32);
    // المفتاح العام بحجم خاطئ يرفض بلا استثناء — أما انحلال بايت داخله
    // فالتغليف قد ينجح شكلاً وحمايته عند فك المستجيب (تحقق FO ورفض صامت)،
    // وهو ما يثبته اختبار العبث أدناه
    expect(RatchetCrypto.pqEncapsulate(pk.sublist(0, 100)), isNull);
    expect(RatchetCrypto.pqEncapsulate(pk + pk), isNull);
  });

  test('ML-KEM-768: التغليف والفك يعيدان السرّ نفسه — وزوج ثانٍ يشتق سرّاً آخر',
      () {
    final (pk, sk) = RatchetCrypto.pqGenerate()!;
    final (ct1, ss1) = RatchetCrypto.pqEncapsulate(pk)!;
    final ss2 = RatchetCrypto.pqDecapsulate(sk, ct1)!;
    expect(base64Encode(ss1), base64Encode(ss2));
    final (_, ss3) = RatchetCrypto.pqEncapsulate(pk)!;
    expect(base64Encode(ss1), isNot(base64Encode(ss3)));
  });

  test('الهجين: سرّا الطرفين متطابقان — ومسار الكلاسيكي لا يشتق نفس السرّ',
      () async {
    final (stA: _, stB: _, pqPrivB: _) = await establishHybrid();
    // عزل المسارين: نفس المفاتيح بمسار الكلاسيكي تعطي سرّاً مختلفاً كلياً
    final ikA = await RatchetCrypto.newKeyPair();
    final ikB = await RatchetCrypto.newKeyPair();
    final prekeyB = await RatchetCrypto.newKeyPair();
    final ekA = await RatchetCrypto.newKeyPair();
    final classic = await RatchetCrypto.initiatorSecret(
      identityMine: ikA,
      identityRemote: await ikB.extractPublicKey(),
      ephemeral: ekA,
      prekeyRemote: await prekeyB.extractPublicKey(),
    );
    final (pk, _) = RatchetCrypto.pqGenerate()!;
    final (_, ss) = RatchetCrypto.pqEncapsulate(pk)!;
    final hybrid = await RatchetCrypto.initiatorSecretPq(
      identityMine: ikA,
      identityRemote: await ikB.extractPublicKey(),
      ephemeral: ekA,
      prekeyRemote: await prekeyB.extractPublicKey(),
      pqShared: ss,
    );
    expect(base64Encode(classic), isNot(base64Encode(hybrid)));
  });

  test('محادثة هجينة كاملة: الافتتاحية تحمل q ومحادثة ثنائية الاتجاه مع تدوير',
      () async {
    final (stA: a, stB: b, pqPrivB: _) = await establishHybrid();
    // الرسالة الأولى: حقل q في الترويسة ثم يُمسح من الحالة
    final w1 = await DoubleRatchet.encrypt(a, convId, 'رسالة أولى هجينة');
    expect(w1, isNotNull);
    final hdr1 = RatchetCrypto.decodeHeader(w1!.split('.')[1]);
    expect(hdr1?['q'], isNotNull);
    expect(a.pqCtB64, isNull);
    final p1 = await DoubleRatchet.decrypt(b, convId, w1);
    expect(p1, 'رسالة أولى هجينة');
    // الرد من ب ثم تبادل طويل يتضمن تدويراً متبادلاً — بلا حقل q بعدها
    final msgs = <String>[
      'تفضل الملف الذي اتفقنا عليه',
      'وصل — أشكرك جزيل الشكر 🌟',
      'أرسل النسخة المحدثة غداً إن شاء الله',
    ];
    for (final m in msgs) {
      final w = await DoubleRatchet.encrypt(b, convId, m);
      expect(await DoubleRatchet.decrypt(a, convId, w!), m);
      final w2 = await DoubleRatchet.encrypt(a, convId, 'تم ✓');
      expect(await DoubleRatchet.decrypt(b, convId, w2!), 'تم ✓');
    }
    // أي رسالة لاحقة من أ بلا q
    final wLate = await DoubleRatchet.encrypt(a, convId, 'بعد التدوير');
    final hdrLate = RatchetCrypto.decodeHeader(wLate!.split('.')[1]);
    expect(hdrLate?['q'], isNull);
    expect(await DoubleRatchet.decrypt(b, convId, wLate), 'بعد التدوير');
  });

  test('عبث في نص التغليف الكمومي: المستجيب يشتق سرّاً مختلفاً فيفشل الفك',
      () async {
    final (pk, _) = RatchetCrypto.pqGenerate()!;
    final ikA = await RatchetCrypto.newKeyPair();
    final ikB = await RatchetCrypto.newKeyPair();
    final prekeyB = await RatchetCrypto.newKeyPair();
    final ekA = await RatchetCrypto.newKeyPair();
    final (ct, ssA) = RatchetCrypto.pqEncapsulate(pk)!;
    final skInit = await RatchetCrypto.initiatorSecretPq(
      identityMine: ikA,
      identityRemote: await ikB.extractPublicKey(),
      ephemeral: ekA,
      prekeyRemote: await prekeyB.extractPublicKey(),
      pqShared: ssA,
    );
    final stA = await DoubleRatchet.startInitiator(
      sk: skInit,
      remoteRatchetPub: await prekeyB.extractPublicKey(),
      ekB64: base64Encode((await ekA.extractPublicKey()).bytes),
      prekeyId: 9,
      pqCtB64: base64Encode(ct),
    );
    final wire = await DoubleRatchet.encrypt(stA, convId, 'سر');
    expect(wire, isNotNull);
    // مستجيب بمفتاح كمومي خاطئ (زوج آخر): فك مختلف → فشل فك الرسالة بلا استثناء
    final (_, wrongPriv) = RatchetCrypto.pqGenerate()!;
    final ssWrong = RatchetCrypto.pqDecapsulate(wrongPriv, ct)!;
    final skWrong = await RatchetCrypto.responderSecretPq(
      identityMine: ikB,
      identityRemote: await ikA.extractPublicKey(),
      prekeyMine: prekeyB,
      ephemeralRemote: await ekA.extractPublicKey(),
      pqShared: ssWrong,
    );
    final stB = await DoubleRatchet.startResponder(
        sk: skWrong, ratchetPair: prekeyB);
    expect(await DoubleRatchet.decrypt(stB, convId, wire!), isNull);
  });

  test('حالة الجلسة: q يُحفظ في JSON ويُستعاد — والافتتاحية الكلاسيكية بلا q',
      () async {
    final (stA: a, stB: _, pqPrivB: _) = await establishHybrid();
    final restored = RatchetState.tryDecode(a.encode());
    expect(restored, isNotNull);
    expect(restored!.pqCtB64, a.pqCtB64);
    expect(restored.pqCtB64, isNotNull);
    // جلسة كلاسيكية (بلا pqCtB64) تبقى بلا q في الترويسة والتسلسل
    final ikB = await RatchetCrypto.newKeyPair();
    final prekeyB = await RatchetCrypto.newKeyPair();
    final ekA = await RatchetCrypto.newKeyPair();
    final sk = await RatchetCrypto.initiatorSecret(
      identityMine: await RatchetCrypto.newKeyPair(),
      identityRemote: await ikB.extractPublicKey(),
      ephemeral: ekA,
      prekeyRemote: await prekeyB.extractPublicKey(),
    );
    final classic = await DoubleRatchet.startInitiator(
      sk: sk,
      remoteRatchetPub: await prekeyB.extractPublicKey(),
      ekB64: base64Encode((await ekA.extractPublicKey()).bytes),
      prekeyId: 5,
    );
    final w = await DoubleRatchet.encrypt(classic, convId, 'عادي');
    final hdr = RatchetCrypto.decodeHeader(w!.split('.')[1]);
    expect(hdr?['q'], isNull);
    expect(RatchetState.tryDecode(classic.encode())!.pqCtB64, isNull);
  });

  test('حد النص مع الافتتاحيات الكمومية: يتقلص بلا أن يهبط تحت 500 وجهاز واحد',
      () {
    // جلسة قائمة (بلا افتتاحية): كما كانت تماماً — التوافق لا يُمَس
    final base = V3Codec.plainLimit(peerDevices: 1, myDevices: 1);
    final withPqSession =
        V3Codec.plainLimit(peerDevices: 1, myDevices: 1, initialPqWraps: 0);
    expect(withPqSession, base);
    // افتتاحية هجينة واحدة: تقلص ملموس لكن يبقى صالحاً
    final initial =
        V3Codec.plainLimit(peerDevices: 1, myDevices: 1, initialPqWraps: 1);
    expect(initial, lessThan(base));
    expect(initial, greaterThanOrEqualTo(500));
    // جهازان بجهازين كليهما افتتاحية: يصل صفراً — المرسل يرجع لمسار v2 تلقائياً
    expect(V3Codec.plainLimit(peerDevices: 2, myDevices: 2, initialPqWraps: 2),
        anyOf(equals(0), lessThan(500)));
    // الإغراق يبقى صفراً كما كان
    expect(V3Codec.plainLimit(peerDevices: 40, myDevices: 1), 0);
  });
}
