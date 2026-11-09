import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/poll_service.dart';

/// اختبارات وحدة: استطلاعات الرأي المشفّرة (بند المرحلة 1 — 0.4.4)
/// الطبقة المشفّرة (E2eService) مُختبرة في ملفها الخاص — هنا نختبر
/// الترميز/فك المحتوى ومنطق الفرز «الأحدث يفوز».
void main() {
  group('تأليف الاستطلاع', () {
    test('ترميز وفك استطلاع عربي بإيموجي', () {
      final plain = PollService.encodePoll('ما أفضل وقت؟ ⏰', ['صباحاً', 'مساءً']);
      final poll = PollService.decodePoll(plain);
      expect(poll, isNotNull);
      expect(poll!.question, 'ما أفضل وقت؟ ⏰');
      expect(poll.options, ['صباحاً', 'مساءً']);
    });

    test('تقليم الفراغات حول السؤال والخيارات', () {
      final plain = PollService.encodePoll('  سؤال  ', [' أ ', 'ب  ', ' ']);
      final poll = PollService.decodePoll(plain);
      expect(poll!.options, ['أ', 'ب']);
    });

    test('رفض أقل من خيارين وأكثر من 10', () {
      expect(() => PollService.encodePoll('س', ['واحد']),
          throwsArgumentError);
      expect(
          () => PollService.encodePoll(
              'س', List.generate(11, (i) => 'خ$i')),
          throwsArgumentError);
    });

    test('رفض سؤال فارغ أو أطول من الحد', () {
      expect(() => PollService.encodePoll('', ['أ', 'ب']), throwsArgumentError);
      expect(() => PollService.encodePoll(' ' * 10, ['أ', 'ب']),
          throwsArgumentError);
      expect(() => PollService.encodePoll('س' * 281, ['أ', 'ب']),
          throwsArgumentError);
    });

    test('رفض خيار أطول من الحد', () {
      expect(() => PollService.encodePoll('س', ['أ', 'ب' * 101]),
          throwsArgumentError);
    });

    test('فك محتوى فاسد أو معبوث يعيد null', () {
      expect(PollService.decodePoll('ليس json'), isNull);
      expect(PollService.decodePoll('{"q":"س","o":["أ","ب"]}'), isNull, // بلا وسم
          reason: 'وسم النوع إلزامي — محتوى من خارج التطبيق يُرفض');
      expect(PollService.decodePoll('{"t":"wasl-poll-v1"}'), isNull);
      expect(PollService.decodePoll('{"t":"wasl-poll-v1","q":"","o":["أ","ب"]}'),
          isNull);
      expect(PollService.decodePoll('{"t":"wasl-poll-v1","q":"س","o":["أ"]}'),
          isNull);
      expect(
          PollService.decodePoll(
              '{"t":"wasl-poll-v1","q":"س","o":["أ","ب","خ3 المزيف الطويل جداً ${'ك' * 200}"]}'),
          isNull);
    });

    test('حد البايتات قبل التشفير', () {
      final ok = PollService.encodePoll('س', ['أ', 'ب']);
      expect(PollService.withinLimit(ok), isTrue);
      final long = PollService.encodePoll('س' * 280, List.generate(10, (i) => 'خ' * 100));
      expect(PollService.withinLimit(long), isFalse);
    });
  });

  group('التصويت والفرز', () {
    Map<String, dynamic> vote(String sender, int choice,
            {String? at, bool deleted = false}) =>
        {
          'id': '$sender-$choice-$at',
          'sender_id': sender,
          'content': PollService.encodeVote(choice),
          'created_at': at ?? '2026-11-09T10:00:00Z',
          if (deleted) 'deleted_at': '2026-11-09T11:00:00Z',
        };

    test('ترميز وفك الصوت', () {
      expect(PollService.decodeVote(PollService.encodeVote(3)), 3);
      expect(PollService.decodeVote(PollService.encodeVote(0)), 0);
      expect(PollService.decodeVote('garbage'), isNull);
      expect(PollService.decodeVote('{"c":1}'), isNull,
          reason: 'بلا وسم يُرفض');
      expect(PollService.decodeVote('{"t":"wasl-poll-vote-v1","c":-1}'), isNull);
      expect(
          () => PollService.encodeVote(-1), throwsArgumentError);
    });

    test('أحدث صوت يفوز عند تغيير الرأي', () {
      final tally = PollService.tally([
        vote('u1', 0, at: '2026-11-09T10:00:00Z'),
        vote('u1', 2, at: '2026-11-09T12:00:00Z'),
      ], optionCount: 3, me: 'u1');
      expect(tally.counts, [0, 0, 1]);
      expect(tally.totalVoters, 1);
      expect(tally.myChoice, 2);
      expect(tally.choiceByUser['u1'], 2);
    });

    test('مجموعة مصوّتين وترتيب صفوف غير مرتّب لا يفسد النتيجة', () {
      final tally = PollService.tally([
        vote('u2', 1, at: '2026-11-09T09:00:00Z'),
        vote('u1', 0, at: '2026-11-09T10:00:00Z'),
        vote('u2', 1, at: '2026-11-09T08:00:00Z'), // أقدم من الصوت النافذ
      ], optionCount: 2, me: 'u1');
      expect(tally.counts, [1, 1]);
      expect(tally.totalVoters, 2);
      expect(tally.myChoice, 0);
    });

    test('تجاهل المحذوف والفاسد والخارج عن النطاق', () {
      final tally = PollService.tally([
        vote('u1', 0, deleted: true),
        vote('u2', 99), // خارج النطاق
        {'id': 'x', 'sender_id': 'u3', 'content': 'فاسد', 'created_at': 'z'},
        {'id': 'y', 'sender_id': '', 'content': PollService.encodeVote(0), 'created_at': 'z'},
      ], optionCount: 2, me: 'u9');
      expect(tally.totalVoters, 0);
      expect(tally.counts, [0, 0]);
      expect(tally.myChoice, isNull);
    });

    test('استطلاع بلا أصوات', () {
      final tally = PollService.tally(const [], optionCount: 4, me: 'u1');
      expect(tally.totalVoters, 0);
      expect(tally.counts, [0, 0, 0, 0]);
      expect(tally.myChoice, isNull);
    });
  });
}
