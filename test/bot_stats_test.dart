import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/bot_service.dart';

/// اختبارات لوحة إحصاءات البوت النقية (المرحلة 12 ب — 0.29.0):
/// العمر بنص عربي صادق والويب هوك والمحادثات بالأعداد الحقيقية —
/// ما لا يمكن قراءته لا يُخترع له رقم (الإفصاح ثابت مكتوب).
void main() {
  final now = DateTime(2026, 11, 15);

  group('عمر البوت ageText', () {
    test('نصوص الأعمار القصيرة', () {
      expect(BotStatsView.ageText(now.toIso8601String(), now), 'اليوم');
      final d1 = now.subtract(const Duration(days: 1, hours: 2));
      expect(BotStatsView.ageText(d1.toIso8601String(), now), 'قبل يوم');
      final d5 = now.subtract(const Duration(days: 5));
      expect(BotStatsView.ageText(d5.toIso8601String(), now), 'قبل 5 أيام');
    });

    test('الأسابيع والأشهر والسنوات', () {
      final w1 = now.subtract(const Duration(days: 8));
      expect(BotStatsView.ageText(w1.toIso8601String(), now), 'قبل أسبوع');
      final w3 = now.subtract(const Duration(days: 21));
      expect(BotStatsView.ageText(w3.toIso8601String(), now), 'قبل 3 أسابيع');
      final m1 = now.subtract(const Duration(days: 35));
      expect(BotStatsView.ageText(m1.toIso8601String(), now), 'قبل شهر');
      final m4 = now.subtract(const Duration(days: 120));
      expect(BotStatsView.ageText(m4.toIso8601String(), now), 'قبل 4 أشهر');
      final y2 = now.subtract(const Duration(days: 800));
      expect(BotStatsView.ageText(y2.toIso8601String(), now), 'قبل 2 سنوات');
    });

    test('كل غرابة تهبط شرطة بلا انهيار — null وفارغ ونص فاسد', () {
      expect(BotStatsView.ageText(null, now), '—');
      expect(BotStatsView.ageText('', now), '—');
      expect(BotStatsView.ageText('not-a-date', now), '—');
    });
  });

  group('الويب هوك والمحادثات', () {
    test('سطر الويب هوك صادق بالحالتين', () {
      expect(
        BotStatsView.webhookLabel({'webhook_url': 'https://x.y/wasl'}),
        'موصول — تصله الرسائل موقّعة HMAC',
      );
      expect(
        BotStatsView.webhookLabel({'webhook_url': ''}),
        'غير موصول — الرسائل لا تُرسل لأي خادم',
      );
      expect(BotStatsView.webhookLabel({}),
          'غير موصول — الرسائل لا تُرسل لأي خادم');
    });

    test('سطر المحادثات بالأعداد الحقيقية', () {
      expect(BotStatsView.chatCountLabel(0), 'لا محادثات مرتبطة بعد');
      expect(BotStatsView.chatCountLabel(1), 'محادثة واحدة مرتبطة');
      expect(BotStatsView.chatCountLabel(4), '4 محادثات مرتبطة');
    });

    test('الإفصاح يعلن الصدق والإحصاءات المقاسة من 039 موثقة', () {
      expect(BotStatsView.disclosure, contains('بلا تخمين ولا أرقام مكتوظة'));
      expect(BotStatsView.disclosure, contains('ترحيل 039'));
      expect(BotStatsView.disclosure,
          contains('رموز ردود الويب هوك تفصلها بيئة بوتك نفسها'),
          reason: 'ردود الويب هوك لا تُقرأ من الخادم — الحد يعلن');
    });
  });
}
