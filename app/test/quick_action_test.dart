import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/quick_action_service.dart';

void main() {
  group('فك حمولات الإجراءات السريعة', () {
    test('فتح بلا معرّف رسالة', () {
      final a = QuickActionService.parse('open|conv-1');
      expect(a, isNotNull);
      expect(a!.kind, QuickActionKind.open);
      expect(a.conversationId, 'conv-1');
      expect(a.messageId, isNull);
    });

    test('فتح بمعرّف رسالة (يخدم إجراء التفاعل)', () {
      final a = QuickActionService.parse('open|conv-1|msg-9');
      expect(a!.kind, QuickActionKind.open);
      expect(a.conversationId, 'conv-1');
      expect(a.messageId, 'msg-9');
    });

    test('فتح بمعرّف رسالة فارغ يعامَل كغيابه', () {
      final a = QuickActionService.parse('open|conv-1|');
      expect(a!.messageId, isNull);
    });

    test('تمييز مقروء', () {
      final a = QuickActionService.parse('read|conv-7');
      expect(a!.kind, QuickActionKind.markRead);
      expect(a.conversationId, 'conv-7');
    });

    test('تفاعل بإيموجي يحمل المعرّف والإيموجي كاملاً', () {
      final a = QuickActionService.parse('react|conv-1|msg-3|❤️');
      expect(a!.kind, QuickActionKind.react);
      expect(a.conversationId, 'conv-1');
      expect(a.messageId, 'msg-3');
      expect(a.emoji, '❤️');
    });

    test('إيموجي يحمل فاصل عمودي لا يُقص', () {
      final a = QuickActionService.parse('react|c|m|👍|👍');
      expect(a!.emoji, '👍|👍');
    });

    test('رد سريع', () {
      final a = QuickActionService.parse('reply|conv-2');
      expect(a!.kind, QuickActionKind.reply);
      expect(a.conversationId, 'conv-2');
    });

    test('حمولات غريبة تعيد null ولا تنفجر: فارغ وقصير ومجهول وبلا محادثة', () {
      expect(QuickActionService.parse(null), isNull);
      expect(QuickActionService.parse(''), isNull);
      expect(QuickActionService.parse('open'), isNull);
      expect(QuickActionService.parse('zoom|conv-1'), isNull);
      expect(QuickActionService.parse('open|'), isNull);
      expect(QuickActionService.parse('react|conv-1'), isNull);
      expect(QuickActionService.parse('react|conv-1|msg'), isNull);
    });

    test('التشفير المدور: encode ثم parse يعيد القيم نفسها', () {
      final open = QuickActionService.parse(
          QuickActionService.encodeOpen('c9', messageId: 'm5'));
      expect(open!.kind, QuickActionKind.open);
      expect(open.conversationId, 'c9');
      expect(open.messageId, 'm5');
      final react = QuickActionService.parse(
          QuickActionService.encodeReact('c1', 'm2', '❤️'));
      expect(react!.kind, QuickActionKind.react);
      expect(react.messageId, 'm2');
      expect(react.emoji, '❤️');
      final mark =
          QuickActionService.parse(QuickActionService.encodeMarkRead('c3'));
      expect(mark!.kind, QuickActionKind.markRead);
      final reply =
          QuickActionService.parse(QuickActionService.encodeReply('c4'));
      expect(reply!.kind, QuickActionKind.reply);
    });
  });
}
