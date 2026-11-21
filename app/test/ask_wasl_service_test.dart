// اختبارات «اسأل وصل» — محرك الإجابة من الأرشيف (المرحلة 14 أ — 1.3.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/ask_wasl_service.dart';

AskPassage _p(String cid, String text, String iso) =>
    AskPassage(conversationId: cid, text: text, createdAtIso: iso);

void main() {
  group('بناء الإجابة', () {
    test('سؤال عن اجتماع يجيب بالمقطع ذي الصلة ويعلن مصدره', () {
      final a = AskWaslService.answer([
        _p('c1', 'نلتقي في السوق الساعة خمسة عصرا بالضبط',
            '2026-11-14T15:00:00Z'),
        _p('c2', 'الطقس جميل اليوم نذهب للبحر', '2026-11-14T16:00:00Z'),
      ], 'متى الموعد في السوق؟');
      expect(a, isNotNull);
      expect(a!.lines, hasLength(1));
      expect(a.lines.first.text, contains('السوق'));
      expect(a.lines.first.conversationId, 'c1');
      expect(a.lines.first.atIso, '2026-11-14T15:00:00Z');
    });

    test('سؤال بلا مقاطع قريبة يعيد null — لا تخمين ولا ادعاء معرفة', () {
      final a = AskWaslService.answer([
        _p('c1', 'أرسلت لك الملف المطلوب صباحا', '2026-11-14T09:00:00Z'),
      ], 'كيف حال الطقس في السفر؟');
      expect(a, isNull);
    });

    test('سؤال فارغ أو بلا كلمات معنوية يعيد null', () {
      expect(AskWaslService.answer([
        _p('c1', 'نص', '2026-11-14T09:00:00Z'),
      ], ''), isNull);
      expect(AskWaslService.answer([
        _p('c1', 'نص', '2026-11-14T09:00:00Z'),
      ], '   '), isNull);
    });

    test('قائمة مقاطع فارغة تعيد null', () {
      expect(AskWaslService.answer(const [], 'متى الموعد؟'), isNull);
    });

    test('التكرار الحرفي يُقصى — المقطع نفسه لا يدخل مرتين', () {
      final a = AskWaslService.answer([
        _p('c1', 'الموعد الساعة خمسة', '2026-11-14T09:00:00Z'),
        _p('c2', 'الموعد الساعة خمسة', '2026-11-14T10:00:00Z'),
      ], 'متى الموعد؟');
      expect(a, isNotNull);
      expect(a!.lines, hasLength(1));
    });

    test('أقصى ثلاثة أسطر بالانتقاء: الأقوى صلةً فقط يدخل', () {
      final a = AskWaslService.answer([
        _p('c1', 'موعد الاجتماع خمسة', '2026-11-14T09:00:00Z'),
        _p('c2', 'موعد العشاء تسعة', '2026-11-14T10:00:00Z'),
        _p('c3', 'موعد الرحلة صباحا', '2026-11-14T11:00:00Z'),
        _p('c4', 'موعد التسليم غدا', '2026-11-14T12:00:00Z'),
      ], 'متى الموعد؟', maxLines: 3);
      expect(a, isNotNull);
      expect(a!.lines.length, lessThanOrEqualTo(3));
    });

    test('العرض زمني تصاعدي بعد الانتقاء بالصلة — السياق كما جرى', () {
      final a = AskWaslService.answer([
        _p('c1', 'موعد الرحلة صباحا يوم الخميس', '2026-11-10T08:00:00Z'),
        _p('c2', 'موعد الاجتماع الرسمي خمسة', '2026-11-14T15:00:00Z'),
      ], 'متى الموعد؟', maxLines: 2);
      expect(a, isNotNull);
      expect(a!.lines.first.atIso, '2026-11-10T08:00:00Z');
      expect(a.lines.last.atIso, '2026-11-14T15:00:00Z');
    });

    test('رفع العتبة يمنع المقاطع الضعيفة الصلة', () {
      final passages = [
        _p('c1', 'وصلت صباحا في الوقت', '2026-11-14T09:00:00Z'),
      ];
      expect(
        AskWaslService.answer(passages, 'متى الموعد؟',
            minScore: 0.9),
        isNull,
      );
    });

    test('مواءمة المرادفات: سؤال يُجيب مقطعاً مجرد التعريف يشاركه المرادفة لا الكلمة', () {
      // «متى الموعد؟» يتوسع بـ«الساعه» بصيغة ال، والمقطع لا يحمل إلا «ساعه»
      // المجردة — المواءمة هي ما يصلهما، وبلاها تكون الإجابة null.
      final a = AskWaslService.answer([
        _p('c1', 'نلتقي الساعة خمسة عصرا', '2026-11-14T15:00:00Z'),
      ], 'متى الموعد؟');
      expect(a, isNotNull);
      expect(a!.lines.first.text, contains('ساعة'));
    });

    test('التشكيل والهمزات في المقاطع لا تكسر الصلة', () {
      final a = AskWaslService.answer([
        _p('c1', 'المُوعدُ السّاعةَ خَمْسة', '2026-11-14T17:00:00Z'),
      ], 'متى الموعد؟');
      expect(a, isNotNull);
    });
  });

  group('تنسيق الإجابة ومصادرها', () {
    test('format يعلن المصدر باسم المحادثة والتاريخ', () {
      final a = AskWaslService.answer([
        _p('c1', 'موعد الاجتماع خمسة عصرا', '2026-11-14T15:00:00Z'),
      ], 'متى الموعد؟')!;
      final f = AskWaslService.format(a, nameOf: (id) => 'فريق العمل');
      expect(f, contains('بناءً على أرشيفك'));
      expect(f, contains('فريق العمل'));
      expect(f, contains('موعد الاجتماع'));
      expect(f, contains('2026'));
    });

    test('format بلا مُسمّي محادثات يعيد «محادثة» عامة لا معرفاً خاماً', () {
      final a = AskWaslService.answer([
        _p('abc-123', 'موعد الاجتماع خمسة عصرا', '2026-11-14T15:00:00Z'),
      ], 'متى الموعد؟')!;
      expect(AskWaslService.format(a), contains('محادثة'));
    });

    test('النص الطويل يُقتطع بشرطة إعلام لا يُعرض كاملاً (بناء مباشر للإجابة)', () {
      final long = 'موعد الاجتماع الخمسة عصرا ' + 'تفصيل ' * 60;
      final a = AskAnswer(
        question: 'متى الموعد؟',
        lines: [
          AskLine(
              text: long,
              conversationId: 'c1',
              atIso: '2026-11-14T15:00:00Z',
              score: 0.5),
        ],
      );
      final f = AskWaslService.format(a);
      expect(f.length, lessThan(long.length));
      expect(f, contains('…'));
    });
  });

  group('الإفصاح والثوابت', () {
    test('الإفصاح معلن وصادق — لا ادعاء توليد ولا شبكة', () {
      expect(AskWaslService.disclosure, contains('جهازك'));
      expect(AskWaslService.disclosure, contains('استخلاص'));
    });

    test('العتبة والسقف ثوابت معلنة', () {
      expect(AskWaslService.minScore, greaterThan(0));
      expect(AskWaslService.maxLines, 3);
    });
  });
}
