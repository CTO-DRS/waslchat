import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/album_service.dart';

Map<String, dynamic> _m(String id,
    {String? gid,
    String sender = 'a',
    String type = 'image',
    bool deleted = false,
    bool viewOnce = false}) {
  return {
    'id': id,
    'media_group_id': gid,
    'sender_id': sender,
    'type': type,
    if (deleted) 'deleted_at': '2026-11-14T00:00:00Z',
    if (viewOnce) 'view_once': true,
  };
}

void main() {
  group('تجميع الألبوم', () {
    test('رسائل بلا معرّف تُعرض منفردة كما كانت', () {
      final msgs = [_m('1'), _m('2'), _m('3')];
      final items = AlbumService.group(msgs);
      expect(items.length, 3);
      for (final it in items) {
        expect(it.length, 1);
      }
    });

    test('القطع المتتالية بمعرّف واحد تتجمع في ألبوم واحد', () {
      final msgs = [
        _m('1', gid: 'g1'),
        _m('2', gid: 'g1'),
        _m('3', gid: 'g1'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 1);
      expect(items.first.length, 3);
    });

    test('رسالة نصية بين قطعتي ألبوم تكسر التتابع', () {
      final msgs = [
        _m('1', gid: 'g1'),
        _m('t', type: 'text'),
        _m('2', gid: 'g1'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 3);
      expect(items[0].length, 1);
      expect(items[1].first['type'], 'text');
      expect(items[2].length, 1);
    });

    test('مرسل مختلف لنفس المعرّف يكسر الألبوم', () {
      final msgs = [
        _m('1', gid: 'g1', sender: 'a'),
        _m('2', gid: 'g1', sender: 'b'),
        _m('3', gid: 'g1', sender: 'a'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 3);
    });

    test('الرسالة المحذوفة لا تنضم للألبوم', () {
      final msgs = [
        _m('1', gid: 'g1'),
        _m('2', gid: 'g1', deleted: true),
        _m('3', gid: 'g1'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 3);
      expect(items[1].first['deleted_at'], isNotNull);
    });

    test('«عرض مرة واحدة» لا تنضم للألبوم وتكسر التتابع', () {
      final msgs = [
        _m('1', gid: 'g1'),
        _m('2', gid: 'g1', viewOnce: true),
        _m('3', gid: 'g1'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 3);
    });

    test('الحد الأقصى 10 قطع: الزائد يفتح ألبوماً جديداً بنفس المعرّف', () {
      final msgs = [
        for (var i = 0; i < 13; i++) _m('$i', gid: 'g1'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 2);
      expect(items[0].length, AlbumService.maxItems);
      expect(items[1].length, 3);
    });

    test('معرّف مختلف مجاور يفصل الألبومات', () {
      final msgs = [
        _m('1', gid: 'g1'),
        _m('2', gid: 'g1'),
        _m('3', gid: 'g2'),
        _m('4', gid: 'g2'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 2);
      expect(items[0].length, 2);
      expect(items[1].length, 2);
    });

    test('النص بين مقاطع الألبوم: التجميع يفصل بالرسالة النصية فقط', () {
      final msgs = [
        _m('1', gid: 'g1'),
        _m('2', gid: 'g1'),
        _m('t', type: 'text'),
        _m('3', gid: 'g1'),
        _m('4', gid: 'g1'),
      ];
      final items = AlbumService.group(msgs);
      expect(items.length, 3);
      expect(items.map((e) => e.length), [2, 1, 2]);
    });
  });

  group('العدّاد ومعرّف المجموعة', () {
    test('معرّف المجموعة فريد ومختلف في كل نداء', () {
      final a = AlbumService.newGroupId();
      final b = AlbumService.newGroupId();
      expect(a, isNot(b));
      expect(a.startsWith('alg_'), isTrue);
    });

    test('العدّاد يوضح الحد عند التجاوز', () {
      expect(AlbumService.counterLabel(5), '5 / 10');
      expect(AlbumService.counterLabel(12), contains('أقصى المسموح 10'));
    });

    test('الفيديو قابل للتجميع والمحوّل (عرض مرة واحدة) لا', () {
      expect(AlbumService.isGroupable(_m('v', type: 'video')), isTrue);
      expect(AlbumService.isGroupable(_m('v', type: 'video', viewOnce: true)), isFalse);
      expect(AlbumService.isGroupable(_m('t', type: 'text')), isFalse);
      expect(AlbumService.isGroupable(_m('v', type: 'voice')), isFalse);
    });
  });
}
