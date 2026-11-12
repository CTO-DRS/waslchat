import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/e2e_service.dart';

/// اختبارات نقية لحمولة التحقق بـ QR — بلا شبكة ولا تخزين.
void main() {
  group('parseVerifyPayload', () {
    // base64 لـ 32 بايت (مفتاح X25519): 43 حرفاً + حشوة =
    final pub = 'A' * 43 + '=';
    const uid = 'abcdefgh-1234-5678-9abc-def012345678';

    test('يحلل حمولة صحيحة', () {
      final p =
          E2eService.parseVerifyPayload('wasl-verify:v1|$uid|$pub');
      expect(p, isNotNull);
      expect(p!.$1, uid);
      expect(p.$2, pub);
    });

    test('دورة كاملة عبر verifyPayloadFor', () {
      final payload = E2eService.verifyPayloadFor(uid, pub);
      expect(payload, 'wasl-verify:v1|$uid|$pub');
      final p = E2eService.parseVerifyPayload(payload);
      expect(p, isNotNull);
      expect(p!.$1, uid);
      expect(p.$2, pub);
    });

    test('يرفض بادئة خاطئة', () {
      expect(E2eService.parseVerifyPayload('other:v1|$uid|$pub'), isNull);
    });

    test('يرفض عدد أجزاء خاطئاً', () {
      expect(E2eService.parseVerifyPayload('wasl-verify:v1|$uid'), isNull);
      expect(
          E2eService.parseVerifyPayload('wasl-verify:v1|$uid|$pub|extra'),
          isNull);
    });

    test('يرفض معرّفاً قصيراً', () {
      expect(E2eService.parseVerifyPayload('wasl-verify:v1|short|$pub'),
          isNull);
      expect(E2eService.parseVerifyPayload('wasl-verify:v1||$pub'), isNull);
    });

    test('يرفض base64 غير صالح أو طول مفتاح غير 32 بايت', () {
      expect(
          E2eService.parseVerifyPayload('wasl-verify:v1|$uid|not-base64!!'),
          isNull);
      expect(E2eService.parseVerifyPayload('wasl-verify:v1|$uid|AAAA'),
          isNull);
    });

    test('يتقبّل مسافات محيطة (trim)', () {
      final p = E2eService.parseVerifyPayload('  wasl-verify:v1|$uid|$pub\n');
      expect(p, isNotNull);
    });
  });
}
