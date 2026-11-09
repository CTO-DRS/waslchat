import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/discovery_service.dart';

/// اختبارات وحدة: اكتشاف الأصدقاء من جهات الاتصال (بند المرحلة 1 — 0.4.7)
/// نختبر هنا الطبقة المحلية الصرفة: التطبيع E.164 والتجزئة والتقطيع —
/// استدعاءات الخادم (RPC) تُختبر ميدانياً وفق CHECKLIST §13.
void main() {
  group('تطبيع الأرقام إلى E.164', () {
    test('أصل بمفتاح دولي', () {
      expect(
          DiscoveryService.normalizeToE164('+966 51 234 5678'),
          '+966512345678');
    });

    test('بادئة 00 الدولية', () {
      expect(
          DiscoveryService.normalizeToE164('00966512345678'),
          '+966512345678');
    });

    test('صفر وطني مع الدولة الافتراضية', () {
      expect(
          DiscoveryService.normalizeToE164('0512345678'),
          '+966512345678');
    });

    test('مفتاح الدولة بلا + يُعامل دولياً لا محلياً', () {
      expect(
          DiscoveryService.normalizeToE164('966512345678'),
          '+966512345678');
    });

    test('رقم محلي بلا صفر يُضاف إليه مفتاح الدولة الافتراضي', () {
      expect(
          DiscoveryService.normalizeToE164('512345678'),
          '+966512345678');
    });

    test('رقم أجنبي بمفتاح دولي يمر كما هو (بلا فواصل)', () {
      expect(
          DiscoveryService.normalizeToE164('+1 (415) 555-2671'),
          '+14155552671');
    });

    test('دولة افتراضية بديلة في الاختيار', () {
      expect(
          DiscoveryService.normalizeToE164('0770090000', defaultCc: '+44'),
          '+44770090000');
    });

    test('الفراغات والشرطات والأقواس تُهمَل', () {
      expect(
          DiscoveryService.normalizeToE164(' 0512-345-678 '),
          '+966512345678');
    });

    test('الرفض: فارغ أو بلا أرقام', () {
      expect(DiscoveryService.normalizeToE164(''), isNull);
      expect(DiscoveryService.normalizeToE164('   '), isNull);
      expect(DiscoveryService.normalizeToE164('abc'), isNull);
      expect(DiscoveryService.normalizeToE164('+'), isNull);
    });
  });

  group('التجزئة SHA-256 بملح النطاق', () {
    test('حتمية: نفس المدخل نفس التجزئة', () async {
      final a = await DiscoveryService.hashPhone('+966512345678');
      final b = await DiscoveryService.hashPhone('+966512345678');
      expect(a, b);
    });

    test('شكل hex: 64 خانة صغيرة', () async {
      final h = await DiscoveryService.hashPhone('+966512345678');
      expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('أرقام مختلفة تجزئات مختلفة', () async {
      final a = await DiscoveryService.hashPhone('+966512345678');
      final b = await DiscoveryService.hashPhone('+966523456789');
      expect(a, isNot(b));
    });

    test('ملح النطاق مسبوق بالمدخل فعلاً (حساب التجزئة المتوقعة مباشرة)', () async {
      // التحقّق الأقوى: نقارن نتيجة hashPhone مع sha256('wasl-cd-v1:'+الرقم)
      // محسوبة هنا يدوياً — يثبت أن الملح مسبوق وليس مُلحّقاً بعده
      final h = await DiscoveryService.hashPhone('+966512345678');
      final expected =
          await Sha256().hash(utf8.encode('wasl-cd-v1:+966512345678'));
      final expectedHex =
          expected.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(h, expectedHex);
      // وإضافة الملح يدوياً في المدخل تُضاعِفه (مدخل مختلف → تجزئة مختلفة)
      final doubleSalted =
          await DiscoveryService.hashPhone('wasl-cd-v1:+966512345678');
      expect(doubleSalted, isNot(h));
    });

    test('تطبيع ثم تجزئة = تجزئة الشكل المطبّع', () async {
      final e = DiscoveryService.normalizeToE164('0512-345-678');
      expect(e, '+966512345678');
      final viaNumber = await DiscoveryService.hashPhone(e!);
      final direct = await DiscoveryService.hashPhone('+966512345678');
      expect(viaNumber, direct);
    });
  });

  group('تجزئة الدفعات والتقطيع', () {
    test('إزالة المكرر بعد التطبيع (نفس الرقم بصيغ مختلفة)', () async {
      final hashes = await DiscoveryService
          .hashNumbers(['0512345678', '+966 51 234 5678', '00966512345678']);
      expect(hashes.length, 1);
    });

    test('الأرقام غير الصالحة تُتخطى لا تُرفع', () async {
      final hashes = await DiscoveryService.hashNumbers(['', 'abc', '0512345678']);
      expect(hashes.length, 1);
    });

    test('التقطيع يحترم حد الاستدعاء الواحد', () {
      final hashes = <String>{
        for (var i = 0; i < 5001; i++) 'a${i.toString().padLeft(4, '0')}'
      };
      final chunks = DiscoveryService.chunkHashes(hashes);
      expect(chunks.length, 2);
      expect(chunks.first.length, DiscoveryService.maxHashesPerCall);
      expect(chunks.last.length, 1);
    });

    test('مجموعة فارغة تعطي دفعة واحدة فارغة على الأكثر', () {
      final chunks = DiscoveryService.chunkHashes(<String>{});
      expect(chunks, isEmpty);
    });

    test('تجاوز السقف الإجمالي يُرفض بلا رفع', () async {
      final huge = List<String>.generate(
          DiscoveryService.maxTotalHashes + 1, (i) => '+9665${i.toString().padLeft(8, '0')}');
      // أرقام فريدة تتجاوز السقف
      expect(() => DiscoveryService.hashNumbers(huge), throwsStateError);
    });
  });

  group('الثوابت الصادقة', () {
    test('حد الاستدعاء الواحد مطابق للترحيل 025', () {
      expect(DiscoveryService.maxHashesPerCall, 5000);
    });

    test('حد النتائج مطابق للترحيل 025', () {
      expect(DiscoveryService.maxResultsPerCall, 500);
    });

    test('ملح النطاق موثّق ومستقر', () {
      expect(DiscoveryService.domainSalt, 'wasl-cd-v1:');
    });
  });
}
