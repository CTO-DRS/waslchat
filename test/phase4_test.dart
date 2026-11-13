import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/bot_service.dart';
import 'package:wasl_chat/services/channel_stats_service.dart';
import 'package:wasl_chat/services/saved_service.dart';
import 'package:wasl_chat/services/username_service.dart';

/// اختبارات وحدة للدوال النقية في ميزات المرحلة 4 (0.13.0):
/// اسم المستخدم، البوتات، مشاهدات القنوات، وسحابة «المحفوظة»
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UsernameService — صيغة اسم المستخدم وتطبيعها وروابطها', () {
    test('الحدود بالطول بعد التطبيع (الأحرف غير الصالحة تُطبّع تلقائياً)', () {
      expect(UsernameService.validationError('ahmed_2026'), isNull);
      expect(UsernameService.validationError('user'), isNull);
      expect(UsernameService.validationError('ab'), isNotNull); // أقصر من 4
      expect(UsernameService.validationError(''), isNotNull);
      expect(UsernameService.validationError('ا'), isNotNull); // تطبيعها ___ قصير
      expect(UsernameService.validationError('a' * 25), isNotNull); // أطول من 24
      expect(UsernameService.validationError('a' * 24), isNull);
    });

    test('التطبيع يصلح الأحرف الكبيرة والمسافات والرموز كما يفعل الخادم', () {
      expect(UsernameService.normalize('  Ahmed.Doe@X  '), 'ahmed_doe_x');
      expect(UsernameService.normalize('@user'), 'user');
      // «أحمد» = 4 أحرف، والخادم يستبدل كل حرف غير مسموح بشرطة سفلية واحدة (regexp_replace)
      expect(UsernameService.normalize('أحمد'), '____');
      // الصيغة الخام نفسها صارمة — التطبيع هو ما يجعلها مقبولة
      expect(UsernameService.format.hasMatch('Ahmed_1'), isFalse);
      expect(UsernameService.format.hasMatch('ahmed_1'), isTrue);
      expect(UsernameService.format.hasMatch('has space'), isFalse);
    });

    test('إزالة @ من البداية فقط', () {
      expect(UsernameService.stripAt('@name'), 'name');
      expect(UsernameService.stripAt('name'), 'name');
      expect(UsernameService.stripAt('a@b'), 'a@b');
    });

    test('الروابط العامة تُبنى وتُقرأ', () {
      expect(UsernameService.profileLink('ahmed'),
          'https://waslchat.app/@ahmed');
      expect(UsernameService.parseFromInput('ahmed_1'), 'ahmed_1');
      expect(UsernameService.parseFromInput('@ahmed_1'), 'ahmed_1');
      expect(
          UsernameService.parseFromInput('https://waslchat.app/@ahmed_1'),
          'ahmed_1');
      expect(UsernameService.parseFromInput('https://evil.com/@ahmed_1'),
          isNull);
      expect(UsernameService.parseFromInput('!!'), isNull);
      expect(UsernameService.parseFromInput(''), isNull);
    });

    test('أخطاء الخادم تترجم عربياً', () {
      expect(UsernameService.errorLabel('username taken'), contains('محجوز'));
      expect(
          UsernameService.errorLabel('username cooldown'), contains('24 ساعة'));
      expect(
          UsernameService.errorLabel('bad username format'), contains('صيغة'));
    });
  });

  group('BotService — أسماء البوتات والرموز وروابط الويب هوك', () {
    test('الأسماء يجب أن تنتهي بـ_bot ضمن الحدود', () {
      expect(BotService.usernameError('helper_bot'), isNull);
      expect(BotService.usernameError('a1_b_bot'), isNull);
      expect(BotService.usernameError('helper'), contains('_bot'));
      expect(BotService.usernameError('_bot'), isNotNull);
      expect(BotService.usernameError('helper_bot_extra_toolong_name'), isNotNull);
      // الخادم (bot_create) يطبّع الحالة قبل الفحص فتُقبل — والمسافات تبقى فتُرفض
      expect(BotService.usernameError('Helper_Bot'), isNull);
      expect(BotService.usernameError('has space_bot'), isNotNull);
    });

    test('التطبيع يحافظ على اللاحقة', () {
      expect(BotService.normalizeUsername(' Store_Bot '), 'store_bot');
      expect(BotService.normalizeUsername('@pay_bot'), 'pay_bot');
    });

    test('رمز الواجهة بصيغته الدقيقة', () {
      expect(
          BotService.isValidToken(
              'wasl_${'a' * 48}'),
          isTrue);
      expect(BotService.isValidToken('sk_live_abc'), isFalse);
      expect(BotService.isValidToken('wasl_short'), isFalse);
      expect(BotService.isValidToken(''), isFalse);
    });

    test('روابط الويب هوك: فارغ مسموح وغيره http/https فقط', () {
      expect(BotService.webhookError(''), isNull);
      expect(BotService.webhookError('   '), isNull);
      expect(
          BotService.webhookError('https://example.com/wasl'), isNull);
      expect(BotService.webhookError('http://10.0.0.1/hook'), isNull);
      expect(BotService.webhookError('ftp://x'), isNotNull);
      expect(BotService.webhookError('example.com'), isNotNull);
      expect(BotService.webhookError('https://x y.com'), isNotNull);
    });

    test('الحدود المعروضة للمستخدم ثابتة', () {
      expect(BotService.maxPerOwner, 10);
      expect(BotService.rateLimitPerMinute, 20);
    });

    test('أخطاء الخادم تترجم عربياً', () {
      expect(BotService.errorLabel('bot limit'), contains('10'));
      expect(BotService.errorLabel('username taken'), contains('محجوز'));
      expect(BotService.errorLabel('use bot_start_chat'), contains('المباشرة'));
      expect(BotService.errorLabel('admins only'), contains('مشرف'));
    });
  });

  group('ChannelStatsService — تنسيق العدّادات العربية', () {
    test('formatCount: أقل من ألف رقم صريح وما فوق تقريب مفيد', () {
      expect(ChannelStatsService.formatCount(0), '0');
      expect(ChannelStatsService.formatCount(7), '7');
      expect(ChannelStatsService.formatCount(999), '999');
      expect(ChannelStatsService.formatCount(1000), '1 ألف');
      expect(ChannelStatsService.formatCount(1260), '1.3 ألف');
      expect(ChannelStatsService.formatCount(999999), '1000 ألف');
      expect(ChannelStatsService.formatCount(1000000), '1 مليون');
      expect(ChannelStatsService.formatCount(2400000), '2.4 مليون');
      expect(ChannelStatsService.formatCount(-5), '0');
    });

    test('viewsLabel بجمع عربي سليم', () {
      expect(ChannelStatsService.viewsLabel(0), 'لا مشاهدات');
      expect(ChannelStatsService.viewsLabel(1), 'مشاهدة واحدة');
      expect(ChannelStatsService.viewsLabel(2), 'مشاهدتان');
      expect(ChannelStatsService.viewsLabel(10), '10 مشاهدات');
      expect(ChannelStatsService.viewsLabel(11), contains('مشاهدة'));
      expect(ChannelStatsService.viewsLabel(1000), '1 ألف مشاهدة');
    });

    test('averageLabel يعبر عن المتوسط بوضوح', () {
      expect(ChannelStatsService.averageLabel(0), contains('لا مشاهدات'));
      expect(ChannelStatsService.averageLabel(2), contains('مشاهدتان'));
      expect(ChannelStatsService.averageLabel(3.5), contains('متوسط'));
    });
  });

  group('SavedService — سحابة «رسائلي المحفوظة»', () {
    test('معاينة أنواع الوسائط برموزها والفراغ بسطر الدعوة', () async {
      // previewLine غير متزامنة بطبيعتها (تفكّ نص المعاينة المشفر) —
      // مسارات null والوسائط تعيد فوراً بلا شبكة
      expect(await SavedService.previewLine(null), contains('احفظ'));
      expect(await SavedService.previewLine({'type': 'image', 'message': 'x'}),
          '📷 صورة');
      expect(await SavedService.previewLine({'type': 'voice', 'message': 'x'}),
          '🎤 رسالة صوتية');
      expect(await SavedService.previewLine({'type': 'video', 'message': 'x'}),
          '🎬 فيديو');
      expect(await SavedService.previewLine({'type': 'file', 'message': 'x'}),
          '📎 ملف');
      expect(await SavedService.previewLine({'type': 'text', 'message': 'مرحبا'}),
          'مرحبا'); // النص الصريح يمر كما هو بلا فك
    });

    test('عنوان السحابة ثابت', () {
      expect(SavedService.title, 'رسائلي المحفوظة');
    });
  });
}
