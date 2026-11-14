// اختبارات مساعد الصياغة بأسلوبك (المرحلة 9 ب — 0.23.0)
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/style_assist_service.dart';

void main() {
  group('تعلم البصمة', () {
    test('أقل من 5 ردود تعيد البصمة المحايدة (لا تعلم من عينة ناقصة)', () {
      final p = StyleAssistService.learn(['تمام', 'شكرا', 'اوكي']);
      expect(p.sampleCount, 0);
      expect(p.formality, 0.5);
    });

    test('ردود رسمية ترفع formality فوق 0.6', () {
      final p = StyleAssistService.learn([
        'من فضلك، تفضل بمراجعة الملف وتفضل بقبول الاحترام',
        'رجاءً أرسل لي التقرير من فضلك وشاكر لك تعاونك',
        'تحياتي لك، أرجو أن تجد الفقرة المطلوبة وفقكم الله',
        'ممتن جدا، نرجو منكم التفضل بالمتابعة رجاء',
        'عفوا، حضراتكم أكرم موضع الفائدة وشاكرين لكم',
        'تفضل بالاطلاع رجاء وتكرموا بقبول الشكر',
      ]);
      expect(p.formality, greaterThan(0.6));
      expect(p.sampleCount, 6);
    });

    test('ردود عامية تنزل formality تحت 0.4', () {
      final p = StyleAssistService.learn([
        'هههه يا عيني شلونك اليوم',
        'ابغى أشوفك بكرة ماشي؟',
        'وش صار عندك هسه خلاص لا تفكر',
        'زين كفو عليك ههه',
        'يلا نمشي عشان الوقت',
        'طيب كذا احسن حلو',
      ]);
      expect(p.formality, lessThan(0.4));
    });

    test('معدل الإيموجي يُحسب من الردود', () {
      final p = StyleAssistService.learn([
        'تمام 👍',
        'زين 🙂',
        'أوكي 🌹',
        'حلو 🤝',
        'خلاص ✅',
        'ماشي',
      ]);
      expect(p.emojiRate, closeTo(5 / 6, 1e-9));
    });

    test('البادئات المتكررة تظهر في topOpeners والواحدة لا تظهر', () {
      final p = StyleAssistService.learn([
        'صباح الخير، هل وصل الملف؟',
        'صباح الخير، تقرير اليوم جاهز',
        'صباح الخير، لا أستطيع الحضور اليوم',
        'أرسل لي الموقع',
        'أرسل لي الرقم عند الوقت',
        'أرسل لي النسخة الأخيرة رجاء',
      ]);
      expect(p.topOpeners, contains('صباح الخير'));
      expect(p.topOpeners, isNot(contains('أرسل لي')));
    });
  });

  group('اقتراح الصيغ', () {
    test('تعيد ثلاث صيغ بملصقات الرسمي والودي والموجز', () {
      final ds = StyleAssistService.drafts('أرسل لي الملف');
      expect(ds.length, 3);
      expect(ds.map((d) => d.label).toSet(), {'رسمي', 'ودي', 'موجز'});
    });

    test('الترتيب يتبع النبرة: رسمية أولى وعامية تجعل الودي أولاً', () {
      final formal = StyleProfile(formality: 0.9, avgWords: 12, emojiRate: 0, topOpeners: [], topClosers: [], sampleCount: 30);
      final casual = StyleProfile(formality: 0.1, avgWords: 8, emojiRate: 0.5, topOpeners: ['هلا والله'], topClosers: [], sampleCount: 30);
      expect(StyleAssistService.drafts('أرسل الملف', profile: formal).first.label, 'رسمي');
      expect(StyleAssistService.drafts('أرسل الملف', profile: casual).first.label, 'ودي');
    });

    test('الصيغة الودية تتضمن البادئة المتعلمة وإيموجياً عند معدل عالٍ', () {
      final p = StyleProfile(formality: 0.3, avgWords: 10, emojiRate: 0.6, topOpeners: ['هلا والله'], topClosers: [], sampleCount: 30);
      final d = StyleAssistService.drafts('نرتب الاجتماع', profile: p).firstWhere((d) => d.label == 'ودي');
      expect(d.text, contains('هلا والله'));
      expect(d.text, contains('🙂'));
    });

    test('الصيغة الرسمية تضيف التأطير المهذب', () {
      final d = StyleAssistService.drafts('أرسل التقرير').firstWhere((d) => d.label == 'رسمي');
      expect(d.text, contains('من فضلك'));
      expect(d.text, contains('أرسل التقرير'));
    });

    test('الصيغة الموجزة تقلم عند أول فاصلة وتقص الطويل', () {
      final d = StyleAssistService.drafts('أرسل الملف، وبعد ذلك سنراجع، ثم نغلق')
          .firstWhere((d) => d.label == 'موجز');
      expect(d.text, 'أرسل الملف');
      final long = 'ك' * 200;
      final d2 = StyleAssistService.drafts(long).firstWhere((d) => d.label == 'موجز');
      expect(d2.text.length, lessThanOrEqualTo(80));
    });

    test('التلميح الفارغ يعطي صيغ بداية عامة لا فراغات', () {
      final ds = StyleAssistService.drafts('');
      for (final d in ds) {
        expect(d.text.trim(), isNotEmpty);
      }
    });
  });

  group('الإفصاح', () {
    test('نص الإفصاح يذكر الجهاز وحد 200 رد وأنه ليس نموذج لغة', () {
      expect(StyleAssistService.disclosure, contains('جهازك'));
      expect(StyleAssistService.disclosure, contains('200'));
      expect(StyleAssistService.disclosure, contains('نموذج لغة'));
    });
  });
}
