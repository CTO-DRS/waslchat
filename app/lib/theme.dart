import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'services/app_studio_service.dart';
import 'widgets/studio_backdrop.dart';

class WaslColors {
  static const indigo = Color(0xFF6366F1);
  static const teal = Color(0xFF14B8A6);
  static const violet = Color(0xFFA855F7);
  static const darkBg = Color(0xFF0B0F1A);
  static const darkSurface = Color(0xFF151B2B);
  static const glass = Color(0x14FFFFFF);

  // لوحة الوضع الفاتح (0.7.1): ألوان محايدة باردة تحافظ على هوية النيلة/التركواز
  static const lightBg = Color(0xFFF2F4FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightGlass = Color(0x146366F1); // نيلة خفيفة تعمل على الفاتح
  static const ink = Color(0xFF1A2033); // نص أساسي على الفاتح
  static const ink2 = Color(0xFF5A6478); // نص ثانوي على الفاتح
  static const ink3 = Color(0xFF6B7590); // نص خافت على الفاتح — WCAG AA نص كبير ≥3:1 (صُدّل 1.2.0)
  static const ink4 = Color(0xFF7D87A0); // نص شبه معطل على الفاتح — WCAG AA كبير ≥3:1 (صُدّل 1.2.0)
  static const lightBubble = Color(0xFFE7EBF5); // فقاعة الطرف الآخر على الفاتح

  /// تدرج الهوية الأصلي الثابت (نيلة ← تركواز)
  static const brandGradient = LinearGradient(
    colors: [indigo, teal],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  /// تدرج الهوية الحالي — يتبع ألوان «استوديو التطبيق» (1.13.0)،
  /// ويساوي [brandGradient] حرفياً في الافتراضي.
  static LinearGradient get gradient => AppStudioService.style.value.gradient;

  /// اللون الأساسي الحالي من الاستوديو (نيلة افتراضياً)
  static Color get accent => AppStudioService.style.value.accentColor;
}

/// ألوان دلالية تتبع سطوع الثيم الحالي — استخدمها بدل Colors.white* و
/// WaslColors.dark* الصلبة حتى تعمل كل الشاشات على الوضعين معاً.
extension WaslCtx on BuildContext {
  bool get _dark => Theme.of(this).brightness == Brightness.dark;

  /// خلفية بطاقة/ورقة سفلية بديلة عن الخلفية
  Color get surfaceAlt => _dark ? WaslColors.darkSurface : WaslColors.lightSurface;

  /// زجاج العناصر البينية (شرائط إدخال، بطاقات شفافة)
  Color get glass => _dark ? WaslColors.glass : WaslColors.lightGlass;

  /// نص أساسي
  Color get textPrimary => _dark ? Colors.white : WaslColors.ink;

  /// نص ثانوي (white70 في الداكن)
  Color get textSecondary => _dark ? Colors.white70 : WaslColors.ink2;

  /// نص خافت (white60/white54 في الداكن)
  Color get textTertiary => _dark ? Colors.white60 : WaslColors.ink3;

  /// نص شبه معطل (white38/white54 في الداكن)
  Color get textFaint => _dark ? Colors.white54 : WaslColors.ink4;

  /// حدود وفواصل
  Color get hairline => _dark ? Colors.white24 : Colors.black.withValues(alpha: 0.10);

  /// فقاعة رسالة الطرف الآخر
  Color get bubbleOther => _dark ? WaslColors.darkSurface : WaslColors.lightBubble;

  /// لون الأيقونة القياسي غير الملوّن
  Color get iconStd => _dark ? Colors.white : WaslColors.ink2;

  /// خلفية شريط التطبيق (شفاف يعتمد الخلفية + لون نصه)
  Color get appBarText => _dark ? Colors.white : WaslColors.ink;
}

class WaslTheme {
  static ThemeData get dark => build(Brightness.dark, StudioStyle.defaults);

  static ThemeData get light => build(Brightness.light, StudioStyle.defaults);

  /// يبني الثيم من اختيارات «استوديو التطبيق» (1.13.0). القيم الافتراضية
  /// تنتج الثيم السابق نفسه حرفياً — كل إضافة تُضاف فقط عند تغييرها.
  static ThemeData build(Brightness b, StudioStyle s) {
    final dark = b == Brightness.dark;
    final d = StudioStyle.defaults;
    final scheme = dark
        ? ColorScheme.fromSeed(seedColor: s.accentColor, brightness: Brightness.dark)
        : ColorScheme.fromSeed(seedColor: s.accentColor);
    final baseBg = dark ? WaslColors.darkBg : const Color(0xFFF2F4FA);
    final surface = dark ? WaslColors.darkSurface : WaslColors.lightSurface;
    final glass = dark ? WaslColors.glass : WaslColors.lightGlass;
    final hair = dark ? Colors.white24 : Colors.black.withValues(alpha: 0.10);
    final fg = dark ? Colors.white : WaslColors.ink;

    final Color scaffold = switch (s.backdrop) {
      StudioBackdrop.plain => baseBg,
      StudioBackdrop.pure => dark ? Colors.black : Colors.white,
      _ => Colors.transparent, // الخلفية تُرسم خلف كل صفحة
    };

    final appBar = switch (s.appBar) {
      StudioAppBar.transparent => const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
      StudioAppBar.glass => AppBarTheme(
          backgroundColor: glass,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
      StudioAppBar.solid => AppBarTheme(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: fg,
          elevation: 0,
          centerTitle: false,
        ),
      StudioAppBar.gradient => AppBarTheme(
          backgroundColor: s.accentColor,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
    };

    final cardDefault = s.surface == d.surface && s.roundness == d.roundness;
    final card = cardDefault
        ? null
        : CardThemeData(
            color: switch (s.surface) {
              StudioSurface.glass => glass,
              StudioSurface.solid || StudioSurface.elevated => surface,
              StudioSurface.outlined => Colors.transparent,
            },
            elevation: s.surface == StudioSurface.elevated ? 4 : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(s.r(16)),
              side: s.surface == StudioSurface.outlined
                  ? BorderSide(color: hair)
                  : BorderSide.none,
            ),
          );

    final density = switch (s.density) {
      StudioDensity.compact => VisualDensity.compact,
      StudioDensity.comfortable => null,
      StudioDensity.spacious => const VisualDensity(horizontal: 1, vertical: 1),
    };

    final needsWrap = s.backdrop != StudioBackdrop.plain &&
        s.backdrop != StudioBackdrop.pure;
    // 1.13.1: انتقال موحّد للتطبيق كله (تلاشٍ + انزلاق وتكبير خفيف ~260ms)
    // يحترم «مستوى الحركة»: خفيفة = تلاشٍ قصير، متوقفة = فوري
    final transitions = StudioPageTransitions(wrap: needsWrap, motion: s.motion);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: appBar,
      cardTheme: card,
      visualDensity: density,
      pageTransitionsTheme: transitions,
      navigationBarTheme: (s.navLabels && s.accent == d.accent)
          ? null
          : NavigationBarThemeData(
              labelBehavior: s.navLabels
                  ? NavigationDestinationLabelBehavior.alwaysShow
                  : NavigationDestinationLabelBehavior.alwaysHide,
            ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? WaslColors.glass : const Color(0x0F6366F1), // نيلة خفيفة تعمل على الفاتح
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(s.r(18)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// انتقال صفحات وصل الموحّد (1.13.1): تلاشٍ مع انزلاق قصير وتكبير خفيف
/// للصفحة الداخلة، وتراجع خفيف للصفحة السابقة. المدة حسب «مستوى الحركة»:
/// كاملة 260ms، خفيفة 180ms (تلاشٍ فقط)، متوقفة = فوري بلا حركة.
class WaslPageTransitionsBuilder extends PageTransitionsBuilder {
  const WaslPageTransitionsBuilder(this.motion);
  final StudioMotion motion;

  static Duration durationFor(StudioMotion m) => switch (m) {
        StudioMotion.full => const Duration(milliseconds: 260),
        StudioMotion.reduced => const Duration(milliseconds: 180),
        StudioMotion.off => Duration.zero,
      };

  @override
  Duration get transitionDuration => durationFor(motion);

  @override
  Duration get reverseTransitionDuration => durationFor(motion);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    switch (motion) {
      case StudioMotion.off:
        return child;
      case StudioMotion.reduced:
        return FadeTransition(opacity: animation, child: child);
      case StudioMotion.full:
        final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
        final inC = CurvedAnimation(
            parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        final outC = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.85).animate(outC),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1, end: 0.97).animate(outC),
            child: FadeTransition(
              opacity: inC,
              child: SlideTransition(
                position: Tween<Offset>(begin: Offset(rtl ? -0.06 : 0.06, 0), end: Offset.zero)
                    .animate(inC),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(inC),
                  child: child,
                ),
              ),
            ),
          ),
        );
    }
  }
}

/// انتقالات الصفحات حسب الاستوديو: ترسم خلفية التطبيق خلف كل صفحة،
/// وتطبّق انتقال وصل الموحّد حسب «مستوى الحركة» على كل المنصات.
class StudioPageTransitions extends PageTransitionsTheme {
  StudioPageTransitions({required this.wrap, required this.motion})
      : super(builders: {
          for (final p in TargetPlatform.values) p: WaslPageTransitionsBuilder(motion),
        });
  final bool wrap;
  final StudioMotion motion;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final c = wrap ? StudioBackdropView(child: child) : child;
    return WaslPageTransitionsBuilder(motion)
        .buildTransitions(route, context, animation, secondaryAnimation, c);
  }

  @override
  bool operator ==(Object other) =>
      other is StudioPageTransitions && other.wrap == wrap && other.motion == motion;

  @override
  int get hashCode => Object.hash(wrap, motion);
}

/// وضع المظهر (داكن/فاتح/النظام) مع حفظه محلياً — الوضع الفاتح مكتمَل منذ 0.7.1.
class ThemeService {
  static const _key = 'theme_mode';
  static const _storage = FlutterSecureStorage();
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      mode.value = switch (v) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    } catch (_) {}
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final v = switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
        _ => 'dark',
      };
      await _storage.write(key: _key, value: v);
    } catch (_) {}
  }
}

