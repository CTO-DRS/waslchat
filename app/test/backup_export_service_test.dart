import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/backup_export_service.dart';

/// اختبارات نقية للنسخة الاحتياطية الكاملة المشفرة (المرحلة 13 أ — 0.26.0):
/// بناء الأرشيف والدورة الكاملة تشفيراً وفكاً ورفض كلمة السر الخاطئة ورفض
/// العبث في أي بايت — كل شيء على الجهاز حصراً والصيغة موثقة في الترويسة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BackupConversation conv({
    required int msgs,
    String title = 'محادثة',
    bool isGroup = false,
  }) =>
      BackupConversation(
        id: 'c-${title.hashCode}',
        title: title,
        isGroup: isGroup,
        messages: List.generate(
          msgs,
          (i) => BackupMessage(
            senderName: i.isEven ? 'أنت' : 'الطرف',
            text: 'رسالة $i في $title — مرحباً بالعربية والهمزة والرمز 🙂',
            createdAtIso: '2026-11-16T10:${(i % 60).toString().padLeft(2, '0')}:00Z',
            mine: i.isEven,
          ),
        ),
      );

  Map<String, dynamic> sampleArchive() => BackupExportService.buildArchive(
        appVersion: '0.26.0+57',
        conversations: [
          conv(msgs: 3, title: 'أحمد'),
          conv(msgs: 2, title: 'عائلتنا', isGroup: true),
        ],
        ownerName: 'المالك',
      );

  test('بناء الأرشيف: الصيغة والإحصاءات والترويسة الصادقة', () {
    final a = sampleArchive();
    expect(a['format'], BackupExportService.formatVersion);
    expect(a['app'], '0.26.0+57');
    expect(a['owner'], 'المالك');
    expect(a['limit_per_conversation'],
        BackupExportService.messagesPerConversation);
    final cs = a['conversations'] as List;
    expect(cs.length, 2);
    final (nc, nm) = BackupExportService.archiveStats(a);
    expect(nc, 2);
    expect(nm, 5);
  });

  test('الدورة الكاملة: تشفير ثم فك يعيد نفس المحتوى والصيغة', () async {
    final a = sampleArchive();
    final bytes =
        await BackupExportService.encryptArchive(a, 'كلمة السر 123');
    // الترويسة السحرية أولاً — أول 7 بايتات
    expect(utf8.decode(bytes.sublist(0, 7)), BackupExportService.magic);
    // salt(32) + nonce(12) + ciphertext+mac(16) — الحجم أكبر من النص الخام
    expect(bytes.length,
        greaterThan(7 + 32 + 12 + 16));
    final back = await BackupExportService.decryptArchive(
        bytes, 'كلمة السر 123');
    expect(back, isNotNull);
    expect(back!['format'], BackupExportService.formatVersion);
    expect(back['owner'], 'المالك');
    final cs = back['conversations'] as List;
    expect(cs.length, 2);
    final c0 = cs.first as Map;
    expect(c0['title'], 'أحمد');
    final msgs = c0['messages'] as List;
    expect(msgs.length, 3);
    expect((msgs.first as Map)['s'], 'أنت');
    expect((msgs.first as Map)['x'], contains('مرحباً بالعربية'));
  });

  test('كلمة السر الخاطئة تعيد null — بلا جزئيات وبلا استثناء', () async {
    final bytes =
        await BackupExportService.encryptArchive(sampleArchive(), 'الصحيحة 1234');
    final r = await BackupExportService.decryptArchive(bytes, 'خاطئة 1234');
    expect(r, isNull);
    final r2 = await BackupExportService.decryptArchive(bytes, '');
    expect(r2, isNull);
  });

  test('بايت واحد معبوث في أي موضع يفشل الفك كلياً (AAD + MAC)', () async {
    final a = sampleArchive();
    // عبث في ciphertext (وسط الملف)
    final b1 = List<int>.of(
        await BackupExportService.encryptArchive(a, 'كلمة السر 123'));
    final mid = b1.length ~/ 2;
    b1[mid] = b1[mid] ^ 0x01;
    expect(await BackupExportService.decryptArchive(b1, 'كلمة السر 123'), isNull);
    // عبث في الترويسة السحرية نفسها (AAD)
    final b2 = List<int>.of(
        await BackupExportService.encryptArchive(a, 'كلمة السر 123'));
    b2[2] = b2[2] ^ 0x01;
    expect(await BackupExportService.decryptArchive(b2, 'كلمة السر 123'), isNull);
    // عبث في الملح (الاشتقاق يختلف كلياً)
    final b3 = List<int>.of(
        await BackupExportService.encryptArchive(a, 'كلمة السر 123'));
    b3[10] = b3[10] ^ 0x01;
    expect(await BackupExportService.decryptArchive(b3, 'كلمة السر 123'), isNull);
  });

  test('ملفات غريبة قصيرة أو ناقصة تعيد null بلا استثناءات', () async {
    expect(await BackupExportService.decryptArchive(const [], 'أي كلمة'), isNull);
    expect(await BackupExportService.decryptArchive([1, 2, 3], 'أي كلمة'), isNull);
    expect(
        await BackupExportService.decryptArchive(
            utf8.encode('ليس ملف وصل إطلاقاً — نص عادي'), 'أي كلمة'),
        isNull);
    expect(
        await BackupExportService.decryptArchive(
            utf8.encode(BackupExportService.magic), 'أي كلمة'),
        isNull);
  });

  test('كلمة السر القصيرة تُرفض عند البناء بلا استثناء متصاعد', () async {
    expect(BackupExportService.passphraseOk('1234567'), isFalse);
    expect(BackupExportService.passphraseOk('12345678'), isTrue);
    expect(
        () => BackupExportService.encryptArchive(sampleArchive(), 'قصيرة'),
        throwsArgumentError);
  });

  test('conversationsOf يعيد المحادثات جاهزة للقراءة — وفك فاشل يعيد null',
      () async {
    final bytes =
        await BackupExportService.encryptArchive(sampleArchive(), 'كلمة السر 123');
    final cs = await BackupExportService.conversationsOf(bytes, 'كلمة السر 123');
    expect(cs, isNotNull);
    expect(cs!.length, 2);
    expect(cs[1].isGroup, isTrue);
    expect(cs[1].title, 'عائلتنا');
    expect(cs[0].messages.first.media, isFalse);
    final bad = await BackupExportService.conversationsOf(bytes, 'لا شيء');
    expect(bad, isNull);
  });

  test('رسالة وسيط تُحفظ كتسمية (m:1) — لا محتوى ملف في النسخة', () {
    final m = const BackupMessage(
      senderName: 'الطرف',
      text: '📷 صورة',
      createdAtIso: '2026-11-16T10:00:00Z',
      mine: false,
      media: true,
    );
    final j = m.toJson();
    expect(j['m'], 1);
    expect(j['s'], 'الطرف');
    final back = BackupMessage.fromJson(j);
    expect(back.media, isTrue);
    expect(back.text, '📷 صورة');
    // الرسالة النصية بلا علم وسيط
    final t = const BackupMessage(
        senderName: 'أنت', text: 'مرحباً', createdAtIso: '', mine: true).toJson();
    expect(t.containsKey('m'), isFalse);
  });

  test('الملف بسلسلة JSON كاملة ثم من الخريطة مرة أخرى — توافق الصيغة', () async {
    final a = sampleArchive();
    final bytes = await BackupExportService.encryptArchive(a, 'كلمة السر 123');
    final back = await BackupExportService.decryptArchive(bytes, 'كلمة السر 123');
    final cs = await BackupExportService.conversationsOf(bytes, 'كلمة السر 123');
    // الطريقان يعيدان البنية نفسها
    final csFromMap = ((back!['conversations'] as List))
        .map((c) => BackupConversation.fromJson(Map<String, dynamic>.from(c)))
        .toList();
    expect(csFromMap.length, cs!.length);
    expect(csFromMap.first.title, cs.first.title);
    expect(csFromMap.first.messages.length, cs.first.messages.length);
  });

  test('اسم الملف بالتاريخ بصيغة موثقة', () {
    expect(BackupExportService.fileName(DateTime(2026, 11, 16)),
        'wasl_backup_2026-11-16.waslbackup');
    expect(BackupExportService.fileName(DateTime(2026, 1, 5)),
        'wasl_backup_2026-01-05.waslbackup');
  });

  test('سطر ملخص المحادثة صادق بالنوع والعدد', () {
    final c = conv(msgs: 7, title: 'عمل', isGroup: true);
    expect(BackupExportService.conversationSummaryLine(c),
        'مجموعة «عمل» — 7 رسالة');
    final c2 = conv(msgs: 1, title: 'أحمد');
    expect(BackupExportService.conversationSummaryLine(c2),
        'محادثة «أحمد» — 1 رسالة');
  });
}
