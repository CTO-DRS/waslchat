import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/key_witness_service.dart';

/// اختبارات نقية للشهود الخارجيين لشفافية المفاتيح (المرحلة 15 ب — 1.6.0).
/// المتجهات الثابتة محسوبة خارجياً بمخلص sha256 الرسمي — أي انحراف في
/// الصيغة عن الدالتين الخادمتين يكشفه اختبار المتجهة فوراً.
void main() {
  const uid = '11111111-1111-1111-1111-111111111111';
  const headA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const headB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('البصمة العمياء تطابق متجهة محسوبة خارجياً حرفياً', () async {
    final d = await KeyWitnessService.blindDigest(userId: uid, head: headA);
    expect(
      d,
      '7d7e4a12a05184ad119fd9faab9c3c35d16f8d7223a7f7d235efec6acafd782f',
    );
  });

  test('تغيّر رأس السلسلة يغيّر البصمة العمياء — الثبات تغيّر', () async {
    final a = await KeyWitnessService.blindDigest(userId: uid, head: headA);
    final b = await KeyWitnessService.blindDigest(userId: uid, head: headB);
    expect(b, '0f741e6a1553f00c9e4e9eb8944b28f434391ac121f42b2606d525d29b69b4e2');
    expect(a, isNot(b));
  });

  test('مدخلات فاسدة تعيد سلسلة فارغة صادقة — لا بصمة مزيفة', () async {
    expect(await KeyWitnessService.blindDigest(userId: '', head: headA), '');
    expect(await KeyWitnessService.blindDigest(userId: uid, head: ''), '');
  });

  test('بصمة اللقطة تطابق متجهة محسوبة خارجياً (ترتيب فرض لا يعبث به)', () async {
    final a = await KeyWitnessService.blindDigest(userId: uid, head: headA);
    final b = await KeyWitnessService.blindDigest(userId: uid, head: headB);
    // أُدخلت بترتيب معكوس عمداً — الترتيب تصاعدي حتمي قبل التجزئة
    final d = await KeyWitnessService.snapshotDigest([b, a]);
    expect(
      d,
      '2d79d9422b1ea5ee488aa255a4917926e8a5e963b08067cafc3bc393ad34e057',
    );
  });

  test('اللقطة الفارغة بصمة السلسلة الفارغة الثابتة — والتكرار يغيّر البصمة (لا dedup زائف)', () async {
    final a = await KeyWitnessService.blindDigest(userId: uid, head: headA);
    // التكرار لا يُخفى: مدخل مكرر يغيّر البصمة الكلية فلا يتظاهر المرور بصمت
    expect(
      await KeyWitnessService.snapshotDigest([a, a]),
      isNot(await KeyWitnessService.snapshotDigest([a])),
    );
    expect(
      await KeyWitnessService.snapshotDigest(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('البصمة من رأس سلسلة كاملة تأخذ آخر صف أُلحِح حصراً', () async {
    final d = await KeyWitnessService.blindFromChain(uid, [headA, headB]);
    expect(
      d,
      '0f741e6a1553f00c9e4e9eb8944b28f434391ac121f42b2606d525d29b69b4e2',
    );
    expect(await KeyWitnessService.blindFromChain(uid, const []), '');
  });

  test('تحليل صف لقطة دفاعي: الناقص الجوهري يُسقط بلا انهيار', () {
    expect(KeyWitnessService.headFromRow({
      'blind_digest': 'a' * 64,
      'chain_len': 3,
      'last_event_at': '2026-11-18T10:00:00Z',
    }), isNotNull);
    expect(KeyWitnessService.headFromRow({'chain_len': 3}), isNull);
    expect(KeyWitnessService.headFromRow({
      'blind_digest': 'قصيرة',
      'chain_len': 3,
    }), isNull);
    expect(KeyWitnessService.headFromRow({
      'blind_digest': 'a' * 64,
    }), isNull, reason: 'طول السلسلة مطلوب — صفر لا معنى له');
    expect(KeyWitnessService.headFromRow({
      'blind_digest': 'a' * 64,
      'chain_len': 0,
    }), isNull);
  });

  test('تحليل سطر سجل دفاعي: JSON فاسد أو ناقص يُسقط بلا ثقة', () {
    final good = KeyWitnessService.snapshotFromLogLine(
        '{"ts":"2026-11-18T09:00:00Z","digest":"${'c' * 64}","count":1,'
        '"heads":[{"d":"${'a' * 64}","len":2,"at":"2026-11-18T08:59:00Z"}]}');
    expect(good, isNotNull);
    expect(good!.heads.length, 1);
    expect(good.heads.first.chainLen, 2);
    expect(KeyWitnessService.snapshotFromLogLine('not json'), isNull);
    expect(KeyWitnessService.snapshotFromLogLine('{"ts":"2026-11-18T09:00:00Z"}'),
        isNull, reason: 'بلا بصمة كلية لا لقطة');
    expect(KeyWitnessService.snapshotFromLogLine('{"digest":"${'c' * 64}"}'),
        isNull, reason: 'بلا لحظة لا لقطة');
    expect(KeyWitnessService.snapshotFromLogLine(
        '{"ts":"باد","digest":"${'c' * 64}"}'), isNull);
  });

  group('تحقق الوجود في سجل الشاهد', () {
    final blind = '7d7e4a12a05184ad119fd9faab9c3c35d16f8d7223a7f7d235efec6acafd782f';
    final other = '0f741e6a1553f00c9e4e9eb8944b28f434391ac121f42b2606d525d29b69b4e2';

    String line(String ts, List<String> blinds) =>
        '{"ts":"$ts","digest":"${'c' * 64}","count":${blinds.length},'
        '"heads":[${blinds.map((b) => '{"d":"$b","len":1,"at":"$ts"}').join(',')}]}';

    test('بصمتك في كل لقطة بعد لحظتك: صفر نواقص', () async {
      final (checked, missing, first) =
          await KeyWitnessService.verifyPresenceInLog(
        logLines: [
          line('2026-11-18T09:00:00Z', [blind, other]),
          line('2026-11-18T10:00:00Z', [other, blind]),
        ],
        blindDigest: blind,
        after: DateTime.utc(2026, 11, 18, 8),
      );
      expect(checked, 2);
      expect(missing, 0);
      expect(first, isNull);
    });

    test('لقطة بعد وجودك بلا بصمتك = نواقص وأول لحظة ناقصة معلنة', () async {
      final (checked, missing, first) =
          await KeyWitnessService.verifyPresenceInLog(
        logLines: [
          line('2026-11-18T09:00:00Z', [blind]),
          line('2026-11-18T10:00:00Z', [other]),
          line('2026-11-18T11:00:00Z', [other, blind]),
        ],
        blindDigest: blind,
        after: DateTime.utc(2026, 11, 18, 8),
      );
      expect(checked, 3);
      expect(missing, 1);
      expect(first, '2026-11-18T10:00:00Z');
    });

    test('اللقطات قبل لحظتك لا تُفحص (وجودك لم يبدأ بعد) والسطر الفاسد يُسقط', () async {
      final (checked, missing, first) =
          await KeyWitnessService.verifyPresenceInLog(
        logLines: [
          'باد',
          line('2026-11-18T07:00:00Z', [other]),
          line('2026-11-18T09:00:00Z', [blind]),
        ],
        blindDigest: blind,
        after: DateTime.utc(2026, 11, 18, 8),
      );
      expect(checked, 1);
      expect(missing, 0);
      expect(first, isNull);
    });

    test('سجل يعود للخلف زمنياً يُرفض فوراً — لا إلحاح بلا ترتيب', () async {
      final (checked, missing, first) =
          await KeyWitnessService.verifyPresenceInLog(
        logLines: [
          line('2026-11-18T09:00:00Z', [blind]),
          line('2026-11-18T08:00:00Z', [blind]),
        ],
        blindDigest: blind,
        after: DateTime.utc(2026, 11, 18, 1),
      );
      expect(missing, 1, reason: 'العودة للخلف تُعلن نواقص بلا فحص أكثر');
      expect(first, '2026-11-18T08:00:00Z');
      expect(checked, 1, reason: 'التوقف عند أول انتهاك للرتابة');
    });

    test('بصمة فارغة أو سجل فارغ: صفر فحوص بلا ادعاء', () async {
      expect(
        await KeyWitnessService.verifyPresenceInLog(
            logLines: const [], blindDigest: blind, after: DateTime.utc(2026)),
        (0, 0, null),
      );
      expect(
        await KeyWitnessService.verifyPresenceInLog(
            logLines: [line('2026-11-18T09:00:00Z', [blind])],
            blindDigest: '',
            after: DateTime.utc(2026)),
        (0, 0, null),
      );
    });
  });
}
