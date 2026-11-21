/// اختبارات كتالوج البوتات المجتمعية (1.21.0): متجهات RFC 4231 المحسوبة
/// خارجياً بـpython hmac (مستقلة عن التنفيذ)، مقارنة زمن-ثابت، بوابة
/// التوقيع بصيغة X-Wasl-Signature القائمة، حدود القوالب المعلنة، الرندر
/// الحتمي، والكتالوج بترتيبه القياسي وتكراره المرفوض — واختبار بنائي
/// يحصر الاستيرادات (لا dart:io ولا شبكة في النواة).
import 'dart:convert';
import 'dart:io' as io;

import 'package:test/test.dart';
import 'package:wasl_bots/wasl_bots.dart';

/// بيان تجربة صالح — بوت ترحيب بسيط
Map<String, dynamic> _manifestJson() => {
      'username': 'helper_bot',
      'displayName': 'المساعد',
      'description': 'بوت ترحيب لمجتمعات وصل',
      'templates': [
        {
          'type': 'welcome',
          'messages': ['أهلاً {name}!', 'كيف أساعدك اليوم؟']
        }
      ],
    };

String _signedDoc(Map<String, dynamic> manifest, List<int> secret) =>
    json.encode({
      'version': 1,
      'bots': [
        {'manifest': manifest, 'signature': signManifest(manifest, secret)}
      ],
    });

