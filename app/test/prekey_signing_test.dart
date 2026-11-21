import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/e2e_service.dart';
import 'package:wasl_chat/services/ratchet.dart';

/// اختبارات نقية لتوقيع المفاتيح الأولية Ed25519 (المرحلة 13 أ — 0.26.0،
/// ترحيل 035): إغلاق البند الوحيد المفتوح في التقوية (E2EE_PLAN §9).
/// الصيغة الصارمة: payload = 'wasl-prekey-sig-v1' + prekeyPub + pqPub(إن وجد).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // مفاتيح ثابتة للتجربة — النقاء يسمح ببذور محددة
  Future<(SimpleKeyPair, String)> makeSigner() async {
    final seed = List<int>.generate(32, (i) => (i * 7 + 3) % 256);
    final pair = await RatchetCrypto.signingKeyPairFromSeed(seed);
    final pub =
        base64Encode((await pair.extractPublicKey()).bytes);
    return (pair, pub);
  }

  test('زوج التوقيع Ed25519: العام 32 بايت (44 حرفاً b64) والبذرة ثابتة',
      () async {
    final (pair, pubB64) = await makeSigner();
    expect(pubB64.length, 44);
    final seed = List<int>.generate(32, (i) => (i * 7 + 3) % 256);
    final again = await RatchetCrypto.signingKeyPairFromSeed(seed);
    final pubAgain = base64Encode((await again.extractPublicKey()).bytes);
    expect(pubAgain, pubB64); // نفس البذرة = نفس المفتاح العام
  });

  test('المادة الموقَّعة: البادئة ثم المفتاح الأولي ثم الكمومي المرافق إن وجد',
      () {
    final prekeyB64 = base64Encode(List<int>.generate(32, (i) => i));
    final pqB64 = base64Encode(List<int>.generate(16, (i) => i + 100));
    final p0 = RatchetCrypto.prekeySigningPayload(prekeyB64, null);
    final p1 = RatchetCrypto.prekeySigningPayload(prekeyB64, pqB64);
    // البادئة الصارمة أولاً
    final domain = utf8.encode(RatchetCrypto.prekeySigDomain);
    for (var i = 0; i < domain.length; i++) {
      expect(p0[i], domain[i]);
    }
    // الكمومي يزيد المادة ولا يغيّر ما قبلها
    expect(p1.length, p0.length + 16);
    for (var i = 0; i < p0.length; i++) {
      expect(p1[i], p0[i]);
    }
    expect(p0.length, domain.length + 32);
  });

  test('توقيع ثم تحقق: الدورة الكاملة تنجح والتوقيع 88 حرفاً b64', () async {
    final (pair, pubB64) = await makeSigner();
    final prekeyB64 = base64Encode(List<int>.generate(32, (i) => i + 5));
    final payload = RatchetCrypto.prekeySigningPayload(prekeyB64, null);
    final sig = await RatchetCrypto.signB64(pair, payload);
    expect(sig.length, 88); // 64 بايت = 88 حرفاً b64 (ترحيل 035 قيد 80..100)
    final ok = await E2eService.verifyPrekeySignature(
        signingPubB64: pubB64, signatureB64: sig, prekeyPubB64: prekeyB64);
    expect(ok, isTrue);
  });

  test('توقيع ثم تحقق مع مفتاح كمومي مرافق (المسار الهجين الكامل)', () async {
    final (pair, pubB64) = await makeSigner();
    final prekeyB64 = base64Encode(List<int>.generate(32, (i) => i + 9));
    final pqB64 = base64Encode(List<int>.generate(24, (i) => i + 40));
    final payload = RatchetCrypto.prekeySigningPayload(prekeyB64, pqB64);
    final sig = await RatchetCrypto.signB64(pair, payload);
    final ok = await E2eService.verifyPrekeySignature(
        signingPubB64: pubB64,
        signatureB64: sig,
        prekeyPubB64: prekeyB64,
        pqPubB64: pqB64);
    expect(ok, isTrue);
    // مفتاح كمومي مختلف في القبول = مادة مختلفة = رفض
    final pq2 = base64Encode(List<int>.generate(24, (i) => i + 41));
    final bad = await E2eService.verifyPrekeySignature(
        signingPubB64: pubB64,
        signatureB64: sig,
        prekeyPubB64: prekeyB64,
        pqPubB64: pq2);
    expect(bad, isFalse);
  });

  test('استبدال المفتاح الأولي (عبث وسيطي) يفشل التحقق — لا قبول صامت', () async {
    final (pair, pubB64) = await makeSigner();
    final real = base64Encode(List<int>.generate(32, (i) => i + 1));
    final forged = base64Encode(List<int>.generate(32, (i) => i + 2));
    final sig = await RatchetCrypto.signB64(
        pair, RatchetCrypto.prekeySigningPayload(real, null));
    final ok = await E2eService.verifyPrekeySignature(
        signingPubB64: pubB64, signatureB64: sig, prekeyPubB64: forged);
    expect(ok, isFalse); // هذا ما يمنع استبدال المفتاح من الخادم
  });

  test('توقيع مزور بمفتاح توقيع آخر يفشل التحقق', () async {
    final (_, pubB64) = await makeSigner();
    final attackerSeed = List<int>.generate(32, (i) => (i * 3 + 11) % 256);
    final attacker = await RatchetCrypto.signingKeyPairFromSeed(attackerSeed);
    final prekeyB64 = base64Encode(List<int>.generate(32, (i) => i + 3));
    final forgedSig = await RatchetCrypto.signB64(
        attacker, RatchetCrypto.prekeySigningPayload(prekeyB64, null));
    final ok = await E2eService.verifyPrekeySignature(
        signingPubB64: pubB64, signatureB64: forgedSig, prekeyPubB64: prekeyB64);
    expect(ok, isFalse);
  });

  test('بايت واحد معبوث في التوقيع نفسه يفشل التحقق', () async {
    final (pair, pubB64) = await makeSigner();
    final prekeyB64 = base64Encode(List<int>.generate(32, (i) => i + 4));
    final sig = await RatchetCrypto.signB64(
        pair, RatchetCrypto.prekeySigningPayload(prekeyB64, null));
    final bytes = base64Decode(sig);
    bytes[0] = bytes[0] ^ 0x01;
    final ok = await E2eService.verifyPrekeySignature(
        signingPubB64: pubB64,
        signatureB64: base64Encode(bytes),
        prekeyPubB64: prekeyB64);
    expect(ok, isFalse);
  });

  test('إدخالات معطوبة كلياً تعيد false بلا استثناءات (فشل قرار لا استثناء)',
      () async {
    final prekeyB64 = base64Encode(List<int>.generate(32, (i) => i + 6));
    final r1 = await E2eService.verifyPrekeySignature(
        signingPubB64: '!!!!', signatureB64: '???', prekeyPubB64: prekeyB64);
    expect(r1, isFalse);
    final r2 = await E2eService.verifyPrekeySignature(
        signingPubB64: base64Encode(List<int>.filled(32, 1)),
        signatureB64: base64Encode(List<int>.filled(64, 2)),
        prekeyPubB64: 'not-base64!!!');
    expect(r2, isFalse);
  });
}
