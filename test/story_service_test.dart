import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/e2e_service.dart';
import 'package:wasl_chat/services/story_service.dart';

/// اختبارات وحدة لطبقة تشفير الحالات (بدون شبكة: أزواج مفاتيح محلية)
/// — نمط اختبارات e2e_service_test.dart نفسه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final x25519 = X25519();
  final aes = AesGcm.with256bits();
  const storyId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

  Future<(SimpleKeyPair, SimplePublicKey)> identity() async {
    final p = await x25519.newKeyPair();
    return (p, await p.extractPublicKey());
  }

  Future<SecretKey> newStoryKey() => aes.newSecretKey();

  // ---------- تغليف مفتاح الحالة ----------

  test('الناشر يغلّف مفتاح الحالة لجهة اتصال، والجهة تفكه فيعيد نفس المفتاح', () async {
    final (nadia, _) = await identity(); // الناشرة
    final nadiaPub = await nadia.extractPublicKey();
    final (omar, omarPub) = await identity(); // جهة الاتصال
    final key = await newStoryKey();

    final wrapped = await StoryService.wrapStoryKey(
        storyKey: key, storyId: storyId, publisherPair: nadia, contactPub: omarPub);
    expect(E2eService.isEncrypted(wrapped), isTrue);
    expect(wrapped.length, lessThan(700)); // قيد wrapped_key في القاعدة

    final out = await StoryService.unwrapStoryKey(
        wrapped: wrapped, storyId: storyId, myPair: omar, publisherPub: nadiaPub);
    expect(out, isNotNull);
    expect(await out!.extractBytes(), await key.extractBytes());
  });

  test('الناشر يفك ظرفه هو (لقراءة حالاته من جهاز آخر)', () async {
    final (nadia, nadiaPub) = await identity();
    final key = await newStoryKey();
    final wrapped = await StoryService.wrapStoryKey(
        storyKey: key, storyId: storyId, publisherPair: nadia, contactPub: nadiaPub);
    final out = await StoryService.unwrapStoryKey(
        wrapped: wrapped, storyId: storyId, myPair: nadia, publisherPub: nadiaPub);
    expect(await out!.extractBytes(), await key.extractBytes());
  });

  test('غريب لا يفك ظرفاً لم يُغلَّف له', () async {
    final (nadia, _) = await identity();
    final (omar, omarPub) = await identity();
    final (eve, evePub) = await identity();
    final key = await newStoryKey();
    final wrapped = await StoryService.wrapStoryKey(
        storyKey: key, storyId: storyId, publisherPair: nadia, contactPub: omarPub);
    // عين تحاول الفك بمفتاحها هي
    final out = await StoryService.unwrapStoryKey(
        wrapped: wrapped, storyId: storyId, myPair: eve, publisherPub: evePub);
    expect(out, isNull);
  });

  test('نقل الظرف إلى حالة أخرى يفشل (AAD + salt = معرف الحالة)', () async {
    final (nadia, nadiaPub) = await identity();
    final (omar, omarPub) = await identity();
    final key = await newStoryKey();
    final wrapped = await StoryService.wrapStoryKey(
        storyKey: key, storyId: storyId, publisherPair: nadia, contactPub: omarPub);
    const otherStory = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    final out = await StoryService.unwrapStoryKey(
        wrapped: wrapped, storyId: otherStory, myPair: omar, publisherPub: nadiaPub);
    expect(out, isNull);
  });

  test('عبث في الظرف يعيد null (تكامل GCM)', () async {
    final (nadia, nadiaPub) = await identity();
    final (omar, omarPub) = await identity();
    final key = await newStoryKey();
    final wrapped = await StoryService.wrapStoryKey(
        storyKey: key, storyId: storyId, publisherPair: nadia, contactPub: omarPub);
    final parts = wrapped.split('.');
    final ct = base64Decode(parts[2]);
    ct[0] = ct[0] ^ 0x01;
    final tampered = 'v1.${parts[1]}.${base64Encode(ct)}.${parts[3]}';
    final out = await StoryService.unwrapStoryKey(
        wrapped: tampered, storyId: storyId, myPair: omar, publisherPub: nadiaPub);
    expect(out, isNull);
  });

  // ---------- محتوى الحالة (تعليق/وسائط) بمفتاح الحالة ----------

  test('تعليق الحالة: تشفير ثم فك يعيد الأصل (عربي + إيموجي)', () async {
    final key = await newStoryKey();
    const plain = 'صباح الخير 🌅 من وصل شات';
    final enc = await E2eService.encryptText(key, storyId, plain);
    expect(E2eService.isEncrypted(enc), isTrue);
    expect(await E2eService.decryptText(key, storyId, enc), plain);
  });

  test('وسائط الحالة: تشفير ثم فك يعيد البايتات (غلاف 28 بايت)', () async {
    final key = await newStoryKey();
    final data = Uint8List.fromList(
        List<int>.generate(2048, (i) => (i * 13 + (i % 97)) & 0xFF));
    final enc = await E2eService.encryptBytes(key, storyId, data);
    expect(enc.length, data.length + 12 + 16);
    final out = await E2eService.decryptBytes(key, storyId, enc);
    expect(out, data);
  });

  test('مفتاح حالة آخر لا يفك تعليق حالة غيرها', () async {
    final k1 = await newStoryKey();
    final k2 = await newStoryKey();
    final enc = await E2eService.encryptText(k1, storyId, 'سر');
    expect(await E2eService.decryptText(k2, storyId, enc), isNull);
  });

  // ---------- الأدوات ----------

  test('uuidV4: صيغة سليمة وتفرد', () {
    final ids = <String>{};
    for (var i = 0; i < 200; i++) {
      final u = StoryService.uuidV4();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(u), isTrue, reason: u);
      ids.add(u);
    }
    expect(ids.length, 200);
  });

  test('StoryItem.fromRow: يقرأ سطر stories_feed و my_stories ويحسب المتبقي', () {
    final feedRow = {
      'story_id': storyId,
      'author_id': '11111111-1111-4111-8111-111111111111',
      'author_name': 'نادية',
      'author_avatar': null,
      'type': 'image',
      'media_path': 'nadia/$storyId.enc.bin',
      'caption': 'v1.AAAA.BBBB.CCCC',
      'bg': null,
      'created_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
      'expires_at': DateTime.now().toUtc().add(const Duration(hours: 22)).toIso8601String(),
      'wrapped_key': 'v1.AAAA.BBBB.CCCC',
    };
    final s = StoryItem.fromRow(feedRow, mine: false);
    expect(s.id, storyId);
    expect(s.authorName, 'نادية');
    expect(s.mine, isFalse);
    expect(s.remaining.inHours, inInclusiveRange(21, 22));

    final mineRow = {
      'story_id': storyId,
      'author_id': '22222222-2222-4222-8222-222222222222',
      'author_name': null,
      'author_avatar': null,
      'type': 'text',
      'media_path': null,
      'caption': 'v1.AAAA.BBBB.CCCC',
      'bg': 'teal',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now().toUtc().toIso8601String(),
      'wrapped_key': 'v1.AAAA.BBBB.CCCC',
      'views': 7,
    };
    final m = StoryItem.fromRow(mineRow, mine: true);
    expect(m.mine, isTrue);
    expect(m.views, 7);
    expect(m.type, 'text');
  });
}
