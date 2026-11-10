import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/thread_service.dart';

/// اختبارات سلاسل الردود والمنشورات المثبّتة (0.5.1 — المرحلة 3 بند 2).
/// المنطق المحلي خالص فوق صفوف البثّ كما تصل من الخادم.
void main() {
  Map<String, dynamic> msg(String id,
      {String? root,
      String type = 'text',
      bool deleted = false,
      String? reply}) {
    return {
      'id': id,
      'sender_id': 'u-$id',
      'type': type,
      'content': 'c-$id',
      'created_at': '2026-11-10T10:00:00Z',
      if (root != null) 'thread_root_id': root,
      if (deleted) 'deleted_at': '2026-11-10T10:01:00Z',
      if (reply != null) 'reply_to': reply,
    };
  }

  group('threadCounts', () {
    test('سلسلة بلا ردود تعطي خريطة فارغة', () {
      final c = ThreadService.threadCounts([msg('a'), msg('b')]);
      expect(c, isEmpty);
    });

    test('ردّان على جذر واحد يحسبان للجذر', () {
      final c = ThreadService.threadCounts([
        msg('root'),
        msg('r1', root: 'root'),
        msg('r2', root: 'root'),
      ]);
      expect(c, {'root': 2});
    });

    test('سلسلتان مستقلتان تعدّان كل منهما لجذرها', () {
      final c = ThreadService.threadCounts([
        msg('x'), msg('x1', root: 'x'),
        msg('y'), msg('y1', root: 'y'), msg('y2', root: 'y'),
      ]);
      expect(c, {'x': 1, 'y': 2});
    });

    test('ردّ داخل سلسلة يتبع الجذر الأصلي (بلا تعشيق — يفرضه الخادم)', () {
      // الخادم يعيد الكتابة إلى الجذر قبل الحفظ، فالعميل لا يرى أبداً
      // thread_root يشير لرسالة داخل سلسلة — الاختبار يوثّق هذا الافتراض
      final c = ThreadService.threadCounts([
        msg('root'), msg('r1', root: 'root'), msg('r2', root: 'root'),
      ]);
      expect(c.keys, everyElement('root'));
    });

    test('قيم غير سلسلة نصية تُهمل ولا تكسر العدّ', () {
      final rows = [msg('a'), {...msg('b'), 'thread_root_id': 123}];
      final c = ThreadService.threadCounts(rows);
      expect(c, isEmpty);
    });
  });

  group('mainFlow', () {
    test('يرسّل الجذر ويستبعد ردود السلاسل من التدفق', () {
      final rows = [
        msg('a'),
        msg('root'), msg('r1', root: 'root'), msg('r2', root: 'root'),
        msg('b'),
      ];
      final flow = ThreadService.mainFlow(rows);
      expect(flow.map((m) => m['id']), ['a', 'root', 'b']);
    });

    test('حذف الجذر فيزيائياً يفتح ردوده (set null من الخادم)', () {
      // بعد on delete set null يصبح ربط الردود null فتعود للتدفق
      // بعد الكتابة الخادمية (set null) تصل الردود بروابط null
      final rows = [msg('r1'), msg('r2')];
      final flow = ThreadService.mainFlow(rows);
      expect(flow.length, 2);
    });
  });

  group('threadMessages', () {
    test('يعرض الجذر أولاً ثم ردوده بالترتيب الوارد', () {
      final rows = [
        msg('a'),
        msg('r1', root: 'root'),
        msg('root'),
        msg('r2', root: 'root'),
      ];
      final t = ThreadService.threadMessages(rows, 'root');
      expect(t.map((m) => m['id']), ['root', 'r1', 'r2']);
    });

    test('سلسلة مجهولة تعطي قائمة فارغة', () {
      expect(ThreadService.threadMessages([msg('a')], 'nope'), isEmpty);
    });
  });

  group('threadLabel', () {
    test('المفرد والجمع العربي السليم', () {
      expect(ThreadService.threadLabel(1), 'ردّ واحد');
      expect(ThreadService.threadLabel(2), 'ردّان');
      expect(ThreadService.threadLabel(5), '5 ردود');
      expect(ThreadService.threadLabel(0), 'سلسلة فارغة');
    });
  });

  group('المثبتات', () {
    test('السقف المحلي مطابق للسقف الخادمي في 029 (10)', () {
      expect(kMaxPinsPerRoom, 10);
    });

    test('رسائل MAX_PINS تترجم لرسالة عربية واضحة بالحد نفسه', () {
      final t = ThreadService.pinErrorText(
          Exception('{"message":"MAX_PINS","code":"P0001"}'));
      expect(t, contains('10'));
    });

    test('رفض غير المشرفين يترجم لرسالة المشرفين', () {
      expect(ThreadService.pinErrorText(Exception('admins only')),
          contains('للمشرفين'));
    });

    test('رسالة محذوفة مرفوضة التثبيت برسالة واضحة', () {
      expect(ThreadService.pinErrorText(Exception('message not found')),
          contains('غير متاحة'));
    });

    test('خطأ مجهول يعطي رسالة عامة بلا استثناء خام', () {
      expect(ThreadService.pinErrorText(Exception('xyz')),
          'تعذّر تنفيذ العملية');
    });
  });
}
