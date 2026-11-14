// اختبارات الترتيب الذكي للمحادثات (المرحلة 9 أ — 0.22.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/smart_order_service.dart';

Map<String, dynamic> _c(
  String id, {
  DateTime? lastAt,
  int unread = 0,
  bool pinned = false,
  bool muted = false,
}) {
  return {
    'conversation_id': id,
    'last_at': (lastAt ?? DateTime(2026, 11, 14, 12)).toIso8601String(),
    'unread': unread,
    'pinned': pinned,
    'muted': muted,
  };
}

final _now = DateTime(2026, 11, 14, 12, 30);

void main() {
  group('نقاط الحداثة', () {
    test('النطاقات المعايرة من الأحدث للأقدم', () {
      expect(
        SmartOrderService.recencyScore(_now.subtract(const Duration(minutes: 30)), _now),
        30,
      );
      expect(
        SmartOrderService.recencyScore(_now.subtract(const Duration(hours: 5)), _now),
        22,
      );
      expect(
        SmartOrderService.recencyScore(_now.subtract(const Duration(hours: 20)), _now),
        14,
      );
      expect(
        SmartOrderService.recencyScore(_now.subtract(const Duration(days: 2)), _now),
        8,
      );
      expect(
        SmartOrderService.recencyScore(_now.subtract(const Duration(days: 6)), _now),
        4,
      );
      expect(
        SmartOrderService.recencyScore(_now.subtract(const Duration(days: 20)), _now),
        1,
      );
    });

    test('رسالة بساعة مستقبلية (خلل جهاز) تعامل كالآن ولا تصبح سالبة', () {
      expect(
        SmartOrderService.recencyScore(_now.add(const Duration(hours: 3)), _now),
        30,
      );
    });
  });

  group('نقاط المحادثة', () {
    test('غير المقروء يرفع النقاط بسقف 20', () {
      final low = SmartOrderService.score(_c('a', unread: 1), openCounts: {}, now: _now);
      final mid = SmartOrderService.score(_c('a', unread: 10), openCounts: {}, now: _now);
      final cap = SmartOrderService.score(_c('a', unread: 50), openCounts: {}, now: _now);
      final cap20 = SmartOrderService.score(_c('a', unread: 20), openCounts: {}, now: _now);
      expect(mid, greaterThan(low));
      expect(cap, cap20); // السقف يعمل
    });

    test('التفاعل: نمو لوغاريتمي بسقف 24', () {
      final one = SmartOrderService.score(_c('a'), openCounts: {'a': 1}, now: _now);
      final many = SmartOrderService.score(_c('a'), openCounts: {'a': 100}, now: _now);
      final none = SmartOrderService.score(_c('a'), openCounts: {}, now: _now);
      expect(one, greaterThan(none));
      expect(many, greaterThan(one));
      expect(many - none, closeTo(24, 0.01)); // السقف عند 100 فتح
    });

    test('إشارة @ في المعاينة ترفع 10 نقاط', () {
      final withAt = SmartOrderService.score(
        _c('a'),
        preview: 'ذكرتك @أحمد في الاجتماع',
        openCounts: {},
        now: _now,
      );
      final without = SmartOrderService.score(_c('a'), openCounts: {}, now: _now);
      expect(withAt - without, 10);
    });

    test('الكتم يخفض النقاط', () {
      final muted = SmartOrderService.score(_c('a', muted: true), openCounts: {}, now: _now);
      final notMuted = SmartOrderService.score(_c('a'), openCounts: {}, now: _now);
      expect(muted, lessThan(notMuted));
    });

    test('بلا last_at صالح: تعامل كمحادثة هادئة قديمة ولا يرمي', () {
      final c = _c('a')..['last_at'] = 'not-a-date';
      expect(() => SmartOrderService.score(c, openCounts: {}, now: _now),
          returnsNormally);
    });
  });

  group('الترتيب الكامل', () {
    test('المثبّت يبقى أولاً دائماً', () {
      final chats = [
        _c('hot', lastAt: _now.subtract(const Duration(minutes: 5)), unread: 9),
        _c('pin', pinned: true, lastAt: _now.subtract(const Duration(days: 9))),
      ];
      final out = SmartOrderService.order(chats, openCounts: {}, now: _now);
      expect(out.first['conversation_id'], 'pin');
    });

    test('الأعلى نقاطاً أولاً بين غير المثبّت: غير المقروء يسبق القديم', () {
      final chats = [
        _c('quiet', lastAt: _now.subtract(const Duration(days: 5))),
        _c('noisy', lastAt: _now.subtract(const Duration(hours: 3)), unread: 4),
      ];
      final out = SmartOrderService.order(chats, openCounts: {}, now: _now);
      expect(out.first['conversation_id'], 'noisy');
    });

    test('التفاعل السابق يرفع المحادثة الهادئة المفتوحة كثيراً', () {
      final chats = [
        _c('fav', lastAt: _now.subtract(const Duration(hours: 10))),
        _c('new', lastAt: _now.subtract(const Duration(hours: 3))),
      ];
      final withoutHistory = SmartOrderService.order(chats, openCounts: {}, now: _now);
      expect(withoutHistory.first['conversation_id'], 'new');
      final withHistory = SmartOrderService.order(
        chats,
        openCounts: {'fav': 60},
        now: _now,
      );
      expect(withHistory.first['conversation_id'], 'fav');
    });

    test('التعادل يحسم بترتيب الخادم الأصلي (ثبات)', () {
      final chats = [
        _c('first', lastAt: _now.subtract(const Duration(hours: 1))),
        _c('second', lastAt: _now.subtract(const Duration(hours: 1))),
      ];
      final out = SmartOrderService.order(chats, openCounts: {}, now: _now);
      expect(out.map((c) => c['conversation_id']).toList(), ['first', 'second']);
    });

    test('القائمة الأصلية لا تُعدَّل', () {
      final chats = [
        _c('quiet', lastAt: _now.subtract(const Duration(days: 5))),
        _c('noisy', lastAt: _now.subtract(const Duration(hours: 3)), unread: 4),
      ];
      SmartOrderService.order(chats, openCounts: {}, now: _now);
      expect(chats.first['conversation_id'], 'quiet');
    });

    test('قائمة فارغة تعيد قائمة فارغة', () {
      expect(SmartOrderService.order([], openCounts: {}, now: _now), isEmpty);
    });
  });

  group('الإفصاح', () {
    test('نص الإفصاح يذكر الجهاز والمثبّت ومفتاح التعطيل', () {
      expect(SmartOrderService.disclosure, contains('جهازك'));
      expect(SmartOrderService.disclosure, contains('المثبّت'));
      expect(SmartOrderService.disclosure, contains('التعطيل'));
    });
  });
}
