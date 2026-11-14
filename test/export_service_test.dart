import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/export_service.dart';

Map<String, dynamic> _m(String id, String sender, String type,
    {String? content,
    String? at,
    bool deleted = false,
    bool viewOnce = false,
    int? durationMs}) {
  return {
    'id': id,
    'sender_id': sender,
    'type': type,
    if (content != null) 'content': content,
    'created_at': at ?? '2026-11-14T10:30:00Z',
    if (deleted) 'deleted_at': '2026-11-14T11:00:00Z',
    if (viewOnce) 'view_once': true,
    if (durationMs != null) 'duration_ms': durationMs,
  };
}

void main() {
  group('بناء نص التصدير', () {
    test('الترويسة تحمل العنوان والتاريخ والعدد والإصدار', () {
      final text = ExportService.buildText(
        title: 'محادثة تجريبية',
        msgs: [_m('1', 'u1', 'text', content: 'مرحبا')],
        senderOf: (_) => 'صديق',
        textOf: (m) => m['content'] as String?,
        myId: 'me',
        now: DateTime(2026, 11, 14, 13, 45),
        appVersion: '0.20.0',
      );
      expect(text, contains('محادثة تجريبية'));
      expect(text, contains('وصل شات'));
      expect(text, contains('2026-11-14'));
      expect(text, contains('عدد الرسائل: 1'));
      expect(text, contains('0.20.0'));
    });

    test('رسالة نصية وردت باسم مرسلها والوقت', () {
      final text = ExportService.buildText(
        title: 'ت',
        msgs: [_m('1', 'u1', 'text', content: 'صباح الخير')],
        senderOf: (_) => 'صديق',
        textOf: (m) => m['content'] as String?,
        myId: 'me',
        now: DateTime(2026),
        appVersion: '0.20.0',
      );
      expect(text, contains('صديق: صباح الخير'));
    });

    test('رسالتي تظهر باسم «أنت» بغض النظر عن الدالة', () {
      final text = ExportService.buildText(
        title: 'ت',
        msgs: [_m('1', 'me', 'text', content: 'ردّي أنا')],
        senderOf: (_) => 'لا ينبغي أن يظهر',
        textOf: (m) => m['content'] as String?,
        myId: 'me',
        now: DateTime(2026),
        appVersion: '0.20.0',
      );
      expect(text, contains('أنت: ردّي أنا'));
      expect(text, isNot(contains('لا ينبغي أن يظهر')));
    });

    test('الوسائط تظهر بتسمياتها لا بمحتواها المشفر', () {
      final text = ExportService.buildText(
        title: 'ت',
        msgs: [
          _m('1', 'u1', 'image', content: 'v1.أظرفمشفر'),
          _m('2', 'u1', 'voice', durationMs: 65000),
          _m('3', 'u1', 'video', viewOnce: true),
          _m('4', 'u1', 'file'),
        ],
        senderOf: (_) => 'صديق',
        textOf: (m) => m['content'] as String?,
        myId: 'me',
        now: DateTime(2026),
        appVersion: '0.20.0',
      );
      expect(text, contains('📷 صورة'));
      expect(text, contains('🎤 رسالة صوتية (1:05)'));
      expect(text, contains('🎬 فيديو (عرض مرة واحدة)'));
      expect(text, contains('📎 ملف'));
      expect(text, isNot(contains('v1.أظرفمشفر')));
    });

    test('المحذوفة تظهر كتسمية حذف والمشفرة غير المفكوكة كقفل', () {
      final text = ExportService.buildText(
        title: 'ت',
        msgs: [
          _m('1', 'u1', 'text', content: 'v2.لنيفك', deleted: true),
          _m('2', 'u1', 'text', content: 'v2.لميفكأبعد'),
        ],
        senderOf: (_) => 'صديق',
        textOf: (m) => null,
        myId: 'me',
        now: DateTime(2026),
        appVersion: '0.20.0',
      );
      expect(text, contains('🚫 حُذفت هذه الرسالة'));
      expect(text, contains('🔒 رسالة مشفرة'));
    });

    test('فاصل الأيام بين رسالتين بتاريخين مختلفين', () {
      final text = ExportService.buildText(
        title: 'ت',
        msgs: [
          _m('1', 'me', 'text', content: 'أ', at: '2026-11-13T10:30:00Z'),
          _m('2', 'me', 'text', content: 'ب', at: '2026-11-14T10:30:00Z'),
        ],
        senderOf: (_) => 'x',
        textOf: (m) => m['content'] as String?,
        myId: 'me',
        now: DateTime(2026),
        appVersion: '0.20.0',
      );
      expect(text, contains('— 2026-11-13 —'));
      expect(text, contains('— 2026-11-14 —'));
    });

    test('اسم الملف آمن: يزيل المحارف الخطرa ويقلم الطول', () {
      final n1 = ExportService.fileName('ملف/غير:آمن*؟', DateTime(2026, 11, 14));
      expect(n1, isNot(contains('/')));
      expect(n1, isNot(contains(':')));
      expect(n1, contains('2026-11-14'));
      expect(n1.endsWith('.txt'), isTrue);
      final n2 = ExportService.fileName('ع' * 60, DateTime(2026));
      expect(n2.length, lessThan(80));
      final n3 = ExportService.fileName('', DateTime(2026));
      expect(n3, contains('محادثة'));
    });

    test('قائمة فارغة تعطي ترويسة بعدد صفر', () {
      final text = ExportService.buildText(
        title: 'ت',
        msgs: const [],
        senderOf: (_) => 'x',
        textOf: (_) => null,
        myId: 'me',
        now: DateTime(2026),
        appVersion: '0.20.0',
      );
      expect(text, contains('عدد الرسائل: 0'));
    });
  });
}
