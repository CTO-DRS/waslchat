import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/key_transparency_service.dart';

/// اختبارات نقية لشفافية المفاتيح (المرحلة 10 ب — 0.25.0، ترحيل 034):
/// التجزئة القياسية المطابقة للدالة الخادمية، وسلامة السلسلة وكشف العبث الجزئي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('التجزئة تطابق vector ثابتاً محسوباً خارجياً (sha256 hex بالصيغة الصارمة)',
      () async {
    final h = await KeyTransparencyService.entryHash(
        prev: '', userId: 'u1', device: 'd1', kind: 'identity_publish', fp: 'fp1');
    expect(
        h,
        '76b8afbef94f59a4ceaa141701c4cc1d34e00b36e278102b2fad8ada359921a3');
    // تغيير أي مدخل يغيّر التجزئة (لا تصادم بصياغة)
    final h2 = await KeyTransparencyService.entryHash(
        prev: '', userId: 'u2', device: 'd1', kind: 'identity_publish', fp: 'fp1');
    expect(h2, isNot(h));
    final h3 = await KeyTransparencyService.entryHash(
        prev: '', userId: 'u1', device: '', kind: 'identity_publish', fp: 'fp1');
    expect(h3, isNot(h));
  });

  KeyLogEntry row({
    required int id,
    required String prev,
    required String hash,
    String kind = 'identity_publish',
    String fp = 'fp',
    String? device,
  }) =>
      KeyLogEntry(
        id: id,
        userId: 'u1',
        deviceId: device,
        kind: kind,
        fingerprint: fp,
        prevHash: prev,
        entryHash: hash,
        createdAtIso: '2026-11-14T00:00:00Z',
      );

  /// يبني سلسلة سليمة بطول [n] بالتجزئة نفسها التي تحسبها الدالة الخادمية
  Future<List<KeyLogEntry>> buildChain(int n) async {
    final out = <KeyLogEntry>[];
    var prev = '';
    for (var i = 0; i < n; i++) {
      final kinds = KeyTransparencyService.kinds;
      final kind = kinds[i % kinds.length];
      final h = await KeyTransparencyService.entryHash(
          prev: prev,
          userId: 'u1',
          device: 'd$i',
          kind: kind,
          fp: 'fp$i');
      out.add(row(id: i + 1, prev: prev, hash: h, kind: kind, device: 'd$i', fp: 'fp$i'));
      prev = h;
    }
    return out;
  }

  test('سلسلة سليمة بطول 5: تحقق كامل بلا مكسور', () async {
    final rows = await buildChain(5);
    final (ok, at) = await KeyTransparencyService.verifyChain(rows);
    expect(ok, isTrue);
    expect(at, -1);
    // السلسلة الفارغة سليمة
    expect(await KeyTransparencyService.verifyChain(const []), (true, -1));
  });

  test('عبث البصمة في المنتصف: يكشف عند فهرسه تحديداً', () async {
    final rows = await buildChain(4);
    rows[2] = row(
        id: 3,
        prev: rows[2].prevHash,
        hash: rows[2].entryHash,
        kind: rows[2].kind,
        fp: 'BASMAMUKHTALA',
        device: rows[2].deviceId);
    final (ok, at) = await KeyTransparencyService.verifyChain(rows);
    expect(ok, isFalse);
    expect(at, 2);
  });

  test('حذف حدث من التاريخ: كسر الربط يكشفه (إعادة ترتيب أو إسقاط)', () async {
    final rows = await buildChain(4);
    final withoutFirst = rows.sublist(1); // حذف الأول يفصل prev_hash ''
    final (ok1, at1) = await KeyTransparencyService.verifyChain(withoutFirst);
    expect(ok1, isFalse);
    expect(at1, 0);
    final reordered = [rows[1], rows[0], rows[2], rows[3]];
    final (ok2, at2) = await KeyTransparencyService.verifyChain(reordered);
    expect(ok2, isFalse);
    expect(at2, 0);
  });

  test('تجزئة مزورة أو شكل غير سليم: المكسور محدد بدقة لا يُقبل بصمت',
      () async {
    final rows = await buildChain(3);
    final forged =
        List<KeyLogEntry>.from(rows)..[1] = row(id: 2, prev: rows[1].prevHash, hash: '0' * 64, kind: rows[1].kind, device: rows[1].deviceId);
    final (ok, at) = await KeyTransparencyService.verifyChain(forged);
    expect(ok, isFalse);
    expect(at, 1);
  });

  test('التسميات العربية للأربعة معروفة — والغير معروف يمر صادقاً كما هو', () {
    expect(KeyTransparencyService.kindLabel('identity_publish'), 'نشر مفتاح الحساب');
    expect(KeyTransparencyService.kindLabel('device_register'), 'تسجيل جهاز');
    expect(KeyTransparencyService.kindLabel('device_remove'), 'إزالة جهاز');
    expect(KeyTransparencyService.kindLabel('key_reset'), 'مفتاح جديد كلياً');
    expect(KeyTransparencyService.kindLabel('weird_kind'), 'weird_kind');
    expect(KeyTransparencyService.kindDetail('device_remove'),
        contains('مخزون مفاتيحه'));
    // الأنواع الأربعة حصراً — مطابقة قيد الترحيل
    expect(
        KeyTransparencyService.kinds,
        ['identity_publish', 'device_register', 'device_remove', 'key_reset']);
  });

  test('fromRow: الصف السليم يُقرأ والناقص حقله الجوهرية يُرفض بلا استثناء', () {
    final ok = KeyLogEntry.fromRow({
      'id': 7,
      'user_id': 'u1',
      'device_id': null,
      'kind': 'key_reset',
      'fingerprint': 'aabb',
      'prev_hash': '',
      'entry_hash': 'ff' * 32,
      'created_at': '2026-11-14T01:02:03Z',
    });
    expect(ok, isNotNull);
    expect(ok!.hashInput.device, '');
    expect(ok.entryHash, 'ff' * 32);
    expect(KeyLogEntry.fromRow({'id': null, 'user_id': 'u1', 'kind': 'x', 'entry_hash': 'y'}),
        isNull);
    expect(KeyLogEntry.fromRow({'id': 1, 'user_id': null, 'kind': 'x', 'entry_hash': 'y'}),
        isNull);
    expect(KeyLogEntry.fromRow({'id': 1, 'user_id': 'u1', 'kind': null, 'entry_hash': 'y'}),
        isNull);
  });
}
