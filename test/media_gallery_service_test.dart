import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/media_gallery_service.dart';

Map<String, dynamic> _m(String id, String sender, String type,
    {String? content,
    String? at,
    bool deleted = false,
    bool viewOnce = false,
    String? mediaUrl}) {
  return {
    'id': id,
    'sender_id': sender,
    'type': type,
    if (content != null) 'content': content,
    'created_at': at ?? '2026-11-14T10:30:00Z',
    if (deleted) 'deleted_at': '2026-11-14T11:00:00Z',
    if (viewOnce) 'view_once': true,
    'media_url': mediaUrl ?? 'storage/media/$id',
  };
}

void main() {
  group('جمع وسائط المحادثة', () {
    test('يجمع الأنواع الأربعة ويستبعد النصوص والمحذوفة وعرض-مرة-واحدة', () {
      final msgs = [
        _m('1', 'u1', 'text', content: 'نص عادي'), // خارج
        _m('2', 'u1', 'image'), // داخل
        _m('3', 'u2', 'voice'), // داخل
        _m('4', 'u2', 'video', content: '{"name":"clip.mp4","size":123}'), // داخل + اسم
        _m('5', 'u1', 'file', content: '{"name":"doc.pdf","size":456}'), // داخل + اسم
        _m('6', 'u1', 'image', deleted: true), // محذوفة: خارج
        _m('7', 'u2', 'image', viewOnce: true), // عرض مرة واحدة: خارج
        _m('8', 'u2', 'image', mediaUrl: ''), // بلا مسار: خارج
      ];
      final items = MediaGalleryService.collect(msgs, (m) => m['content'] as String?, myId: 'u1');
      expect(items.length, 4);
      expect(items.map((i) => i.type), containsAll(['image', 'voice', 'video', 'file']));
    });

    test('الترتيب الأحدث أولاً', () {
      final msgs = [
        _m('1', 'u1', 'image', at: '2026-11-14T09:00:00Z'),
        _m('2', 'u1', 'image', at: '2026-11-14T12:00:00Z'),
        _m('3', 'u1', 'image', at: '2026-11-14T10:00:00Z'),
      ];
      final items = MediaGalleryService.collect(msgs, (_) => null, myId: 'u1');
      expect(items.map((i) => i.messageId).toList(), ['2', '3', '1']);
    });

    test('تمييز رسائلي عن الواردة', () {
      final msgs = [_m('1', 'me', 'image'), _m('2', 'other', 'image')];
      final items = MediaGalleryService.collect(msgs, (_) => null, myId: 'me');
      expect(items.firstWhere((i) => i.messageId == '1').mine, isTrue);
      expect(items.firstWhere((i) => i.messageId == '2').mine, isFalse);
    });

    test('اسم الملف من الميتا المفكوكة والتعليق من نص الصورة', () {
      final msgs = [
        _m('1', 'u1', 'video', content: '{"name":"فيديو العيد.mp4","size":99}'),
        _m('2', 'u1', 'image', content: 'عيد مبارك'),
        _m('3', 'u1', 'image', content: 'v2.AAAA'), // ما زال مشفراً: بلا تعليق
      ];
      final items = MediaGalleryService.collect(msgs, (m) => m['content'] as String?, myId: 'u1');
      expect(items.firstWhere((i) => i.messageId == '1').name, 'فيديو العيد.mp4');
      expect(items.firstWhere((i) => i.messageId == '2').caption, 'عيد مبارك');
      expect(items.firstWhere((i) => i.messageId == '3').caption, isNull);
    });
  });

  group('الفلترة والعدّ', () {
    final msgs = [
      _m('1', 'u1', 'image'),
      _m('2', 'u1', 'image'),
      _m('3', 'u1', 'video'),
      _m('4', 'u1', 'file', content: '{"name":"a.pdf"}'),
      _m('5', 'u1', 'voice'),
    ];
    final items = MediaGalleryService.collect(msgs, (m) => m['content'] as String?, myId: 'u1');

    test('تبويب الكل يعيد الجميع', () {
      expect(MediaGalleryService.filter(items, 'الكل').length, 5);
    });

    test('صور وفيديو ومقسم ملفات (ملفات+صوت) وصوت', () {
      expect(MediaGalleryService.filter(items, 'صور').length, 2);
      expect(MediaGalleryService.filter(items, 'فيديو').length, 1);
      expect(MediaGalleryService.filter(items, 'ملفات').length, 2);
      expect(MediaGalleryService.filter(items, 'صوت').length, 1);
    });

    test('عدادات كل تبويب تطابق الفلترة', () {
      final counts = MediaGalleryService.counts(items);
      expect(counts['الكل'], 5);
      expect(counts['صور'], 2);
      expect(counts['ملفات'], 2);
    });
  });
}
