import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/bot_proposals_service.dart';
import 'package:wasl_chat/services/bot_service.dart';

/// اختبارات نقية للنظام البيئي الموسع (المرحلة 15 ج — 1.7.0، ترحيل 039):
/// تحليل صفوف المقترحات والإحصاءات دفاعياً، والنصوص العربية الصادقة،
/// وترجمة أخطاء القرار الإشرافي الحقيقية — بلا شبكة ولا خادم.
void main() {
  group('تحليل صف المقترح', () {
    final good = {
      'message_id': 'm1',
      'conversation_id': 'c1',
      'room_title': 'الغرفة العامة',
      'bot_id': 'b1',
      'bot_name': 'حارس_المجتمع',
      'target_id': 'u1',
      'target_name': 'عبد الله',
      'action': 'mute',
      'minutes': 60,
      'reason': 'سبام واضح',
      'created_at': '2026-11-18T09:00:00Z',
    };

    test('صف كامل كامل الحقول يُقرأ كما هو', () {
      final p = BotProposal.fromRow(good)!;
      expect(p.messageId, 'm1');
      expect(p.botName, 'حارس_المجتمع');
      expect(p.targetName, 'عبد الله');
      expect(p.action, 'mute');
      expect(p.minutes, 60);
      expect(p.reason, 'سبام واضح');
    });

    test('الناقص الجوهري يُسقط بلا انهيار — لا مقترح شبح', () {
      for (final missing in [
        {'target_id': 'u1', 'action': 'mute'},
        {'message_id': 'm1', 'action': 'mute'},
        {'message_id': 'm1', 'target_id': 'u1'},
        {'message_id': '', 'conversation_id': 'c1', 'bot_id': 'b1',
         'action': 'mute', 'target_id': 'u1'},
      ]) {
        expect(BotProposal.fromRow(missing), isNull,
            reason: 'ناقص ${missing.keys.first} يُسقط الصف');
      }
    });

    test('إجراء غير معروف يُسقط — لا بطاقة لفعل لا يفهمه التطبيق', () {
      expect(
        BotProposal.fromRow({...good, 'action': 'ban'}),
        isNull,
        reason: 'الحظر قرار بشري أثقل — البوت لا يقترحه في هذه المرحلة',
      );
    });

    test('كتم بلا مدة يُسقط — لا كتم بلا مهلة معلنة', () {
      expect(BotProposal.fromRow({...good, 'minutes': null}), isNull);
      expect(BotProposal.fromRow({...good, 'minutes': 0}), isNull);
    });

    test('الأسماء الفارغة تهبط تسميات صادقة لا فراغات', () {
      final p = BotProposal.fromRow({...good, 'bot_name': '', 'target_name': ''})!;
      expect(p.botName, 'بوت');
      expect(p.targetName, 'عضو');
    });
  });

  group('النصوص الصادقة للمقترح', () {
    BotProposal build(String action, int? minutes, String reason) =>
        BotProposal.fromRow({
          'message_id': 'm1', 'conversation_id': 'c1', 'room_title': 'غرفة',
          'bot_id': 'b1', 'bot_name': 'حارس', 'target_id': 'u1',
          'target_name': 'سالم', 'action': action, 'minutes': minutes,
          'reason': reason, 'created_at': '2026-11-18T09:00:00Z',
        })!;

    test('وصف الكتم بالمدة العربية الصحيحة والسبب', () {
      expect(BotProposalsService.describe(build('mute', 60, 'سبام')),
          'كتم سالم لمدة ساعة واحدة — سبام');
      expect(BotProposalsService.describe(build('mute', 1, '')),
          'كتم سالم لمدة دقيقة واحدة');
      expect(BotProposalsService.describe(build('mute', 2, '')),
          'كتم سالم لمدة دقيقتان');
      expect(BotProposalsService.describe(build('mute', 5, '')),
          'كتم سالم لمدة 5 دقائق');
    });

    test('وصف الطرد بلا مدة إطلاقاً', () {
      final d = BotProposalsService.describe(build('kick', null, 'مخالفة'));
      expect(d, 'طرد سالم — مخالفة');
      expect(d, isNot(contains('مدة')));
    });

    test('نتيجة القرار تُعلن ما نُفّذ بصدق', () {
      final p = build('mute', 10, '');
      expect(BotProposalsService.outcomeLabel('muted', p),
          'نُفّذ كتم سالم لمدة 10 دقائق');
      expect(BotProposalsService.outcomeLabel('kicked', build('kick', null, '')),
          'نُفّذ طرد سالم');
      expect(BotProposalsService.outcomeLabel('rejected', p),
          'رُفض المقترح بلا أي إجراء');
      expect(BotProposalsService.outcomeLabel('??', p), 'عُولج المقترح');
    });
  });

  group('أخطاء القرار الإشرافي الحقيقية', () {
    test('كل خطأ خادم معلن برسالة عربية صادقة لا عفواً', () {
      expect(
        BotProposalsService.resolveErrorHint(
            Exception('not allowed: target is owner')),
        'لا يمكن إشراف مشرف — القرار يتخذ بأدوات العضو مباشرة',
      );
      expect(
        BotProposalsService.resolveErrorHint(Exception('cannot moderate yourself')),
        'لا يمكن إشراف على المشرف الموافق نفسه',
      );
      expect(
        BotProposalsService.resolveErrorHint(Exception('not a member')),
        'الهدف لم يعد عضواً — المقترح تجاوزه الزمن',
      );
      expect(
        BotProposalsService.resolveErrorHint(Exception('proposal not found')),
        'المقترح عُولج من مشرف آخر لحظة قبل قرارك',
      );
      expect(
        BotProposalsService.resolveErrorHint(Exception('not a community room')),
        'المقترح ليس في غرفة مجتمع',
      );
      expect(BotProposalsService.resolveErrorHint(Exception('anything else')),
          'تعذّر تنفيذ القرار — جرّب لاحقاً');
    });
  });

  group('تحليل إحصاءات البوت (ترحيل 039)', () {
    test('الصف الكامل يُقرأ كما هو', () {
      final s = BotStats.fromRow({
        'total_messages': 120,
        'messages_24h': 5,
        'last_message_at': '2026-11-18T09:00:00Z',
        'conversations': 3,
        'members_reached': 45,
        'proposals_pending': 2,
        'proposals_approved': 7,
        'proposals_rejected': 1,
      });
      expect(s.totalMessages, 120);
      expect(s.messages24h, 5);
      expect(s.conversations, 3);
      expect(s.membersReached, 45);
      expect(s.proposalsPending, 2);
      expect(BotStats.proposalsLabel(s),
          'معلقة 2 · منفذة 7 · مرفوضة 1');
    });

    test('الحقول الغريبة تهبط صفراً صادقاً — لا رقم مكتوظ', () {
      final s = BotStats.fromRow({
        'total_messages': -5,
        'messages_24h': 'كثير',
        'conversations': null,
        'members_reached': 12.0,
      });
      expect(s.totalMessages, 0);
      expect(s.messages24h, 0);
      expect(s.conversations, 0);
      expect(s.membersReached, 12, reason: 'العدد الصحيح القادم كرقم يُقبل');
      expect(BotStats.proposalsLabel(s), 'لا مقترحات بعد — بوتك يرصد ولا يقترح بعد');
    });

    test('الوصول المقاس معلن كتقدير لا عدّاً قاطعاً', () {
      expect(BotStats.reachLabel(0), 'لا وصول بعد');
      expect(BotStats.reachLabel(45), contains('قد يتكرر بين الغرف'));
    });

    test('آخر النشاط يعلن الغياب صادقاً ويقيس الصعود', () {
      expect(BotStats.lastActivity('', DateTime.now()), 'لا نشاط مسجل بعد');
      expect(BotStats.lastActivity('باد', DateTime.now()), 'لا نشاط مسجل بعد');
      final now = DateTime.now();
      expect(BotStats.lastActivity(now.toIso8601String(), now), 'الآن');
    });
  });
}
