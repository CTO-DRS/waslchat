/// اختبارات محرك wasl_model_fetch: متجهات SHA-256 محسوبة خارجياً بـpython
/// hashlib (مستقلة عن التنفيذ) وسلوك التنزيل الموثق الذري كاملاً.
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wasl_model_fetch/wasl_model_fetch.dart';

/// نمط بايتات حتمي (i*37+11)%256 بطول 200 — بصمته المحسوبة بـpython:
const _pattern200Sha =
    '5e48d64839a8bff5e2471507af6a49f9990817df437857f4a2007df41266e1b5';

/// نمط 119 بايتاً (i*13+7)%256 — يقطع حدود كتلتي التحديث ويختبر padding
/// عند الطول 119 (كاملتان + 55 بايتاً) — بصمته بـpython:
const _pattern119Sha =
    'fd06b902a80a7934de6c554139f009a618f21177609745903a149f81c80688a5';

Uint8List _pattern(int length, int Function(int i) f) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = f(i) & 0xFF;
  }
  return out;
}

ModelSource _source(String id, String sha, {int sizeMb = 1, Uri? url}) =>
    ModelSource(
      id: id,
      label: 'نموذج اختبار',
      url: url ?? Uri.parse('https://example.test/models/$id'),
      sha256Hex: sha,
      sizeMb: sizeMb,
      notes: 'للاختبار حصراً',
    );

