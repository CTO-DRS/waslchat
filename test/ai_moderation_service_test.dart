import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/ai_moderation_service.dart';

/// اختبارات نقية لمساعد الإشراف الذكي — بلا شبكة ولا قاعدة بيانات.
/// الفرض من الخادم (ترحيل 027): الملاحظات لمشرفي المجتمعات العامة فقط،
/// والمساعد يقترح ولا ينفذ؛ هنا نتحقق من المحلّل الدفاعي لرد Gemini
/// والتسميات والأيقونات التي تعرضها شاشة الإشراف.
void main() {
  group('AiModerationService — تحليل رد Gemini دفاعياً', () {
    test('مصفوفة JSON سليمة تعيد الخريطة بالفئة والدرجة والسبب', () {
      final raw = [
        {'message_id': 'm1', 'category': 'scam', 'severity': 'high', 'reason': 'وعود مال'},
        {'message_id': 'm2', 'category': 'abuse', 'severity': 'low', 'reason': 'سبّ'},
      ];
      final out = AiModerationService.parseVerdicts(raw);
      expect(out.length, 2);
      expect(out['m1']!.$1, 'scam');
      expect(out['m1']!.$2, 'high');
      expect(out['m1']!.$3, 'وعود مال');
      expect(out['m2']!.$1, 'abuse');
      expect(out['m2']!.$2, 'low');
    });

    test('نص بأسوار كود json يُفكَّ ويُستخرج الملجأ الأول', () {
      const fenced = '```json\n'
          '[{"message_id":"m1","category":"spam","severity":"low","reason":"تكرار"}]\n'
          '```';
      final out = AiModerationService.parseVerdicts(fenced);
      expect(out.length, 1);
      expect(out['m1']!.$1, 'spam');
      expect(out['m1']!.$2, 'low');
    });

    test('نص فيه كلام قبل المصفوفة وبعدها يستخرج الملجأ بين أول [ وآخر ]', () {
      const noisy = 'هذه ملاحظاتي:\n[{"message_id":"m9","category":"danger","severity":"high"}] شكراً';
      final out = AiModerationService.parseVerdicts(noisy);
      expect(out.length, 1);
      expect(out['m9']!.$1, 'danger');
      // الدرجة الموجودة تُقرأ كما هي (المفقودة وحدها تسقط لـlow)
      expect(out['m9']!.$2, 'high');
    });

    test('الفئات المجهولة والعناصر الناقصة تُهمل ولا تكسر التحليل', () {
      final raw = [
        {'message_id': 'm1', 'category': 'offtopic', 'severity': 'high'}, // فئة مجهولة
        {'category': 'spam', 'severity': 'low'}, // بلا معرّف
        {'message_id': 'm2'}, // بلا فئة
        'نص ليس خريطة', // عنصر غريب
        {'message_id': 'm3', 'category': 'nsfw', 'severity': 'weird'}, // درجة غريبة → low
      ];
      final out = AiModerationService.parseVerdicts(raw);
      expect(out.keys, {'m3'});
      expect(out['m3']!.$1, 'nsfw');
      expect(out['m3']!.$2, 'low');
    });

    test('النص الغريب كله يعيد خريطة فارغة بلا استثناء', () {
      expect(AiModerationService.parseVerdicts(''), isEmpty);
      expect(AiModerationService.parseVerdicts('لا شيء'), isEmpty);
      expect(AiModerationService.parseVerdicts('[{كسر'), isEmpty);
      expect(AiModerationService.parseVerdicts(42), isEmpty);
      expect(AiModerationService.parseVerdicts(null), isEmpty);
      expect(AiModerationService.parseVerdicts({'message_id': 'x'}), isEmpty);
    });

    test('سقف الملاحظات 40 يحترم والتكرار بالمعرّف يستبدل لا يكرر', () {
      final many = List.generate(60, (i) => {
            'message_id': 'm$i',
            'category': 'spam',
            'severity': 'low',
          });
      final out = AiModerationService.parseVerdicts(many);
      expect(out.length, AiModerationService.flagsLimit);
      expect(AiModerationService.flagsLimit, 40);

      final dup = [
        {'message_id': 'm1', 'category': 'spam', 'severity': 'low'},
        {'message_id': 'm1', 'category': 'scam', 'severity': 'high', 'reason': 'الأخير يفوز'},
      ];
      final outDup = AiModerationService.parseVerdicts(dup);
      expect(outDup.length, 1);
      expect(outDup['m1']!.$1, 'scam');
      expect(outDup['m1']!.$3, 'الأخير يفوز');
    });

    test('السبب الطويل يقص عند 300 حرف', () {
      final raw = [
        {'message_id': 'm1', 'category': 'spam', 'reason': 'س' * 500},
      ];
      final out = AiModerationService.parseVerdicts(raw);
      expect(out['m1']!.$3.length, 300);
    });
  });

  group('AiModerationService — الفئات والتسميات والأيقونات', () {
    test('الفئات الخمس مطابقة لقيد الخادم في ترحيل 027', () {
      expect(AiModerationService.categories,
          ['spam', 'abuse', 'scam', 'nsfw', 'danger']);
      expect(AiModerationService.scanLimit, 120);
    });

    test('لكل فئة تسمية وأيقونة ولون محددان', () {
      for (final c in AiModerationService.categories) {
        expect(AiModerationService.categoryLabel(c), isNotEmpty);
        expect(AiModerationService.categoryIcon(c), isNotNull);
        expect(AiModerationService.categoryColor(c), isNotNull);
      }
      expect(AiModerationService.categoryLabel('spam'), 'إزعاج ودعاية');
      expect(AiModerationService.categoryLabel('abuse'), 'إساءة وتشهير');
      expect(AiModerationService.categoryLabel('scam'), 'احتيال وتصيّد');
      expect(AiModerationService.categoryLabel('nsfw'), 'محتوى حساس');
      expect(AiModerationService.categoryLabel('danger'), 'تهديد وتحريض');
      // فئة مجهولة تسقط لافتراضي آمن لا يكسر الواجهة
      expect(AiModerationService.categoryLabel('x'), 'ملاحظة');
    });

    test('تسميات الخطورة وإجراءات المعالجة بالمفرّد والمجهول', () {
      expect(AiModerationService.severityLabel('high'), 'خطورة عالية');
      expect(AiModerationService.severityLabel('low'), 'خطورة منخفضة');
      expect(AiModerationService.severityLabel('weird'), 'خطورة منخفضة');
      expect(AiModerationService.resolvedActionLabel('ignored'), 'جُهلت');
      expect(AiModerationService.resolvedActionLabel('muted'), 'عقبها كتم المرسل');
      expect(AiModerationService.resolvedActionLabel('kicked'), 'عقبها طرد المرسل');
      expect(AiModerationService.resolvedActionLabel('deleted'), 'عقبها حذف الرسالة');
      expect(AiModerationService.resolvedActionLabel('warned'), 'عقبها إنذار المرسل');
      expect(AiModerationService.resolvedActionLabel('weird'), 'مُعالَجة');
      expect(AiModerationService.resolvedActionLabel(null), 'مُعالَجة');
    });
  });
}
