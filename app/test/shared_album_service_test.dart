/// اختبارات الألبومات المشتركة (1.20.0): الغرف المسموحة جماعية حصراً،
/// لا صلاحية جديدة (المضاف يزيل قطعته والمنشئ يحذف ألبومه)، حدود معلنة
/// (5 ألبومات للغرفة و50 قطعة)، بلا تكرار، وترتيب الإضافة محفوظ.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/shared_album_service.dart';

void main() {
  final now = DateTime(2026, 11, 20, 12);
  SharedAlbum _album({String creator = 'a'}) => SharedAlbum(
        id: 'alb-1',
        conversationId: 'conv-1',
        title: 'رحلتنا',
        createdBy: creator,
        createdAt: now,
        items: [],
      );

  group('الغرف المسموحة', () {
    test('الجماعية تستضيف الألبومات والخاصة ترفض', () {
      expect(SharedAlbumService.canHostAlbums(isGroup: true), isTrue);
      expect(SharedAlbumService.canHostAlbums(isGroup: false), isFalse);
    });

    test('إنشاء في غرفة خاصة رفض صريح', () {
      final out = SharedAlbumService.createAlbum(
        isGroup: false,
        isMember: true,
        memberId: 'a',
        title: 'ألبوم',
        currentAlbumCount: 0,
        albumId: 'x',
        now: now,
      );
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('الغرف الجماعية حصراً'));
    });

    test('إنشاء في غرفة جماعية: ناجح وعنوانه مقصوص من الفراغ', () {
      final out = SharedAlbumService.createAlbum(
        isGroup: true,
        isMember: true,
        memberId: 'a',
        title: '  رحلتنا  ',
        currentAlbumCount: 0,
        albumId: 'alb-1',
        now: now,
      );
      expect(out.isOk, isTrue);
      expect(out.value.title, 'رحلتنا');
      expect(out.value.createdBy, 'a');
    });

    test('أسباب الإنشاء تجمع لا أولها (عضوية + عنوان + حد)', () {
      final out = SharedAlbumService.createAlbum(
        isGroup: true,
        isMember: false,
        memberId: 'a',
        title: '   ',
        currentAlbumCount: 5,
        albumId: 'x',
        now: now,
      );
      expect(out.isRefused, isTrue);
      expect(out.reasons.length, 3);
      expect(out.reasons.any((r) => r.contains('ليست عضواً')), isTrue);
      expect(out.reasons.any((r) => r.contains('العنوان فارغ')), isTrue);
      expect(out.reasons.any((r) => r.contains('بلغ الحد')), isTrue);
    });
  });

  group('القطع — بلا صلاحية جديدة', () {
    test('إضافة وترتيب الإضافة محفوظ ومنع التكرار', () {
      var album = _album();
      final r1 = SharedAlbumService.addItem(
          isMember: true, memberId: 'a', messageId: 'm1',
          currentItems: album.items, now: now);
      expect(r1.isOk, isTrue);
      album = SharedAlbum(
          id: album.id, conversationId: album.conversationId,
          title: album.title, createdBy: album.createdBy,
          createdAt: album.createdAt, items: r1.value);
      final r2 = SharedAlbumService.addItem(
          isMember: true, memberId: 'b', messageId: 'm2',
          currentItems: album.items,
          now: now.add(const Duration(minutes: 1)));
      expect(r2.isOk, isTrue);
      // تكرار m1 مرفوض
      final dup = SharedAlbumService.addItem(
          isMember: true, memberId: 'a', messageId: 'm1',
          currentItems: r2.value, now: now);
      expect(dup.isRefused, isTrue);
      expect(dup.reasons.first, contains('موجودة في الألبوم أصلاً'));
    });

    test('القطعة يزيلها من أضافها حصراً — لا صلاحية جديدة', () {
      final items = [
        SharedAlbumItem(messageId: 'm1', addedBy: 'a', addedAt: now),
        SharedAlbumItem(messageId: 'm2', addedBy: 'b', addedAt: now),
      ];
      final stranger = SharedAlbumService.removeItem(
          memberId: 'c', messageId: 'm1', currentItems: items);
      expect(stranger.isRefused, isTrue);
      final otherOwner = SharedAlbumService.removeItem(
          memberId: 'b', messageId: 'm1', currentItems: items);
      expect(otherOwner.isRefused, isTrue);
      expect(otherOwner.reasons.first, contains('لمن أضافها حصراً'));
      final own = SharedAlbumService.removeItem(
          memberId: 'a', messageId: 'm1', currentItems: items);
      expect(own.isOk, isTrue);
      expect(own.value.length, 1);
      expect(own.value.first.messageId, 'm2');
    });

    test('حد القطع 50: القطعة 51 مرفوضة والسبب معلن', () {
      final items = List.generate(
          50,
          (i) => SharedAlbumItem(
              messageId: 'm$i', addedBy: 'a',
              addedAt: now.add(Duration(minutes: i))));
      final out = SharedAlbumService.addItem(
          isMember: true, memberId: 'a', messageId: 'm50',
          currentItems: items, now: now);
      expect(out.isRefused, isTrue);
      expect(out.reasons.first, contains('بلغ الحد'));
    });
  });

  group('حذف الألبوم والترتيب', () {
    test('الحذف لمنشئه حصراً', () {
      final refused = SharedAlbumService.deleteAlbum(
          memberId: 'b', album: _album(creator: 'a'));
      expect(refused.isRefused, isTrue);
      final ok = SharedAlbumService.deleteAlbum(
          memberId: 'a', album: _album(creator: 'a'));
      expect(ok.isOk, isTrue);
    });

    test('الترتيب بزمن الإضافة لا بأي ترتيب آخر', () {
      final album = SharedAlbum(
        id: 'x', conversationId: 'c', title: 'ت', createdBy: 'a',
        createdAt: now,
        items: [
          SharedAlbumItem(messageId: 'late', addedBy: 'a',
              addedAt: now.add(const Duration(hours: 2))),
          SharedAlbumItem(messageId: 'early', addedBy: 'b', addedAt: now),
        ],
      );
      final ordered = SharedAlbumService.orderedItems(album);
      expect(ordered.first.messageId, 'early');
      expect(ordered.last.messageId, 'late');
    });
  });
}