void main() {
  group('متجهات RFC 4231 — HMAC-SHA256 المعياري', () {
    test('TC1: مفتاح 20 بايت وبيانات «Hi There»', () {
      final mac = hmacSha256(
          List.filled(20, 0x0b), 'Hi There'.codeUnits);
      expect(_hex(mac),
          'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
    });

    test('TC2: مفتاح «Jefe» وبيانات ماذا تريد للاشيء', () {
      final mac = hmacSha256(
          'Jefe'.codeUnits, 'what do ya want for nothing?'.codeUnits);
      expect(_hex(mac),
          '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
    });

    test('TC3: مفتاح 0xaa×20 وبيانات 0xdd×50', () {
      final mac = hmacSha256(
          List.filled(20, 0xaa), List.filled(50, 0xdd));
      expect(_hex(mac),
          '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe');
    });

    test('TC6: مفتاح 131 بايت — مسار hash-first', () {
      final mac = hmacSha256(List.filled(131, 0xaa),
          'Test Using Larger Than Block-Size Key - Hash First'.codeUnits);
      expect(_hex(mac),
          '58e73a2cba6b3d9836117a3766d5f27d9922fb07cac4267b5140f4492880b1a5');
    });

    test('TC7: مفتاح 131 بايت وبيانات 0xdd×50', () {
      final mac = hmacSha256(
          List.filled(131, 0xaa), List.filled(50, 0xdd));
      expect(_hex(mac),
          '124c7d2385aa1743aaad12204e3464f06305fd1a6d291250fa564dceffab0c8a');
    });
  });

  group('المقارنة الزمن-الثابتة', () {
    test('متساوية تمر ومختلفة ترفض وطول مختلف يرفض', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('بوابة X-Wasl-Signature — صيغة الواجهة القائمة', () {
    const secret = [0x11, 0x22, 0x33];
    test('توقيع صحيح على جسم البيان يمر', () {
      final body = 'hello'.codeUnits;
      final sig = 'sha256=${_hex(hmacSha256(secret, body))}';
      final r = verifyXWaslSignature(sig, body, secret);
      expect(r.isOk, isTrue, reason: r.reasons.toString());
    });

    test('جسم معبث يُرفض — لا ثقة بلا مطابقة', () {
      final body = 'hello'.codeUnits;
      final sig = 'sha256=${_hex(hmacSha256(secret, body))}';
      final r = verifyXWaslSignature(sig, 'tampered'.codeUnits, secret);
      expect(r.isOk, isFalse);
      expect(r.reasons.first, contains('لا يطابق جسم البيان'));
    });

    test('سر معبث يُرفض كذلك', () {
      final body = 'hello'.codeUnits;
      final sig = 'sha256=${_hex(hmacSha256(secret, body))}';
      final r = verifyXWaslSignature(sig, body, [0x99]);
      expect(r.isOk, isFalse);
      expect(r.reasons.first, contains('لا يطابق جسم البيان'));
    });

    test('أسباب الصيغة تتجمع لا أولها (مفقود + بادئة + طول)', () {
      final r = verifyXWaslSignature('', [1, 2], secret);
      expect(r.isOk, isFalse);
      expect(r.reasons.length, greaterThanOrEqualTo(2),
          reason: 'التوقيع المفقود يجمع مفقود + بادئة + طول معاً');
      expect(r.reasons.any((x) => x.contains('التوقيع مفقود')), isTrue);
      expect(r.reasons.any((x) => x.contains('sha256=')), isTrue);
    });
  });

  group('بيان البوت — صيغة الواجهة القائمة للاسم', () {
    test('بيان صالح يُفك ويُتحقق منه دورة كاملة', () {
      final m = _manifestJson();
      final (parsed, reasons) = BotManifest.fromJson(m);
      expect(reasons, isEmpty, reason: reasons.toString());
      expect(parsed!.username, 'helper_bot');
      // ودورة التوقيع: وقّع وتحقق على الترميز القانوني نفسه (utf8 بايتات)
      final sig = signManifest(m, const [1, 2, 3, 4]);
      final r = verifyXWaslSignature(
          sig, utf8.encode(json.encode(m)), const [1, 2, 3, 4]);
      expect(r.isOk, isTrue, reason: r.reasons.toString());
    });

    test('اسم بلا _bot ووصف طويل — أسباب مجمعة', () {
      final m = _manifestJson()
        ..['username'] = 'helper'
        ..['description'] = 'x' * 300;
      final (parsed, reasons) = BotManifest.fromJson(m);
      expect(parsed, isNull);
      expect(reasons.any((r) => r.contains('_bot')), isTrue);
      expect(reasons.any((r) => r.contains('الوصف')), isTrue);
    });
  });

  group('القوالب الثلاثة — حدود معلنة ورندر حتمي', () {
    test('ترحيب: حتى 3 رسائل و{name} يستبدل حتمياً', () {
      final t = BotTemplate.welcome(['أهلاً {name}', 'بك في وصل']);
      expect(t.validate(), isEmpty);
      expect(t.renderWelcome('أحمد'),
          'أهلاً أحمد\nبك في وصل');
      // ورندر ثانوي نفسه = نفس النص حرفياً (حتمية)
      expect(t.renderWelcome('أحمد'), t.renderWelcome('أحمد'));
      final bad = BotTemplate.welcome(['a' * 201]);
      expect(bad.validate(), isNotEmpty);
      final tooMany = BotTemplate.welcome(
          ['1', '2', '3', '4']);
      expect(tooMany.validate().first, contains('من 1 إلى 3'));
    });

    test('حضور: HH:mm صحيحة والبداية قبل النهاية', () {
      final ok = BotTemplate.attendance([('09:00', '17:00')]);
      expect(ok.validate(), isEmpty);
      expect(ok.renderAttendance(), 'الحضور: 09:00–17:00');
      final badTime = BotTemplate.attendance([('9:00', '25:00')]);
      expect(badTime.validate().first, contains('HH:mm'));
      final reversed = BotTemplate.attendance([('17:00', '09:00')]);
      expect(reversed.validate().first, contains('تسبق نهايتها'));
    });

    test('اقتراحات: من 3 إلى 5 عناصر بحد 80 حرفاً', () {
      final ok = BotTemplate.suggestions(['اقترح فكرة', 'شارك خبرة', 'رشح عضواً']);
      expect(ok.validate(), isEmpty);
      expect(ok.renderSuggestions()!.length, 3);
      final tooFew = BotTemplate.suggestions(['واحد', 'اثنان']);
      expect(tooFew.validate().first, contains('من 3 إلى 5'));
      final tooLong = BotTemplate.suggestions(['x' * 81, 'y', 'z']);
      expect(tooLong.validate().first, contains('80 حرفاً'));
    });

    test('نوع قالب غير معروف يُسقط بسبب صريح', () {
      final reasons = <String>[];
      final t = BotTemplate.fromJson(
          {'type': 'magic', 'anything': 1}, reasons);
      expect(t, isNull);
      expect(reasons.first, contains('نوع قالب غير معروف'));
    });
  });

  group('الكتالوج الموثق', () {
    test('كتالوج موقّع يُعتمد كاملاً', () {
      final doc = _signedDoc(_manifestJson(), const [7, 7, 7]);
      final r = verifyCatalog(doc, const [7, 7, 7]);
      expect(r.isOk, isTrue, reason: r.reasons.toString());
      expect(r.entries.single.manifest.username, 'helper_bot');
    });

    test('كتالوج معبث (بعد التوقيع) يُرفض ببَوّابة التوقيع', () {
      final m = _manifestJson();
      final doc = _signedDoc(m, const [7, 7, 7]);
      // نبدل الاسم بعد التوقيع
      final tampered = doc.replaceFirst('helper_bot', 'hacker_bot');
      final r = verifyCatalog(tampered, const [7, 7, 7]);
      expect(r.isOk, isFalse);
      expect(r.reasons.any((x) => x.contains('التوقيع')), isTrue);
    });

    test('تكرار اسم برمجي وترتيب غير قياسي وأسير فوق الحد — أسباب مجمعة',
        () {
      final secret = const [5, 5, 5];
      Map<String, dynamic> entry(String name) {
        final m = _manifestJson()..['username'] = name;
        return {'manifest': m, 'signature': signManifest(m, secret)};
      }

      // بترتيب معكوس عمداً: zeta ثم alpha — ومرتان لنفس الاسم
      final doc = json.encode({
        'version': 1,
        'bots': [entry('zeta_bot'), entry('alpha_bot'), entry('zeta_bot')]
      });
      final r = verifyCatalog(doc, secret);
      expect(r.isOk, isFalse);
      expect(r.reasons.any((x) => x.contains('غير مرتب')), isTrue);
      expect(r.reasons.any((x) => x.contains('مكرر')), isTrue);
    });

    test('نسخة غير 1 وكتالوج فارغ يرفضان', () {
      final r1 = verifyCatalog(
          json.encode({'version': 2, 'bots': []}), const [1]);
      expect(r1.isOk, isFalse);
      expect(r1.reasons.any((x) => x.contains('نسخة')), isTrue);
      final r2 = verifyCatalog('not json at all', const [1]);
      expect(r2.isOk, isFalse);
      expect(r2.reasons.first, contains('JSON'));
    });
  });

  group('البنية — صفر شبكة وصفر ملفات في النواة', () {
    test('لا استيراد dart:io ولا شبكة — بايتات داخل ونتائج خارج', () async {
      final source =
          io.File('lib/wasl_bots.dart').readAsStringSync();
      final imports = RegExp(r"^import\s+[^;]+;", multiLine: true)
          .allMatches(source)
          .map((m) => m.group(0)!)
          .toList();
      expect(imports.any((i) => i.contains('dart:io')), isFalse);
      expect(imports.any((i) => i.contains('dart:http')), isFalse);
      expect(imports.any((i) => i.contains('socket')), isFalse);
      final allowed = ['dart:convert', 'dart:typed_data', 'sha256.dart'];
      for (final imp in imports) {
        expect(allowed.any((a) => imp.contains(a)), isTrue,
            reason: 'استيراد غير متوقع في نواة نقية: $imp');
      }
    });
  });
}

String _hex(List<int> bytes) {
  const d = '0123456789abcdef';
  final b = StringBuffer();
  for (final x in bytes) {
    b.write(d[(x >> 4) & 0xf]);
    b.write(d[x & 0xf]);
  }
  return b.toString();
}
