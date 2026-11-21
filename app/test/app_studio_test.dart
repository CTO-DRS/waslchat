/// استوديو التطبيق واستوديو المحادثة وشاشة القفل و«وصول» (1.13.0)
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/app_icon_service.dart';
import 'package:wasl_chat/services/app_lock_service.dart';
import 'package:wasl_chat/services/app_studio_service.dart';
import 'package:wasl_chat/services/contrast_service.dart';
import 'package:wasl_chat/theme.dart';
import 'package:wasl_chat/widgets/lock_gate.dart';
import 'package:wasl_chat/widgets/studio_backdrop.dart';
import 'package:wasl_chat/widgets/wasl_mascot.dart';

void main() {
  group('StudioStyle', () {
    test('الافتراضي يطابق ألوان وصل الحالية حرفياً', () {
      const d = StudioStyle.defaults;
      expect(d.accentColor, WaslColors.indigo);
      expect(d.accent2Color, WaslColors.teal);
      expect(d.gradient, WaslColors.brandGradient);
      expect(d.backdrop, StudioBackdrop.plain);
      expect(d.roundness.factor, 1.0);
      expect(d.bubbleShape.radius, 20);
      expect(d.bannerSeconds, 4);
      expect(d.isDefault, isTrue);
    });

    test('تدرج الهوية الحالي = الأصلي عند الافتراضي', () {
      AppStudioService.style.value = StudioStyle.defaults;
      expect(WaslColors.gradient, WaslColors.brandGradient);
    });

    test('ذهاب وإياب JSON بلا فقد لكل السمات الجاهزة وأنماط عشوائية', () {
      for (final t in StudioCatalog.themes) {
        expect(StudioStyle.decode(t.style.encode()), t.style);
      }
      final custom = StudioStyle.defaults.copyWith(
        accent: 0xFFDC2626,
        backdrop: StudioBackdrop.stars,
        nav: StudioNav.minimal,
        navLabels: false,
        ownBubble: () => 0xFF16A34A,
        otherBubble: () => 0xFFEC4899,
        banner: StudioBanner.toast,
        bannerPreview: false,
        lockStyle: StudioLock.night,
        lockOn: false,
        autoDayNight: true,
      );
      final back = StudioStyle.decode(custom.encode());
      expect(back, custom);
      expect(back.ownBubble, 0xFF16A34A);
      expect(back.lockStyle, StudioLock.night);
    });

    test('القراءة المتسامحة: نص تالف أو حقول مجهولة تعود للافتراضي', () {
      expect(StudioStyle.decode('not json'), StudioStyle.defaults);
      expect(StudioStyle.decode(null), StudioStyle.defaults);
      final s = StudioStyle.decode('{"backdrop":"???","bannerSeconds":99,"nav":"classic"}');
      expect(s.backdrop, StudioBackdrop.plain);
      expect(s.bannerSeconds, 10);
      expect(s.nav, StudioNav.classic);
    });

    test('≥10 لوحات و≥8 سمات جاهزة و≥8 خلفيات و≥4 أشكال قفل', () {
      expect(StudioCatalog.palettes.length, greaterThanOrEqualTo(10));
      expect(StudioCatalog.themes.length, greaterThanOrEqualTo(8));
      expect(StudioBackdrop.values.length, greaterThanOrEqualTo(8));
      expect(StudioLock.values.length, greaterThanOrEqualTo(4));
      final names = StudioCatalog.themes.map((t) => t.name).toSet();
      for (final n in ['ليل وصل', 'فجر', 'صحراء', 'محيط', 'زمرد', 'وردي', 'كلاسيكي', 'عالي التباين']) {
        expect(names, contains(n));
      }
    });

    test('النص الأبيض مقروء على كل لون أساسي وكل لون فقاعة (≥3:1)', () {
      for (final p in StudioCatalog.palettes) {
        expect(ContrastService.ratio(Colors.white, Color(p.accent)), greaterThanOrEqualTo(3.0),
            reason: p.name);
      }
      for (final c in StudioCatalog.swatches) {
        expect(ContrastService.ratio(Colors.white, Color(c)), greaterThanOrEqualTo(3.0),
            reason: c.toRadixString(16));
      }
    });

    test('صبغة فقاعة الآخرين تحافظ على تباين النص في الوضعين', () {
      for (final c in StudioCatalog.otherTints) {
        final look = BubbleLook.resolve(StudioStyle.defaults.copyWith(otherBubble: () => c), null);
        final darkBg = look.otherColor(WaslColors.darkSurface);
        final lightBg = look.otherColor(WaslColors.lightBubble);
        expect(ContrastService.ratio(Colors.white, darkBg), greaterThanOrEqualTo(4.5));
        expect(ContrastService.ratio(WaslColors.ink, lightBg), greaterThanOrEqualTo(4.5));
      }
    });

    test('تطبيق سمة يحفظ إعدادات القفل والاهتزاز الشخصية', () {
      final mine = StudioStyle.defaults.copyWith(lockOn: false, haptics: false);
      final t = StudioCatalog.themeById('ocean')!;
      final applied = AppStudioService.keepPersonal(t.style, mine);
      expect(applied.lockOn, isFalse);
      expect(applied.haptics, isFalse);
      expect(applied.accent, t.style.accent);
    });

    test('تلقائي حسب الوقت: فاتح نهاراً وداكن ليلاً', () {
      final s = StudioStyle.defaults.copyWith(autoDayNight: true);
      expect(AppStudioService.effectiveMode(ThemeMode.dark, s, DateTime(2026, 1, 1, 9)),
          ThemeMode.light);
      expect(AppStudioService.effectiveMode(ThemeMode.light, s, DateTime(2026, 1, 1, 22)),
          ThemeMode.dark);
      expect(AppStudioService.effectiveMode(ThemeMode.system, StudioStyle.defaults,
          DateTime(2026, 1, 1, 9)), ThemeMode.system);
    });
  });

  group('الثيم', () {
    test('الافتراضي يبني الثيم السابق نفسه', () {
      final d = WaslTheme.dark;
      expect(d.scaffoldBackgroundColor, WaslColors.darkBg);
      expect(d.appBarTheme.backgroundColor, Colors.transparent);
      expect(d.pageTransitionsTheme, isA<StudioPageTransitions>());
      final l = WaslTheme.light;
      expect(l.scaffoldBackgroundColor, const Color(0xFFF2F4FA));
    });

    test('ThemeData يُبنى لكل سمة ولكل خيار بلا أخطاء', () {
      final styles = <StudioStyle>[
        for (final t in StudioCatalog.themes) t.style,
        for (final b in StudioBackdrop.values) StudioStyle.defaults.copyWith(backdrop: b),
        for (final a in StudioAppBar.values) StudioStyle.defaults.copyWith(appBar: a),
        for (final s in StudioSurface.values) StudioStyle.defaults.copyWith(surface: s),
        for (final d in StudioDensity.values) StudioStyle.defaults.copyWith(density: d),
        for (final m in StudioMotion.values) StudioStyle.defaults.copyWith(motion: m),
      ];
      for (final s in styles) {
        for (final b in Brightness.values) {
          final t = WaslTheme.build(b, s);
          expect(t.brightness, b);
        }
      }
    });

    test('الخلفية المرسومة تجعل الصفحات شفافة وتلفّها بالانتقال', () {
      final t = WaslTheme.build(
          Brightness.dark, StudioStyle.defaults.copyWith(backdrop: StudioBackdrop.aurora));
      expect(t.scaffoldBackgroundColor, Colors.transparent);
      expect(t.pageTransitionsTheme, isA<StudioPageTransitions>());
      expect((t.pageTransitionsTheme as StudioPageTransitions).wrap, isTrue);
    });
  });

  group('استوديو المحادثة', () {
    test('الفقاعات تتبع التطبيق ما لم تُخصَّص المحادثة', () {
      final g = StudioStyle.defaults.copyWith(bubbleShape: StudioBubbleShape.sharp);
      final plain = BubbleLook.resolve(g, ChatStyle.empty);
      expect(plain.radius, 8);
      expect(plain.gradient, g.gradient);
      const c = ChatStyle(ownBubble: 0xFFDC2626, bubbleFill: StudioBubbleFill.solid,
          bubbleShape: StudioBubbleShape.round);
      final over = BubbleLook.resolve(g, c);
      expect(over.radius, 20);
      expect(over.gradient, isNull);
      expect(over.ownColor, const Color(0xFFDC2626));
    });

    test('ذهاب وإياب JSON لتخصيص المحادثة وفارغه', () {
      const c = ChatStyle(wallpaper: 3, ownBubble: 0xFF059669, fontScale: 1.15,
          bubbleShape: StudioBubbleShape.soft);
      expect(ChatStyle.decode(c.encode()), c);
      expect(ChatStyle.decode('{}').isEmpty, isTrue);
      expect(ChatStyle.decode('bad').isEmpty, isTrue);
    });

    test('مستمع المحادثة يعيد القيمة المحقونة', () {
      ChatStudioService.debugPut('c1', const ChatStyle(wallpaper: 2));
      expect(ChatStudioService.of('c1').value.wallpaper, 2);
    });

    test('الذيل يغيّر زاوية جهة المرسل فقط', () {
      final look = BubbleLook.resolve(StudioStyle.defaults.copyWith(bubbleTail: true), null);
      final mine = look.borderRadius(mine: true) as BorderRadiusDirectional;
      expect(mine.bottomEnd.x, 4);
      expect(mine.bottomStart.x, 20);
    });
  });

  group('شاشة القفل', () {
    test('العودة: المؤمّن يقفل دائماً، والسحب بعد 30 ثانية فقط', () {
      bool f({bool signedIn = true, bool secure = false, bool lockOn = true, int s = 0}) =>
          LockGate.shouldLockOnResume(
              signedIn: signedIn, secure: secure, lockOn: lockOn, away: Duration(seconds: s));
      expect(f(s: 10), isFalse);
      expect(f(s: 31), isTrue);
      expect(f(s: 120, lockOn: false), isFalse);
      expect(f(secure: true, s: 5, lockOn: false), isTrue);
      expect(f(signedIn: false, secure: true, s: 100), isFalse);
    });

    test('التحية حسب الوقت وتلميح غير المقروء بلا محتوى', () {
      expect(lockGreeting(8), 'صباح الخير');
      expect(lockGreeting(14), 'نهارك سعيد');
      expect(lockGreeting(19), 'مساء الخير');
      expect(lockGreeting(2), 'طابت ليلتك');
      expect(unreadHint(0), contains('هادئ'));
      expect(unreadHint(2), contains('رسالتان'));
      expect(unreadHint(5), contains('5'));
    });

    test('رمز PIN: صيغة صالحة وتحقق مملَّح', () async {
      expect(AppLockService.validPin('1234'), isTrue);
      expect(AppLockService.validPin('12a4'), isFalse);
      expect(AppLockService.validPin('123'), isFalse);
      final salt = List<int>.generate(16, (i) => i);
      final h = await AppLockService.hashPin('2468', salt);
      final raw = '${base64Encode(salt)}:$h';
      expect(await AppLockService.verifyStored(raw, '2468'), isTrue);
      expect(await AppLockService.verifyStored(raw, '2469'), isFalse);
      expect(h, isNot(contains('2468')));
    });
  });

  group('الأيقونة و«وصول»', () {
    test('≥5 أيقونات بمعرّفات وألقاب فريدة', () {
      final v = AppIconService.variants;
      expect(v.length, greaterThanOrEqualTo(5));
      expect(v.map((e) => e.id).toSet().length, v.length);
      expect(v.map((e) => e.alias).toSet().length, v.length);
      expect(AppIconService.byId('nope').id, AppIconService.classic);
    });

    test('رسم «وصول» بكل الأمزجة والخلفيات بلا أخطاء', () {
      for (final m in MascotMood.values) {
        for (final still in [true, false]) {
          final rec = ui.PictureRecorder();
          MascotPainter(mood: m, time: 0.37, blink: 0.5, tap: 0.4, still: still,
                  gaze: const Offset(0.5, -0.3))
              .paint(Canvas(rec), const Size(160, 160));
          rec.endRecording();
        }
      }
      for (final b in StudioBackdrop.values) {
        for (final dark in [true, false]) {
          final rec = ui.PictureRecorder();
          StudioBackdropPainter(
                  kind: b, accent: WaslColors.indigo, accent2: WaslColors.teal, dark: dark)
              .paint(Canvas(rec), const Size(300, 600));
          rec.endRecording();
        }
      }
    });
  });
}