/// حجم خط التطبيق كنسبة تكبير تُطبَّق على كل النصوص عبر TextScaler.
/// الخيارات: 0.85 صغير، 1.0 عادي، 1.15 كبير، 1.3 أكبر.
class FontScaleService {
  static const _key = 'font_scale';
  static const _storage = FlutterSecureStorage();
  static final ValueNotifier<double> scale = ValueNotifier(1.0);

  /// الخيارات المعروضة في الإعدادات (القيمة، التسمية العربية)
  static const options = <(double, String)>[
    (0.85, 'صغير'),
    (1.0, 'عادي'),
    (1.15, 'كبير'),
    (1.3, 'أكبر'),
  ];

  static Future<void> load() async {
    try {
      final v = double.tryParse(await _storage.read(key: _key) ?? '') ?? 1.0;
      scale.value = v.clamp(0.8, 1.5);
    } catch (_) {}
  }

  static Future<void> set(double v) async {
    scale.value = v;
    try {
      await _storage.write(key: _key, value: v.toString());
    } catch (_) {}
  }
}

/// خلفية شاشة المحادثة: مضمنة داخل التطبيق (لا تنزيلات ولا وسائط خارجية — الخصوصية).
/// 0 = افتراضي (لون الخلفية فقط بلا نمط).
class WallpaperService {
  static const _key = 'chat_wallpaper';
  static const _storage = FlutterSecureStorage();
  static final ValueNotifier<int> index = ValueNotifier(0);