void main() {
  group('SHA-256 نقي — متجهات محسوبة خارجياً بـpython hashlib', () {
    test('السلسلة الفارغة (متجه NIST)', () {
      expect(sha256Hex(<int>[]),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('"abc" (متجه NIST)', () {
      expect(sha256Hex('abc'.codeUnits),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('نمط 200 بايت (يقطع حدود الكتلة)', () {
      expect(sha256Hex(_pattern(200, (i) => i * 37 + 11)), _pattern200Sha);
    });

    test('نمط 119 بايتاً (padding عند 55 بايتاً متبقية)', () {
      expect(sha256Hex(_pattern(119, (i) => i * 13 + 7)), _pattern119Sha);
    });

    test('التحديث بتدفق شرائح متعددة يطابق الدفعة الواحدة', () {
      final data = _pattern(500, (i) => i * 31 + 5);
      final whole = Sha256()..update(data);
      final chunked = Sha256();
      for (var i = 0; i < data.length; i += 7) {
        chunked.update(data.sublist(i, (i + 7) < data.length ? i + 7 : data.length));
      }
      expect(chunked.digestHex(), whole.digestHex());
    });

    test('التنفيذ يوافق python على 10 آلاف بايت (بصمة مرجعية)', () {
      // بصمة النمط 10000 بايت (i*99+3)%256 محسوبة بـpython hashlib:
      // sha256(bytes((i*99+3)%256 for i in range(10000)))
      const sha10k =
          'e0446246be890fce21ef138401d36b723488a68566df0df8418653c7c022a997';
      expect(sha256Hex(_pattern(10000, (i) => i * 99 + 3)), sha10k);
    });
  });

  group('التنزيل الموثق — كتابة ذرية وتحقق إلزامي', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wasl_fetch_test');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Stream<List<int>> chunks(List<int> bytes, int size) async* {
      for (var i = 0; i < bytes.length; i += size) {
        yield bytes.sublist(i, (i + size) < bytes.length ? i + size : bytes.length);
      }
    }

    test('نجاح كامل: دفق → تحقق → ملف نهائي وبصمة مدونة وجاهزية', () async {
      final data = _pattern(200, (i) => i * 37 + 11);
      final fetcher = ModelFetcher(modelsDir: dir);
      final states = <FetchState>[];
      final result = await fetcher.fetch(
        _source('test-200b', _pattern200Sha),
        onProgress: (p) => states.add(p.state),
        byteStream: chunks(data, 64),
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(result.state, FetchState.ready);
      expect(result.receivedBytes, 200);
      expect(states, containsAllInOrder([FetchState.downloading, FetchState.verifying, FetchState.ready]));
      final done = File('${dir.path}/test-200b.gguf');
      expect(await done.exists(), isTrue);
      expect(await done.readAsBytes(), data);
      expect(await File('${dir.path}/test-200b.sha256').readAsString(), _pattern200Sha);
      expect(await fetcher.isReady('test-200b', expectedSha256Hex: _pattern200Sha), isTrue);
      expect(await partFileExists(dir, 'test-200b'), isFalse, reason: 'لا يبقى مؤقت');
    });

    test('بصمة خاطئة: يفشل ويحذف المؤقت ولا يُعتمد الملف أبداً', () async {
      final data = _pattern(200, (i) => i * 37 + 11);
      final fetcher = ModelFetcher(modelsDir: dir);
      final wrongSha = '00' * 32;
      final result = await fetcher.fetch(
        _source('bad-sha', wrongSha),
        onProgress: (_) {},
        byteStream: chunks(data, 64),
      );
      expect(result.ok, isFalse);
      expect(result.state, FetchState.failed);
      expect(result.error, isNotNull);
      expect(await File('${dir.path}/bad-sha.gguf').exists(), isFalse,
          reason: 'ملف لا يطابق بصمة الناشر لا يصير جاهزاً');
      expect(await fetcher.isReady('bad-sha'), isFalse);
    });

    test('فشل الدفق في المنتصف: لا يبقى نصف ملف يوهم المستخدم', () async {
      final data = _pattern(100, (i) => i * 7 + 1);
      var threw = false;
      Stream<List<int>> broken() async* {
        yield data.sublist(0, 40);
        threw = true;
        throw StateError('انقطعت الشبكة');
      }

      final fetcher = ModelFetcher(modelsDir: dir);
      final result = await fetcher.fetch(
        _source('broken', _pattern200Sha),
        byteStream: broken(),
      );
      expect(result.ok, isFalse);
      expect(result.state, FetchState.failed);
      expect(threw, isTrue);
      expect(await partFileExists(dir, 'broken'), isFalse, reason: 'المؤقت يُمحى عند أي فشل');
      expect(await fetcher.isReady('broken'), isFalse);
    });

    test('delete يمسح النهائي والمؤقت والبصمة بلا أثر', () async {
      final data = _pattern(200, (i) => i * 37 + 11);
      final fetcher = ModelFetcher(modelsDir: dir);
      await fetcher.fetch(_source('del', _pattern200Sha), byteStream: chunks(data, 50));
      expect(await fetcher.isReady('del'), isTrue);
      await fetcher.delete('del');
      expect(await fetcher.isReady('del'), isFalse);
      expect(await File('${dir.path}/del.gguf').exists(), isFalse);
      expect(await File('${dir.path}/del.sha256').exists(), isFalse);
    });

    test('verifyFull يعيد البصمة للسليم ويمحي المخالف بعد الاعتماد', () async {
      final data = _pattern(200, (i) => i * 37 + 11);
      final fetcher = ModelFetcher(modelsDir: dir);
      await fetcher.fetch(_source('vf', _pattern200Sha), byteStream: chunks(data, 100));
      expect(await fetcher.verifyFull(_source('vf', _pattern200Sha)), _pattern200Sha);
      // تلف بعد الاعتماد: نعدّل الملف ثم الإثبات يمحيه ولا يدّعي الجاهزية
      final done = File('${dir.path}/vf.gguf');
      await done.writeAsBytes(<int>[...data, 0x00]);
      expect(await fetcher.verifyFull(_source('vf', _pattern200Sha)), isNull);
      expect(await done.exists(), isFalse, reason: 'الملف المخالف يُحذف');
    });

    test('مُعرّفات بأحرف غريبة تُعزل داخل مجلد النماذج (لا خروج مسار)', () async {
      final data = _pattern(200, (i) => i * 37 + 11);
      final fetcher = ModelFetcher(modelsDir: dir);
      final result = await fetcher.fetch(
        _source('../../etc/passwd', _pattern200Sha),
        byteStream: chunks(data, 100),
      );
      expect(result.ok, isTrue);
      // الاسم يطهَّر فلا يوجد ملف خارج المجلد
      expect(await File('${dir.path}/passwd').exists(), isFalse);
      expect(await File('${dir.path}/.._.._etc_passwd.gguf').exists(), isTrue);
    });
  });
}

/// فحص وجود ملف المؤقت (لتأكيد عدم بقاء نصف ملفات)
Future<bool> partFileExists(Directory dir, String id) async =>
    File('${dir.path}/${id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.part').exists();
