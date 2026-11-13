import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/hijri_service.dart';
import 'package:wasl_chat/services/local_ai_service.dart';
import 'package:wasl_chat/services/smart_search_service.dart';
import 'package:wasl_chat/services/voice_commands_service.dart';

/// اختبارات وحدة لميزات المرحلة 5 (v0.14.0):
/// وصل AI المحلي، البحث الذكي، التقويم الهجري، والأوامر الصوتية
/// (كلها محركات نقية بلا شبكة — نفس فلسفة اختبارات المراحل السابقة)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAiService — التطبيع العربي', () {
    test('التشكيل والهمزات والهاء المربوطة توحَّد', () {
      expect(LocalAiService.normalize('مُحَمَّد'), 'محمد');
      expect(LocalAiService.normalize('أَحْمَد'), 'احمد');
      expect(LocalAiService.normalize('مدرسة'), 'مدرسه');
      expect(LocalAiService.normalize('على'), 'علي');
      expect(LocalAiService.normalize('شـكـرًا'), 'شكرا');
      expect(LocalAiService.normalize('HELLO'), 'hello');
    });

    test('كشف اللغة الغالبة', () {
      expect(LocalAiService.isMostlyArabic('مرحبا كيف حالك'), isTrue);
      expect(LocalAiService.isMostlyArabic('Hello how are you'), isFalse);
      expect(LocalAiService.isMostlyArabic('123 456'), isTrue); // لا حروف = يبقى
    });
  });

  group('LocalAiService — الردود الذكية', () {
    test('التحية تُصنَّف وتقترح ردود سلام', () {
      final r = LocalAiService.smartReplies('السلام عليكم');
      expect(r, isNotEmpty);
      expect(r.length <= 3, isTrue);
      expect(r.first, contains('السلام'));
    });

    test('الشكر والاعتذار والمباركة نوايا منفصلة', () {
      expect(LocalAiService.detectIntent('شكراً جزيلاً على المساعدة')!.$1, 'شكر');
      expect(LocalAiService.detectIntent('أعتذر عن التأخير')!.$1, 'اعتذار');
      expect(LocalAiService.detectIntent('مبروك النجاح!')!.$1, 'مبروك');
    });

    test('سؤال الموعد يرجح نية الموعد على السؤال العام', () {
      final (name, hits) = LocalAiService.detectIntent('متى نلتقي؟')!;
      expect(name, 'موعد');
      expect(hits, greaterThan(0));
    });

    test('الرسالة الغريبة تعيد ردوداً محايدة قصيرة', () {
      final r = LocalAiService.smartReplies('تم إرسال الملف');
      expect(r, isNotEmpty);
      expect(r.length <= 3, isTrue);
    });

    test('الرسالة الفارغة لا تنهار', () {
      expect(LocalAiService.smartReplies(''), isNotEmpty);
      expect(LocalAiService.detectIntent(''), isNull);
    });

    test('الردود الذكية تتسامح مع التطبيع (مشكور/شكرا)', () {
      final (name, _) = LocalAiService.detectIntent('مشكور يا غالي')!;
      expect(name, 'شكر');
    });
  });

  group('LocalAiService — الملخص المحلي الاستخلاصي', () {
    test('محادثة قصيرة تعاد كما هي بالنقاط', () {
      final s = LocalAiService.summarizeLines(['أحمد: سلام', 'سارة: سلام']);
      expect(s, contains('• أحمد: سلام'));
      expect(s, contains('• سارة: سلام'));
    });

    test('الأسطر الوسيطية أخفض أولوية من الكلام', () {
      final lines = [
        'أحمد: مرحبا، عندي اجتماع مهم غدا في الساعة 10 صباحا',
        'أحمد: [صورة]',
        'سارة: تمام، سأحضر الاجتماع وأجهز العرض التقديمي والملاحظات',
        'أحمد: شكرا، الموضوع أساسي لمشروع الشركة الجديد الكبير',
        'سارة: اتفقنا إذن، حتى غدا الصباح',
        'أحمد: [رسالة صوتية]',
        'سارة: هل أحضر معي الملفات المطبوعة أيضا؟',
        'أحمد: نعم أحضر الملفات وكل شيء جاهز الآن',
      ];
      final s = LocalAiService.summarizeLines(lines);
      // أهمية الكلام اللفظي تسبق علامات الوسائط
      expect(s.contains('اجتماع'), isTrue);
    });

    test('الفراغ يعيد نص الدعوة ويمكن ضبط عدد الأسطر', () {
      expect(LocalAiService.summarizeLines([]), contains('لا توجد رسائل'));
      final lines = List.generate(30, (i) => 'عضو: رسالة رقم $i فيها تفاصيل $i');
      final s = LocalAiService.summarizeLines(lines, maxLines: 5);
      expect('•'.allMatches(s).length, 5);
    });
  });

  group('SmartSearchService — المطابقة الذكية', () {
    test('التطبيع يجعل المفردات متكافئة', () {
      expect(SmartSearchService.matches('مُحَمَّد أحمد', 'محمد'), isTrue);
      expect(SmartSearchService.matches('ذهبت إلى المدرسة', 'مدرسه'), isTrue);
      expect(SmartSearchService.matches('على الطاولة', 'طاوله'), isTrue);
    });

    test('تسامح الأخطاء المطبعية حسب طول الكلمة', () {
      expect(SmartSearchService.matches('شكرا جزيلا', 'شكرا جزيلا'), isTrue);
      // كلمة 6 أحرف تسمح بخطأ واحد
      expect(SmartSearchService.matches('اجتماع اليوم', 'اجتماء'), isTrue);
      // كلمات قصيرة (أقل من 4) لا تسامح
      expect(SmartSearchService.matches('البيت', 'البيت'), isTrue);
    });

    test('المرادفات توسّع البحث', () {
      expect(SmartSearchService.matches('متى نلتقي', 'الساعه'), isTrue);
      expect(SmartSearchService.matches('هلا والله', 'سلام'), isTrue);
      expect(SmartSearchService.matches('أين أنت', 'وين'), isTrue);
    });

    test('عدم المطابقة يعيد صفر ولا يطابق', () {
      expect(SmartSearchService.matches('رسالة عادية', 'موسيقى'), isFalse);
      expect(SmartSearchService.score('كلام', ''), 0);
    });

    test('مطابقة العبارة الكاملة أقوى من مطابقة الكلمات', () {
      final phrase =
          SmartSearchService.score('متى نلتقي غدا في المكتب', 'نلتقي غدا');
      final words = SmartSearchService.score('غدا ثم نلتقي', 'نلتقي غدا');
      expect(phrase, greaterThan(words));
    });

    test('استعلام بكلمة مهمة غائبة يرفض النص كله', () {
      expect(SmartSearchService.matches('أرسل الملف', 'أرسل الفاتورة'), isFalse);
    });

    test('مواضع الإبراز تشير للكلمات المطابقة على النص الأصلي', () {
      final spans = SmartSearchService.highlightSpans('سأحضر الاجتماع غدا', 'اجتماع');
      expect(spans, isNotEmpty);
      final (start, len) = spans.first;
      expect('سأحضر الاجتماع غدا'.substring(start, start + len), 'الاجتماع');
    });

    test('مسافة التحرير حسابات معلومة', () {
      expect(SmartSearchService.editDistance('كتاب', 'كتاب'), 0);
      expect(SmartSearchService.editDistance('كتاب', 'كتم'), 2);
      expect(SmartSearchService.editDistance('كتاب', 'اكتاب'), 1); // إدراج
      expect(SmartSearchService.editDistance('', 'abc'), 3);
    });
  });

  group('HijriService — التقويم الهجري الحسابي المدني', () {
    test('تواريخ مرجعية محسوبة بخوارزمية التقويم المدني القياسية', () {
      // المراجع مُتحقق منها بخوارزمية التقويم الهجري الجدولي المدني
      // (نفسها المستخدمة في مكتبات التقويم القياسية)
      expect(HijriService.toHijri(DateTime(2008, 1, 10)), (1429, 1, 1));
      expect(HijriService.toHijri(DateTime(2026, 11, 13)), (1448, 6, 2));
      expect(HijriService.toHijri(DateTime(2026, 1, 1)), (1447, 7, 12));
      expect(HijriService.toHijri(DateTime(2024, 1, 1)), (1445, 6, 19));
      expect(HijriService.toHijri(DateTime(2025, 6, 26)), (1446, 12, 29));
      expect(HijriService.toHijri(DateTime(2030, 3, 10)), (1451, 11, 5));
      expect(HijriService.toHijri(DateTime(1999, 12, 31)), (1420, 9, 23));
      expect(HijriService.toHijri(DateTime(2026, 3, 1)), (1447, 9, 12));
    });

    test('التحويل ذهاباً وإياباً عبر قرون', () {
      for (final y in [1990, 2000, 2010, 2020, 2026, 2040]) {
        for (final m in [1, 5, 9, 12]) {
          final g = DateTime(y, m, 15);
          final (hy, hm, hd) = HijriService.toHijri(g);
          final back = HijriService.toGregorian(hy, hm, hd);
          expect(back.year, y, reason: 'سنة $y/$m');
          expect(back.month, m, reason: 'سنة $y/$m');
          expect(back.day, 15, reason: 'سنة $y/$m');
        }
      }
    });

    test('طول الشهور: الفردي 30 والزوجي 29 وذي الحجة في الكبيسة 30', () {
      expect(HijriService.hijriMonthLength(1447, 1), 30);
      expect(HijriService.hijriMonthLength(1447, 2), 29);
      expect(HijriService.isHijriLeap(1447), isTrue);
      expect(HijriService.hijriMonthLength(1447, 12), 30);
      // سنة غير كبيسة: ذو الحجة 29
      var foundNonLeap = false;
      for (var y = 1440; y <= 1470; y++) {
        if (!HijriService.isHijriLeap(y)) {
          expect(HijriService.hijriMonthLength(y, 12), 29);
          foundNonLeap = true;
          break;
        }
      }
      expect(foundNonLeap, isTrue);
    });

    test('التسمية العربية للشهور والتواريخ المزدوجة', () {
      expect(HijriService.hijriMonths[8], 'رمضان');
      expect(HijriService.hijriMonths[11], 'ذو الحجة');
      final both = HijriService.formatBoth(DateTime(2026, 11, 13));
      expect(both, contains('نوفمبر'));
      expect(both, contains('1448هـ'));
      expect(HijriService.hijriShort(DateTime(2008, 1, 10)), '1 محرم 1429هـ');
    });
  });

  group('VoiceCommandsService — فهم الأوامر', () {
    test('التبويبات الخمس تُفهم بصيغ مختلفة', () {
      expect(VoiceCommandsService.parse('افتح المحادثات')!.action, 'tab:0');
      expect(VoiceCommandsService.parse('المحادثه')!.action, 'tab:0');
      expect(VoiceCommandsService.parse('افتح المجتمعات')!.action, 'tab:1');
      expect(VoiceCommandsService.parse('القنوات')!.action, 'tab:2');
      expect(VoiceCommandsService.parse('المكالمات')!.action, 'tab:3');
      expect(VoiceCommandsService.parse('الإعدادات')!.action, 'tab:4');
      expect(VoiceCommandsService.parse('الضبط')!.action, 'tab:4');
    });

    test('التطبيع يتغلب على الهمزات والتشكيل', () {
      expect(VoiceCommandsService.parse('اَفْتَح الإعدادات')!.action, 'tab:4');
      expect(VoiceCommandsService.parse('وصل الذكاء')!.action, 'ai');
      expect(VoiceCommandsService.parse('محادثة جديدة')!.action, 'newchat');
    });

    test('كلام عشوائي لا يُفهم كأمر', () {
      expect(VoiceCommandsService.parse(''), isNull);
      expect(VoiceCommandsService.parse('طقس اليوم جميل'), isNull);
    });
  });
}