  static final wallpapers = const <WaslWallpaper>[
    WaslWallpaper('افتراضي'),
    WaslWallpaper('ليل وصل', colors: [Color(0xFF0B0F1A), Color(0xFF171F38)], dot: Color(0x14FFFFFF)),
    WaslWallpaper('نيلة', colors: [Color(0xFF10142A), Color(0xFF2A2450)], dot: Color(0x1AFFFFFF)),
    WaslWallpaper('تركواز', colors: [Color(0xFF0A1A1E), Color(0xFF123B3A)], dot: Color(0x18FFFFFF)),
    WaslWallpaper('بنفسج', colors: [Color(0xFF140F1E), Color(0xFF34204A)], dot: Color(0x16FFFFFF)),
    WaslWallpaper('رملي فاتح', colors: [Color(0xFFEFF2F9), Color(0xFFE4E9F4)], dot: Color(0x336366F1)),
    WaslWallpaper('نيلي فاتح', colors: [Color(0xFFEEF1FB), Color(0xFFE3E9FA)], dot: Color(0x2E14B8A6)),
  ];

  static WaslWallpaper get current =>
      (index.value >= 0 && index.value < wallpapers.length) ? wallpapers[index.value] : wallpapers.first;

  static Future<void> load() async {
    try {
      final v = int.tryParse(await _storage.read(key: _key) ?? '') ?? 0;
      index.value = v.clamp(0, wallpapers.length - 1);
    } catch (_) {}
  }

  static Future<void> set(int i) async {
    index.value = i;
    try {
      await _storage.write(key: _key, value: '$i');
    } catch (_) {}
  }
}

class WaslWallpaper {
  final String name;
  final List<Color>? colors; // تدرج الخلفية؛ null = لون الثيم الافتراضي
  final Color? dot; // لون نمط النقاط؛ null = بلا نمط
  const WaslWallpaper(this.name, {this.colors, this.dot});
}

/// يرسم خلفية المحادثة: تدرج ناعم + شبكة نقاط خافتة (نمط مجاني ومضمن).
class WallpaperPainter extends CustomPainter {
  final WaslWallpaper wallpaper;
  final bool dark;
  WallpaperPainter(this.wallpaper, {required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    if (wallpaper.colors != null && wallpaper.colors!.length >= 2) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: wallpaper.colors!,
          ).createShader(rect),
      );
    }
    final dot = wallpaper.dot;
    if (dot != null) {
      const gap = 26.0;
      final r = 1.4;
      final p = Paint()..color = dot;
      for (double y = gap / 2; y < size.height; y += gap) {
        for (double x = gap / 2; x < size.width; x += gap) {
          canvas.drawCircle(Offset(x, y), r, p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant WallpaperPainter old) =>
      old.wallpaper != wallpaper || old.dark != dark;
}
