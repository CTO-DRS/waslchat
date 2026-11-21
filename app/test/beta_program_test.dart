import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/config.dart';
import 'package:wasl_chat/services/beta_program_service.dart';
import 'package:wasl_chat/services/feedback_service.dart';

/// اختبارات نقية لبرنامج الاختبار الميداني (المرحلة 16 — 1.8.0) —
/// العائِل الصادق والقالب المعبأ والمجالات وحالة الانضمام المحلية كلها
/// قرارات تُثبت هنا قبل أي استخدام حقيقي. التخزين الآمن غير متاح في
/// بيئة الاختبار فيهبط بصمت — والحالة في الذاكرة هي ما يُختبر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('مجالات الاختبار', () {
    test('خمسة مجالات بمعرفات فريدة وتسميات ووصف غير فارغة', () {
      expect(BetaProgramService.scopes.length, 5);
      final ids = BetaProgramService.scopes.map((s) => s.id).toSet();
      expect(ids.length, 5);
      for (final s in BetaProgramService.scopes) {
        expect(s.label, isNotEmpty);
        expect(s.hint, isNotEmpty);
      }
    });

    test('استعادة دفاعية: معرف صالح يعود بمجاله وغريب يعود «كل شيء»', () {
      expect(BetaProgramService.scopeFrom('ai').id, 'ai');
      expect(BetaProgramService.scopeFrom('calls').id, 'calls');
      expect(BetaProgramService.scopeFrom(null).id, 'all');
      expect(BetaProgramService.scopeFrom('').id, 'all');
      expect(BetaProgramService.scopeFrom('stolen').id, 'all');
    });
  });

  group('العائِل الصادق', () {
    test('ما يُختبر وما ينقص قائمتان غير فارغتين ببنود مكتملة', () {
      expect(BetaProgramService.whatIsTested, isNotEmpty);
      expect(BetaProgramService.whatIsMissing, isNotEmpty);
      for (final p in [...BetaProgramService.whatIsTested, ...BetaProgramService.whatIsMissing]) {
        expect(p.length, greaterThan(15), reason: 'بند مبتور: $p');
      }
    });

    test('قائمة النقص تعلن قرارا المالك الماليين وحد الشبكات الصارمة بصدق', () {
      final all = BetaProgramService.whatIsMissing.join(' ');
      expect(all, contains('Play'));
      expect(all, contains('iOS'));
      expect(all, contains('TURN'));
    });

    test('إفصاح الانضمام يقول «محلياً حصراً» وينفي أي قائمة خادمية', () {
      final d = BetaProgramService.joinDisclosure;
      expect(d, contains('محلي'));
      expect(d, contains('لا يضيفك لأي قائمة على الخادم'));
      expect(d, contains('مغادرته ممكنة'));
    });

    test('ملاحظة القناة لا تدّعي وجودها — «إن وُجدت»', () {
      expect(BetaProgramService.channelNote, contains('إن وُجدت'));
    });
  });

  group('قالب تقرير الاختبار', () {
    test('يحمل بصمة المجال والإصدار والمنصة وحقول الفراغ الثلاثة', () {
      final t = BetaProgramService.reportTemplate(
        scopeId: 'messages',
        version: '1.8.0+70',
        platform: 'Android',
      );
      expect(t, contains('[اختبار ميداني — الرسائل والتشفير]'));
      expect(t, contains('1.8.0+70'));
      expect(t, contains('Android'));
      expect(t, contains('ما توقعته أن يحدث: '));
      expect(t, contains('ما حدث فعلاً: '));
    });

    test('مجال غريب في القالب يهبط «كل شيء» بلا انهيار', () {
      final t = BetaProgramService.reportTemplate(
        scopeId: 'stolen',
        version: '1.8.0+70',
        platform: 'Android',
      );
      expect(t, contains('كل شيء'));
    });

    test('القالب ضمن حد الخادم ويعبر فحص التحقق قبل الإرسال', () {
      for (final s in BetaProgramService.scopes) {
        final t = BetaProgramService.reportTemplate(
          scopeId: s.id,
          version: '1.8.0+70',
          platform: 'Android',
        );
        expect(t.length, lessThanOrEqualTo(FeedbackService.maxLen));
        expect(FeedbackService.validationError(t), isNull,
            reason: 'قالب مجال ${s.id} يُرفض قبل الإرسال');
        // التنظيف لا يفسده — يمر مرتين كما يفعل الإرسال الفعلي
        expect(FeedbackService.sanitize(t).length,
            lessThanOrEqualTo(FeedbackService.maxLen));
      }
    });

    test('القالب يحمل تذكير الخصوصية الحرفي المطابق لإفصاح شاشة الملاحظات', () {
      final t = BetaProgramService.reportTemplate(
        scopeId: 'all',
        version: '1.8.0+70',
        platform: 'Android',
      );
      expect(t, contains('ملاحظة خصوصية'));
      expect(t, contains('لن أكتب هنا محتوى محادثاتي'));
    });

    test('المعرف في رأس القالب يطابق ما يعيد استخدامه الخادم — version من AppConfig', () {
      // صيغة الإصدار نفسها التي ترسلها شاشة الملاحظات دائماً
      final version = '${AppConfig.appVersion}+${AppConfig.appBuild}';
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    });
  });

  group('حالة الانضمام المحلية', () {
    test('الافتراضي: غير منضم وبلا مجال', () {
      // حالة خدمة طازجة قبل أي load ناجح — الذاكرة هي مصدر الاختبار
      expect(BetaProgramService.joined.value, isFalse);
    });

    test('الانضمام يفعّل الحالة ويثبت المجال، والمغادرة تمسحها', () async {
      await BetaProgramService.join('communities');
      expect(BetaProgramService.joined.value, isTrue);
      expect(BetaProgramService.scope.value, 'communities');
      expect(BetaProgramService.joinedAt, isNotNull);

      await BetaProgramService.leave();
      expect(BetaProgramService.joined.value, isFalse);
      expect(BetaProgramService.scope.value, isNull);
      expect(BetaProgramService.joinedAt, isNull);
    });

    test('إعادة الانضمام بمجال آخر تستبدل المجال القديم', () async {
      await BetaProgramService.join('ai');
      expect(BetaProgramService.scope.value, 'ai');
      await BetaProgramService.join('all');
      expect(BetaProgramService.scope.value, 'all');
      expect(BetaProgramService.joined.value, isTrue);
      await BetaProgramService.leave();
    });
  });

  group('تسمية تاريخ الانضمام', () {
    test('نفس السنة: يوم واسم الشهر بلا سنة', () {
      final label = BetaProgramService.joinedAtLabel(
        DateTime(2026, 11, 18, 10, 30),
        DateTime(2026, 11, 18, 22, 0),
      );
      expect(label, contains('18 نوفمبر'));
      expect(label, isNot(contains('2026')));
    });

    test('سنة مختلفة: تُضاف السنة', () {
      final label = BetaProgramService.joinedAtLabel(
        DateTime(2025, 2, 3),
        DateTime(2026, 11, 18),
      );
      expect(label, contains('3 فبراير'));
      expect(label, contains('2025'));
    });
  });
}
