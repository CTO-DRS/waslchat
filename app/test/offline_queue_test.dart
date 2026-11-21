import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/offline_queue_service.dart';

/// اختبارات نقية لطابور الإرسال بلا شبكة (المرحلة 13 أ — 1.1.0) —
/// بلا شبكة ولا مخزن ولا ملفات: النواة النقية حصراً. العقد المثبتة:
/// الترتيب FIFO صارم، التفريد بالمعرّف، السقوف المعلنة، النجاة من قتل
/// التطبيق بالتدوير، وعدم تكرار رسالة ولا حذفها قبل تأكيد النجاح.
void main() {
  PendingSend text(String id, {int created = 1000, int attempts = 0}) =>
      PendingSend(
        id: id,
        conversationId: 'conv',
        kind: 'text',
        type: 'text',
        content: 'enc-payload-$id',
        createdAtMs: created,
        attempts: attempts,
      );

  group('الإدخال والترتيب والتفريد', () {
    test('FIFO صارم: الأقدم يدخل أولاً ويخرج أولاً — الترتيب لا يفسد', () {
      final q = OfflineQueueCore()
        ..enqueue(text('a', created: 1000))
        ..enqueue(text('b', created: 2000))
        ..enqueue(text('c', created: 3000));
      expect(q.items.map((x) => x.id).toList(), ['a', 'b', 'c']);
      expect(q.next()!.id, 'a');
    });

    test('المكرر بالمعرّف مرفوض — لا تكرار رسالة أبداً', () {
      final q = OfflineQueueCore()
        ..enqueue(text('a'))
        ..enqueue(text('a'));
      expect(q.items.length, 1);
      expect(q.enqueue(text('a')), isFalse);
    });

    test('السقف 50 محفوظة: فوقه مرفوض بصدق لا صمت', () {
      final q = OfflineQueueCore();
      for (var i = 0; i < OfflineQueueCore.maxPending; i++) {
        expect(q.enqueue(text('m$i')), isTrue);
      }
      expect(q.enqueue(text('overflow')), isFalse);
      expect(q.items.length, OfflineQueueCore.maxPending);
    });

    test('الحذف يعيد الحقيقة: موجود يحذف وغير موجود يكذب', () {
      final q = OfflineQueueCore()..enqueue(text('a'));
      expect(q.remove('a'), isTrue);
      expect(q.remove('a'), isFalse);
      expect(q.items, isEmpty);
    });
  });

  group('المحاولات والتوقف الصادق', () {
    test('محاولات أقل من السقف تستحق إعادة محاولة آلية', () {
      expect(OfflineQueueCore.shouldAutoRetry(0), isTrue);
      expect(OfflineQueueCore.shouldAutoRetry(7), isTrue);
      expect(OfflineQueueCore.shouldAutoRetry(8), isFalse);
    });

    test('المتعثرة (ما بعد 8 محاولات) تُتجاوز ولا تسد الطريق لمن بعدها', () {
      final q = OfflineQueueCore()
        ..enqueue(text('stuck', created: 1000, attempts: 8))
        ..enqueue(text('fresh', created: 2000));
      expect(q.next()!.id, 'fresh');
    });

    test('كل شيء متعثر → الطابور صادق في صمته: next يعيد null', () {
      final q = OfflineQueueCore()..enqueue(text('stuck', attempts: 8));
      expect(q.next(), isNull);
    });

    test('withAttempt يزيد المحاولات ويحفظ كل الحقول الأخرى', () {
      final p = text('a');
      final p2 = p.withAttempt();
      expect(p2.attempts, p.attempts + 1);
      expect(p2.id, p.id);
      expect(p2.content, p.content);
      expect(p2.createdAtMs, p.createdAtMs);
    });
  });

  group('النجاة من قتل التطبيق — التدوير كامل بلا فقد ولا تكرار', () {
    test('encode → decode يعيد نفس الطابور بالترتيب نفسه', () {
      final q = OfflineQueueCore()
        ..enqueue(text('a', created: 1000))
        ..enqueue(PendingSend(
          id: 'med',
          conversationId: 'conv',
          kind: 'media',
          type: 'image',
          content: '{"mk":"abc"}',
          mediaFile: '/tmp/x.bin',
          ext: 'enc.bin',
          contentType: 'application/octet-stream',
          durationMs: 5,
          viewOnce: true,
          groupId: 'g1',
          replyTo: 'r1',
          rememberKey: '{"mk":"abc"}',
          createdAtMs: 2000,
          attempts: 3,
        ));
      final back = OfflineQueueCore.decode(q.encode());
      expect(back.items.length, 2);
      expect(back.items[0].id, 'a');
      expect(back.items[1].id, 'med');
      expect(back.items[1].kind, 'media');
      expect(back.items[1].mediaFile, '/tmp/x.bin');
      expect(back.items[1].viewOnce, isTrue);
      expect(back.items[1].attempts, 3);
    });

    test('الأشكال المرتجفة تُسقط والصالح يبقى — لا انهيار ولا اختراع', () {
      final back = OfflineQueueCore.decode(
          '[{"id":"","conversation_id":"c","kind":"text","type":"text","content":"x"},'
          '{"id":"ok","conversation_id":"c","kind":"text","type":"text","content":"enc"},'
          '{"id":"bad","conversation_id":"c","kind":" weird","type":"text","content":"x"},'
          '"ليس خريطة",'
          '{"id":"m","conversation_id":"c","kind":"media","type":"image","content":"{}"}]');
      expect(back.items.length, 2);
      expect(back.items[0].id, 'ok');
      expect(back.items[1].id, 'm');
    });

    test('نص فارغ أو مشوه يعيد طابوراً فارغاً بلا استثناء', () {
      expect(OfflineQueueCore.decode(null).items, isEmpty);
      expect(OfflineQueueCore.decode('').items, isEmpty);
      expect(OfflineQueueCore.decode('ليس جيسون').items, isEmpty);
      expect(OfflineQueueCore.decode('[]').items, isEmpty);
    });
  });
}
