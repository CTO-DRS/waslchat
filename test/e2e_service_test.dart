import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/e2e_service.dart';

/// اختبارات وحدة لطبقة التشفير (بدون شبكة: مفتاح محلي بدل اشتقاق ECDH)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final aes = AesGcm.with256bits();
  const convId = '11111111-2222-3333-4444-555555555555';

  Future<SecretKey> newKey() => aes.newSecretKey();

  test('النص: تشفير ثم فك يعيد الأصل (عربي + إيموجي + أسطر)', () async {
    final key = await newKey();
    const plain = 'مرحباً 👋\nهذه رسالة اختبار Wasl Chat — 123';
    final env = await E2eService.encryptText(key, convId, plain);
    expect(E2eService.isEncrypted(env), isTrue);
    expect(env.startsWith('v1.'), isTrue);
    final out = await E2eService.decryptText(key, convId, env);
    expect(out, plain);
  });

  test('النص القديم (غير المشفّر) يمر كما هو', () async {
    final key = await newKey();
    const legacy = 'رسالة قديمة من قبل التشفير';
    final out = await E2eService.decryptText(key, convId, legacy);
    expect(out, legacy);
    expect(E2eService.isEncrypted(legacy), isFalse);
  });

  test('مفتاح خاطئ يعيد null وليس رماية', () async {
    final k1 = await newKey();
    final k2 = await newKey();
    final env = await E2eService.encryptText(k1, convId, 'سر');
    final out = await E2eService.decryptText(k2, convId, env);
    expect(out, isNull);
  });

  test('عبث في النص المشفّر يعيد null (تكامل GCM)', () async {
    final key = await newKey();
    final env = await E2eService.encryptText(key, convId, 'رسالة مهمة');
    final parts = env.split('.');
    final ct = base64Decode(parts[2]);
    ct[0] = ct[0] ^ 0xFF; // عبث بايت واحد
    final tampered = 'v1.${parts[1]}.${base64Encode(ct)}.${parts[3]}';
    final out = await E2eService.decryptText(key, convId, tampered);
    expect(out, isNull);
  });

  test('نقل نص مشفّر إلى محادثة أخرى يفشل (AAD)', () async {
    final key = await newKey();
    final env = await E2eService.encryptText(key, convId, 'سر');
    final otherConv = '99999999-8888-7777-6666-555555555555';
    final out = await E2eService.decryptText(key, otherConv, env);
    expect(out, isNull);
  });

  test('الوسائط: تشفير ثم فك يعيد البايتات', () async {
    final key = await newKey();
    final data = Uint8List.fromList(
        List<int>.generate(4096, (i) => (i * 7 + (i % 251)) & 0xFF));
    final enc = await E2eService.encryptBytes(key, convId, data);
    // الغلاف: 12 بايت nonce + النص + 16 بايت mac
    expect(enc.length, data.length + 12 + 16);
    final out = await E2eService.decryptBytes(key, convId, enc);
    expect(out, data);
  });

  test('الوسائط: ملف قصير/فاسد يعيد null', () async {
    final key = await newKey();
    final short = Uint8List.fromList([1, 2, 3]);
    expect(await E2eService.decryptBytes(key, convId, short), isNull);
  });

  test('حد طول النص قبل التشفير', () {
    // الحد 2600 بايت يبقي أسوأ رسالة v2 (بأثقل ترويستها) داخل قيد 4000 حرف
    expect(E2eService.withinPlainLimit('a' * 2600), isTrue);
    expect(E2eService.withinPlainLimit('أ' * 1500), isFalse); // 3000 بايت UTF-8
  });

  test('حجم الغلاف يبقى داخل قيد قاعدة البيانات (4000 حرف)', () async {
    final key = await newKey();
    // أسوأ حالة: 2900 بايت كلها عربية (2 بايت/حرف → 1450 حرفاً)
    final worst = 'أ' * 1450; // 2900 بايت
    expect(utf8.encode(worst).length, 2900);
    final env = await E2eService.encryptText(key, convId, worst);
    expect(env.length, lessThan(4000));
  });

  // ---------- المرحلة 2: مفاتيح المجموعات ----------

  final x25519 = X25519();

  test('المجموعات: تغليف المفتاح لعضو ثم فكّه يعيد نفس المفتاح', () async {
    final alice = await x25519.newKeyPair();
    final alicePub = await alice.extractPublicKey();
    final bob = await x25519.newKeyPair();
    final bobPub = await bob.extractPublicKey();

    final gkey = await newKey();
    final wrapped = await E2eService.wrapGroupKey(
      groupKey: gkey,
      conversationId: convId,
      wrapperPair: alice,
      memberPub: bobPub,
    );
    expect(E2eService.isEncrypted(wrapped), isTrue);
    expect(wrapped.length, lessThan(700)); // قيد wrapped_key في القاعدة

    final out = await E2eService.unwrapGroupKey(
      wrapped: wrapped,
      conversationId: convId,
      myPair: bob,
      wrapperPub: alicePub,
    );
    expect(out, isNotNull);
    expect(await out!.extractBytes(), await gkey.extractBytes());
  });

  test('المجموعات: عضو ثالث لا يفك ظرفاً لم يُغلَّف له (مفتاح خاطئ)', () async {
    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();
    final eve = await x25519.newKeyPair();
    final bobPub = await bob.extractPublicKey();
    final evePub = await eve.extractPublicKey();

    final gkey = await newKey();
    final wrapped = await E2eService.wrapGroupKey(
      groupKey: gkey,
      conversationId: convId,
      wrapperPair: alice,
      memberPub: bobPub,
    );
    // حاولت عين تفك الظرف بمفتاحها هي (والغلاف مُغلَّف لبوب)
    final out = await E2eService.unwrapGroupKey(
      wrapped: wrapped,
      conversationId: convId,
      myPair: eve,
      wrapperPub: evePub,
    );
    expect(out, isNull);
  });

  test('المجموعات: نقل الظرف إلى محادثة أخرى يفشل (AAD)', () async {
    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();
    final alicePub = await alice.extractPublicKey();
    final bobPub = await bob.extractPublicKey();

    final gkey = await newKey();
    final wrapped = await E2eService.wrapGroupKey(
      groupKey: gkey,
      conversationId: convId,
      wrapperPair: alice,
      memberPub: bobPub,
    );
    final otherConv = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final out = await E2eService.unwrapGroupKey(
      wrapped: wrapped,
      conversationId: otherConv,
      myPair: bob,
      wrapperPub: alicePub,
    );
    expect(out, isNull);
  });

  test('المجموعات: عبث في الظرف المغلّف يعيد null (تكامل GCM)', () async {
    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();
    final alicePub = await alice.extractPublicKey();
    final bobPub = await bob.extractPublicKey();

    final gkey = await newKey();
    final wrapped = await E2eService.wrapGroupKey(
      groupKey: gkey,
      conversationId: convId,
      wrapperPair: alice,
      memberPub: bobPub,
    );
    final parts = wrapped.split('.');
    final ct = base64Decode(parts[2]);
    ct[0] = ct[0] ^ 0x01;
    final tampered = 'v1.${parts[1]}.${base64Encode(ct)}.${parts[3]}';
    final out = await E2eService.unwrapGroupKey(
      wrapped: tampered,
      conversationId: convId,
      myPair: bob,
      wrapperPub: alicePub,
    );
    expect(out, isNull);
  });

  test('تدوير المفتاح: رسالة الإصدار القديم تُفك بالقديم فقط، والجديد لا يفك القديم', () async {
    const conv = 'group-rotate-1';
    final v1 = await AesGcm.with256bits().newSecretKey();
    final v2 = await AesGcm.with256bits().newSecretKey();
    final oldMsg = await E2eService.encryptText(v1, conv, 'رسالة قبل الإزالة');
    final newMsg = await E2eService.encryptText(v2, conv, 'رسالة بعد الإزالة');
    // تجربة كل الإصدارات المعروفة (الحالي أولاً) كما يفعل decryptGroupText
    Future<String?> tryAll(List<SecretKey> keys, String c) async {
      for (final k in keys) {
        final p = await E2eService.decryptText(k, conv, c);
        if (p != null) return p;
      }
      return null;
    }
    expect(await tryAll([v2, v1], oldMsg), 'رسالة قبل الإزالة');
    expect(await tryAll([v2, v1], newMsg), 'رسالة بعد الإزالة');
    // العضو المُزال يملك v1 فقط: لا يفك الجديد
    expect(await tryAll([v1], newMsg), isNull);
  });
}
