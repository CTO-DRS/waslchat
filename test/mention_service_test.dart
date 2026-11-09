import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/mention_service.dart';

/// اختبارات وحدة: الإشارة @ في المجموعات (بند المرحلة 1 — 0.4.5).
/// مواضع المدى تتحقق ذاتياً بـ substring بدل أرقام مُعدّاة يدوياً.
void main() {
  group('الترميز والفك', () {
    test('بلا إشارات: النص يعيد كما هو حرفياً (بلا JSON)', () {
      const text = 'مرحبا بالجميع 👋';
      expect(MentionCodec.encode(text, const []), text);
      expect(MentionCodec.isStructured(text), isFalse);
      expect(MentionCodec.decode(text), isNull);
      expect(MentionCodec.displayText(text), text);
    });

    test('ترميز وفك جولة كاملة بعربية وإيموجي وإشارتين', () {
      const text = 'يا @أحمد و@سارة نصّاً مع 🎨';
      final atAhmad = text.indexOf('@أحمد');
      final atSara = text.indexOf('@سارة');
      final encoded = MentionCodec.encode(text, [
        MentionSpan('u1', atAhmad, atAhmad + 5),
        MentionSpan('u2', atSara, atSara + 5),
      ]);
      expect(MentionCodec.isStructured(encoded), isTrue);
      final st = MentionCodec.decode(encoded)!;
      expect(st.text, text);
      expect(st.mentions.length, 2);
      expect(st.mentions[0].userId, 'u1');
      expect(text.substring(st.mentions[0].start, st.mentions[0].end), '@أحمد');
      expect(text.substring(st.mentions[1].start, st.mentions[1].end), '@سارة');
      expect(MentionCodec.displayText(encoded), text);
    });

    test('فك محتوى فاسد أو معبوث: null أو إهمال المدى السيئ', () {
      expect(MentionCodec.decode('{"t":"غيره","x":"نص"}'), isNull);
      expect(MentionCodec.decode('{"t":"wasl-text-v1"}'), isNull); // بلا x
      expect(MentionCodec.decode('{"t":"wasl-text-v1","x":5}'), isNull);
      expect(MentionCodec.decode('{"t":"wasl-text-v1","x":null,"m":[]}'),
          isNull);
      final st = MentionCodec.decode(
          '{"t":"wasl-text-v1","x":"نص","m":['
          '{"u":"u1","s":0,"e":99},' // خارج النص
          '{"u":"u2","s":3,"e":1},' // معكوس
          '{"u":"u3","s":0,"e":2},' // سليم
          '"تالف"]}');
      expect(st!.mentions.length, 1);
      expect(st.mentions.first.userId, 'u3');
    });
  });

  group('ضبط المدى عند التحرير (تحقق ذاتي بالـsubstring)', () {
    test('إدراج قبل الإشارة يزيحها للأمام', () {
      const oldText = 'hi @Ahmad hello';
      const newText = 'well hi @Ahmad hello';
      final tokens = [MentionToken('u1', 'Ahmad', 3, 9)];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(tokens.single.start, 8);
      expect(newText.substring(tokens.single.start, tokens.single.end),
          '@Ahmad');
    });

    test('إدراج بعد الإشارة لا يغيّرها', () {
      const oldText = 'hi @Ahmad hello';
      const newText = 'hi @Ahmad hello my friend';
      final tokens = [MentionToken('u1', 'Ahmad', 3, 9)];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(tokens.single.start, 3);
      expect(tokens.single.end, 9);
      expect(newText.substring(3, 9), '@Ahmad');
    });

    test('حذف قبل الإشارة يزيحها للخلف', () {
      const oldText = 'wow hi @Ahmad hello';
      const newText = 'hi @Ahmad hello';
      final tokens = [MentionToken('u1', 'Ahmad', 7, 13)];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(newText.substring(tokens.single.start, tokens.single.end),
          '@Ahmad');
    });

    test('حذف حرف داخل اسم الإشارة يلغيها، ويُزاح غيرها صح', () {
      const oldText = 'hi @Ahmad and @Sara';
      const newText = 'hi @hmad and @Sara'; // حُذف A من @Ahmad
      final atSara = oldText.indexOf('@Sara');
      final tokens = [
        MentionToken('u1', 'Ahmad', 3, 9),
        MentionToken('u2', 'Sara', atSara, atSara + 5),
      ];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(tokens.length, 1);
      expect(tokens.single.userId, 'u2');
      expect(newText.substring(tokens.single.start, tokens.single.end),
          '@Sara');
    });

    test('إدراج داخل الإشارة يلغيها', () {
      const oldText = 'hi @Ahmad';
      const newText = 'hi @AXhmAd'; // إدراج X داخل الاسم مرتين
      final tokens = [MentionToken('u1', 'Ahmad', 3, 9)];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(tokens, isEmpty);
    });

    test('حذف الإشارة الأولى كاملة يلغيها، والثانية تُزاح صح', () {
      const oldText = '@Ahmad and @Sara';
      const newText = 'and @Sara'; // حُذفت «@Ahmad »
      final atSara = oldText.indexOf('@Sara');
      final tokens = [
        MentionToken('u1', 'Ahmad', 0, 6),
        MentionToken('u2', 'Sara', atSara, atSara + 5),
      ];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(tokens.length, 1);
      expect(tokens.single.userId, 'u2');
      expect(newText.substring(tokens.single.start, tokens.single.end),
          '@Sara');
    });

    test('إشارة داخل المنطقة المُعاد كتابتها تموت حتى لو لم تُمَس حروفاً', () {
      const oldText = 'a @X b';
      const newText = 'a ZZZZZZ b'; // استبدال @X بالكامل
      final tokens = [MentionToken('u1', 'X', 2, 4)];
      MentionTracker.adjust(tokens, oldText, newText);
      expect(tokens, isEmpty);
    });

    test('النصان متساويان: لا تغيير', () {
      final tokens = [MentionToken('u1', 'Ahmad', 3, 9)];
      MentionTracker.adjust(tokens, 'نص ثابت', 'نص ثابت');
      expect(tokens.single.start, 3);
    });
  });

  group('استعلام المنتقي', () {
    test('يعيد الاستعلام بعد @ في البداية وبعد فراغ وبعد سطر', () {
      expect(MentionTracker.queryAt('@Ah', 3), 'Ah');
      expect(MentionTracker.queryAt('hi @S', 5), 'S');
      expect(MentionTracker.queryAt('مرحبا @', 7), '');
      expect(MentionTracker.queryAt('سطر\n@س', 6), 'س');
    });

    test('يرفض @ في وسط كلمة أو بريد إلكتروني', () {
      expect(MentionTracker.queryAt('user@mail', 9), isNull,
          reason: '@ داخل بريد لا تفتح المنتقي');
      expect(MentionTracker.queryAt('ab@cd', 5), isNull);
    });

    test('الفراغ يقطع الاستعلام', () {
      expect(MentionTracker.queryAt('@Ahmad سلام', 11), isNull);
      expect(MentionTracker.queryAt('hi @a b', 7), isNull);
    });

    test('مؤشر خارج النص أو على البداية يعيد null', () {
      expect(MentionTracker.queryAt('@Ahmad', 0), isNull);
      expect(MentionTracker.queryAt('@Ahmad', 99), isNull);
      expect(MentionTracker.queryAt('', 0), isNull);
    });
  });
}
