import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/ratchet.dart';

/// اختبارات نقية لنواة السرية الأمامية: X3DH + Double Ratchet (بلا شبكة ولا تخزين)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const convId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const otherConv = 'ffffffff-1111-2222-3333-444444444444';

  /// يشغّل تبادلاً كاملاً بين طرفين ويعيد أدواته
  Future<({
    SimpleKeyPair ikA,
    SimpleKeyPair ikB,
    SimpleKeyPair prekeyB,
    SimpleKeyPair ekA,
  })> makeKeys() async {
    final ikA = await RatchetCrypto.newKeyPair();
    final ikB = await RatchetCrypto.newKeyPair();
    final prekeyB = await RatchetCrypto.newKeyPair();
    final ekA = await RatchetCrypto.newKeyPair();
    return (ikA: ikA, ikB: ikB, prekeyB: prekeyB, ekA: ekA);
  }

  /// X3DH كامل: يبني جلسة المبادر وجلسة المستجيب
  Future<(RatchetState, RatchetState)> establish() async {
    final (ikA: a, ikB: b, prekeyB: pk, ekA: ek) = await makeKeys();
    final skInit = await RatchetCrypto.initiatorSecret(
      identityMine: a,
      identityRemote: await b.extractPublicKey(),
      ephemeral: ek,
      prekeyRemote: await pk.extractPublicKey(),
    );
    final skResp = await RatchetCrypto.responderSecret(
      identityMine: b,
      identityRemote: await a.extractPublicKey(),
      prekeyMine: pk,
      ephemeralRemote: await ek.extractPublicKey(),
    );
    // نقطة التحقق 1: السرّان متطابقان
    expect(base64Encode(skInit), base64Encode(skResp));

    // الجلسة الأولية للمبادر: مفتاح التدوير هو المفتاح الأولي للطرف
    final stA = await DoubleRatchet.startInitiator(
      sk: skInit,
      remoteRatchetPub: await pk.extractPublicKey(),
      ekB64: base64Encode((await ek.extractPublicKey()).bytes),
      prekeyId: 77,
    );
    final stB = await DoubleRatchet.startResponder(sk: skResp, ratchetPair: pk);
    return (stA, stB);
  }

  test('X3DH: سرّ الطرفين متطابق ومختلف عن أزواج أخرى', () async {
    final (ikA: a, ikB: b, prekeyB: pk, ekA: ek) = await makeKeys();
    final s1 = await RatchetCrypto.initiatorSecret(
      identityMine: a,
      identityRemote: await b.extractPublicKey(),
      ephemeral: ek,
      prekeyRemote: await pk.extractPublicKey(),
    );
    final s2 = await RatchetCrypto.responderSecret(
      identityMine: b,
      identityRemote: await a.extractPublicKey(),
      prekeyMine: pk,
      ephemeralRemote: await ek.extractPublicKey(),
    );
    expect(base64Encode(s1), base64Encode(s2));
    expect(s1.length, 32);

    // مفتاح أولي آخر → سرّ مختلف
    final other = await RatchetCrypto.newKeyPair();
    final s3 = await RatchetCrypto.initiatorSecret(
      identityMine: a,
      identityRemote: await b.extractPublicKey(),
      ephemeral: ek,
      prekeyRemote: await other.extractPublicKey(),
    );
    expect(base64Encode(s3), isNot(base64Encode(s1)));
  });

  test('محادثة كاملة بالاتجاهين مع تدوير متبادل', () async {
    var (stA, stB) = await establish();
    String? w1;
    w1 = await DoubleRatchet.encrypt(stA, convId, 'مرحبا يا صديقي 🌟');
    expect(w1, startsWith('v2.'));
    expect(DoubleRatchet.isInitialWire(w1!), isTrue,
        reason: 'أول رسالة تحمل حقلي e وk');
    expect(await DoubleRatchet.decrypt(stB, convId, w1), 'مرحبا يا صديقي 🌟');

    // رد المستجيب: تدوير DH جديد عنده ومفتاح إرسال جديد
    final w2 = await DoubleRatchet.encrypt(stB, convId, 'أهلاً! كيف حالك؟');
    expect(await DoubleRatchet.decrypt(stA, convId, w2!), 'أهلاً! كيف حالك؟');
    expect(DoubleRatchet.isInitialWire(w2), isFalse);

    // جولتان أخريان — كل رسالة مفتاحها مختلف
    final w3 = await DoubleRatchet.encrypt(stA, convId, 'بخير الحمد لله');
    final w4 = await DoubleRatchet.encrypt(stA, convId, 'وش أخبارك اليوم؟');
    expect(w3, isNot(w4));
    expect(await DoubleRatchet.decrypt(stB, convId, w3!), 'بخير الحمد لله');
    expect(await DoubleRatchet.decrypt(stB, convId, w4!), 'وش أخبارك اليوم؟');
    final w5 = await DoubleRatchet.encrypt(stB, convId, 'تمام والحمد لله');
    expect(await DoubleRatchet.decrypt(stA, convId, w5!), 'تمام والحمد لله');
  });

  test('رسائل وصلت بلا ترتيب: تُفك كلها بالمفاتيح المتخطاة', () async {
    var (stA, stB) = await establish();
    final w1 = await DoubleRatchet.encrypt(stA, convId, 'واحد');
    final w2 = await DoubleRatchet.encrypt(stA, convId, 'اثنان');
    final w3 = await DoubleRatchet.encrypt(stA, convId, 'ثلاثة');
    expect(await DoubleRatchet.decrypt(stB, convId, w3!), 'ثلاثة');
    expect(await DoubleRatchet.decrypt(stB, convId, w1!), 'واحد');
    expect(await DoubleRatchet.decrypt(stB, convId, w2!), 'اثنان');
  });

  test('عبث في نص التشفير أو الترويسة → null والجلسة تكمل بعدها', () async {
    var (stA, stB) = await establish();
    final w = (await DoubleRatchet.encrypt(stA, convId, 'سر'))!;
    final parts = w.split('.');
    final bad = 'v2.${parts[1]}.${'A${parts[2].substring(1)}'}.${parts[3]}';
    expect(await DoubleRatchet.decrypt(stB, convId, bad), isNull);

    // رسالة التالية السليمة تعمل
    final w2 = await DoubleRatchet.encrypt(stA, convId, 'التالية');
    expect(await DoubleRatchet.decrypt(stB, convId, w2!), 'التالية');
  });

  test('AAD: رسالة لا تُفك في محادثة أخرى', () async {
    var (stA, stB) = await establish();
    final w = await DoubleRatchet.encrypt(stA, convId, 'خصوصية');
    expect(await DoubleRatchet.decrypt(stB, otherConv, w!), isNull);
  });

  test('إعادة إرسال الرسالة ذاتها (Replay) → ثاني مرة null', () async {
    var (stA, stB) = await establish();
    final w = await DoubleRatchet.encrypt(stA, convId, 'مرة واحدة');
    expect(await DoubleRatchet.decrypt(stB, convId, w!), 'مرة واحدة');
    expect(await DoubleRatchet.decrypt(stB, convId, w), isNull);
  });

  test('حفظ/تحميل الحالة JSON وسط المحادثة يستكمل بلا انقطاع', () async {
    var (stA, stB) = await establish();
    final w1 = await DoubleRatchet.encrypt(stA, convId, 'قبل الحفظ');
    expect(await DoubleRatchet.decrypt(stB, convId, w1!), 'قبل الحفظ');

    // حفظ الطرفين وتحميلهما من جديد (كما يحدث بين استخدامات التطبيق)
    stA = RatchetState.tryDecode(stA.encode())!;
    stB = RatchetState.tryDecode(stB.encode())!;

    final w2 = await DoubleRatchet.encrypt(stA, convId, 'بعد التحميل');
    expect(await DoubleRatchet.decrypt(stB, convId, w2!), 'بعد التحميل');
    final w3 = await DoubleRatchet.encrypt(stB, convId, 'وأنا أيضاً');
    expect(await DoubleRatchet.decrypt(stA, convId, w3!), 'وأنا أيضاً');
  });

  test('تدوير متعدد: تبادل طويل يبقى متسقاً', () async {
    var (stA, stB) = await establish();
    var speaker = 'a';
    for (var i = 0; i < 12; i++) {
      final w = speaker == 'a'
          ? await DoubleRatchet.encrypt(stA, convId, 'رسالة $i')
          : await DoubleRatchet.encrypt(stB, convId, 'رسالة $i');
      final plain = speaker == 'a'
          ? await DoubleRatchet.decrypt(stB, convId, w!)
          : await DoubleRatchet.decrypt(stA, convId, w!);
      expect(plain, 'رسالة $i');
      speaker = speaker == 'a' ? 'b' : 'a';
    }
  });

  test('رسالة افتتاحية معاد تشغيلها لا تستبدل جلسة مستخدمة (علم used)', () async {
    var (stA, stB) = await establish();
    final w1 = await DoubleRatchet.encrypt(stA, convId, 'افتتاح');
    expect(await DoubleRatchet.decrypt(stB, convId, w1!), 'افتتاح');
    expect(stB.used, isTrue);
    // علم used يمنع في الخدمة استبدال الجلسة برسالة افتتاحية قديمة
    expect(DoubleRatchet.isInitialWire(w1), isTrue);
  });

  test('أسوأ رسالة v2 (افتتاحية بأقصى حد 2600 بايت) تبقى داخل قيد 4000 حرف', () async {
    var (stA, stB) = await establish();
    final worst = 'أ' * 1300; // 2600 بايت UTF-8 — أثقل نص مسموح
    expect(utf8.encode(worst).length, 2600);
    final w = (await DoubleRatchet.encrypt(stA, convId, worst))!;
    expect(w.startsWith('v2.'), isTrue);
    // افتتاحية الأثقل ترويسةً: تحمل e وk إضافة إلى d/n/p
    expect(DoubleRatchet.isInitialWire(w), isTrue);
    expect(w.length, lessThan(4000));
    // والرسالة سليمة بعد الفك
    expect(await DoubleRatchet.decrypt(stB, convId, w), worst);
  });
}
