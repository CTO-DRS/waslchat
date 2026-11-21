/// اختبارات خدمة التنزيل الموثق (1.16.0): صدق بنية المصادر الموثقة
/// (بصمة 64 رقم سداسي ورابط https وحجم موجب) وسلوك الخدمة عبر الحقن
/// بلا شبكة — الجوهر نفسه مغطى باختبارات محرك wasl_model_fetch المستقلة.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/model_fetch_service.dart';

Uint8List pattern(int length, int Function(int i) f) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = f(i) & 0xFF;
  }
  return out;
}

/// بصمة النمط 200 بايت (i*37+11)%256 — محسوبة بـpython hashlib:
const pattern200Sha =
    '5e48d64839a8bff5e2471507af6a49f9990817df437857f4a2007df41266e1b5';

void main() {
  group('المصادر الموثقة — صدق البنية (لا بصمة مخترعة ولا رابط مهيأ)', () {
    test('كل مصدر: بصمة 64 رقم سداسي ورابط https وحجم موجب ومعرّف نقي', () {
      final hex = RegExp(r'^[0-9a-fA-F]{64}$');
      final cleanId = RegExp(r'^[a-zA-Z0-9._-]+$');
      expect(ModelFetchService.sources, isNotEmpty);
      for (final s in ModelFetchService.sources) {
        expect(hex.hasMatch(s.sha256Hex), isTrue,
            reason: 'بصمة ${s.id} ليست SHA-256 سداسياً سليماً');
        expect(s.url.scheme, 'https', reason: '${s.id} بلا رابط موثق');
        expect(s.sizeMb, greaterThan(0));
        expect(cleanId.hasMatch(s.id), isTrue, reason: '${s.id} معرّف غير نقي');
        expect(s.notes, isNotEmpty, reason: 'الإفصاح جزء من العقد الصادق');
      }
    });

    test('المعرّفات فريدة بين المصادر', () {
      final ids = ModelFetchService.sources.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('الخدمة عبر الحقن — مجلد مؤقت ودفق مصنوع بلا شبكة', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wasl_model_fetch_svc');
      ModelFetchService.debugModelsDirOverride = dir;
    });
    tearDown(() async {
      ModelFetchService.debugModelsDirOverride = null;
      ModelFetchService.debugStreamFactory = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    ModelSource source(String id, String sha, {int sizeMb = 1}) => ModelSource(
          id: id,
          label: 'اختبار',
          url: Uri.parse('https://example.test/$id'),
          sha256Hex: sha,
          sizeMb: sizeMb,
          notes: 'اختبار',
        );

    test('تنزيل كامل عبر الخدمة: جاهزية وبصمة مدونة وبلا مؤقت', () async {
      final data = pattern(200, (i) => i * 37 + 11);
      ModelFetchService.debugStreamFactory = (url) async* {
        for (var i = 0; i < data.length; i += 64) {
          yield data.sublist(i, (i + 64) < data.length ? i + 64 : data.length);
        }
      };
      final states = <FetchState>[];
      final result = await ModelFetchService.fetch(
        source('svc-200b', pattern200Sha),
        onProgress: (p) => states.add(p.state),
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(states,
          containsAllInOrder([FetchState.downloading, FetchState.verifying, FetchState.ready]));
      expect(
          await ModelFetchService.isReady(source('svc-200b', pattern200Sha)), isTrue);
      expect(await File('${dir.path}/svc-200b.part').exists(), isFalse);
    });

    test('بصمة خاطئة عبر الخدمة: فشل صادق ولا جاهزية ولا ملف نهائي', () async {
      final data = pattern(200, (i) => i * 37 + 11);
      ModelFetchService.debugStreamFactory = (url) async* {
        yield data;
      };
      final result = await ModelFetchService.fetch(source('svc-bad', 'ff' * 32));
      expect(result.ok, isFalse);
      expect(result.state, FetchState.failed);
      expect(await File('${dir.path}/svc-bad.gguf').exists(), isFalse);
      expect(await ModelFetchService.isReady(source('svc-bad', 'ff' * 32)), isFalse);
    });

    test('الحذف عبر الخدمة يمسح كل شيء', () async {
      final data = pattern(200, (i) => i * 37 + 11);
      ModelFetchService.debugStreamFactory = (url) async* {
        yield data;
      };
      final ok = source('svc-del', pattern200Sha);
      await ModelFetchService.fetch(ok);
      expect(await ModelFetchService.isReady(ok), isTrue);
      await ModelFetchService.delete(ok.id);
      expect(await ModelFetchService.isReady(ok), isFalse);
      expect(await File('${dir.path}/svc-del.gguf').exists(), isFalse);
    });

    test('verifyFull عبر الخدمة يعيد البصمة للسليم', () async {
      final data = pattern(200, (i) => i * 37 + 11);
      ModelFetchService.debugStreamFactory = (url) async* {
        yield data;
      };
      final ok = source('svc-vf', pattern200Sha);
      await ModelFetchService.fetch(ok);
      expect(await ModelFetchService.verifyFull(ok), pattern200Sha);
    });
  });
}
