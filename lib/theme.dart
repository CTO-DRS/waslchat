import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ألوان الهوية الثابتة — لا تتغير بين الوضعين الفاتح والداكن
class WaslColors {
  static const indigo = Color(0xFF6366F1);
  static const teal = Color(0xFF14B8A6);
  static const violet = Color(0xFFA855F7);
  static const darkBg = Color(0xFF0B0F1A);
  static const darkSurface = Color(0xFF151B2B);
  static const glass = Color(0x14FFFFFF);

  static const gradient = LinearGradient(
    colors: [indigo, teal],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
}

/// لوحة ألوان دلالية لكل وضع.
/// كل شاشة تقرأ من `context.wasl` بدل الألوان الصلبة، فيعمل الوضعان الفاتح
/// والداكن بنفس الكود (بند المرحلة 1 من خارطة الطريق).
class WaslPalette {
  // الخلفيات والأسطح
  final Color bg; // خلفية الشاشة
  final Color surface; // البطاقات والأشرطة والنوافذ
  final Color glass; // حاوية زجاجية شفافة (حقول، أزرار ثانوية)
  final Color glassStrong; // زجاج أوضح (شارات، تحديد)
  final Color border; // حدود خفيفة
  final Color bubbleMine; // خلفية فقاعة رسائلي
  final Color bubbleOther; // خلفية فقاعة الطرف الآخر

  // النصوص والأيقونات
  final Color textPrimary; // نص أساسي
  final Color textSecondary; // نص ثانوي (توصيفات، أوقات)
  final Color textFaint; // نص باهت (تلميحات، عناصر مكتومة)
  final Color onBubbleMine; // نص فوق فقاعة رسائلي

  // الألوان الوظيفية
  final Color accent; // لون التمييز (نقرات، روابط)
  final Color success; // نجاح، متصل الآن
  final Color danger; // حذف، حظر، أخطاء
  final Color warning; // نجمة، تحذير
  final Color warningSoft; // خلفية تحذير شفافة
  final Color violetSoft; // خلفية بنفسجية شفافة
  final Color readReceipt; // علامات القراءة (تم القراءة)
  final Color barrier; // حاجز النوافذ الحوارية

  const WaslPalette({
    required this.bg,
    required this.surface,
    required this.glass,
    required this.glassStrong,
    required this.border,
    required this.bubbleMine,
    required this.bubbleOther,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.onBubbleMine,
    required this.accent,
    required this.success,
    required this.danger,
    required this.warning,
    required this.warningSoft,
    required this.violetSoft,
    required this.readReceipt,
    required this.barrier,
  });

  /// الوضع الداكن — مطابق تماماً لمظهر 0.3.0 السابق (لا تغيير بصري للموجودين)
  static const dark = WaslPalette(
    bg: Color(0xFF0B0F1A),
    surface: Color(0xFF151B2B),
    glass: Color(0x14FFFFFF),
    glassStrong: Color(0x22FFFFFF),
    border: Color(0x3DFFFFFF),
    bubbleMine: Color(0x556366F1),
    bubbleOther: Color(0xFF151B2B),
    textPrimary: Colors.white,
    textSecondary: Color(0xB3FFFFFF), // white70
    textFaint: Color(0x99FFFFFF), // white60
    onBubbleMine: Colors.white,
    accent: WaslColors.indigo,
    success: WaslColors.teal,
    danger: Color(0xFFFF5252),
    warning: Color(0xFFFFC107),
    warningSoft: Color(0x33FFC107),
    violetSoft: Color(0x33A855F7),
    readReceipt: Color(0xFF7DF9FF),
    barrier: Colors.black,
  );

  /// الوضع الفاتح — نفس الهوية (بنفسجي/تركوازي) على خلفية فاتحة عالية التباين
  static const light = WaslPalette(
    bg: Color(0xFFF2F4FA),
    surface: Colors.white,
    glass: Color(0x116366F1),
    glassStrong: Color(0x1F6366F1),
    border: Color(0x1F1A2340),
    bubbleMine: Color(0xFF4F46E5),
    bubbleOther: Colors.white,
    textPrimary: Color(0xFF141A2A),
    textSecondary: Color(0xFF4A5568),
    textFaint: Color(0xFF8A94A6),
    onBubbleMine: Colors.white,
    accent: Color(0xFF4F46E5),
    success: Color(0xFF0E9F8C),
    danger: Color(0xFFD32F2F),
    warning: Color(0xFFB26A00),
    warningSoft: Color(0x29FFC107),
    violetSoft: Color(0x24A855F7),
    readReceipt: Color(0xFF2563EB),
    barrier: Color(0x8A000000),
  );
}

/// الوصول للوحة الدلالية من أي سياق: `context.wasl.textPrimary`
extension WaslPaletteX on BuildContext {
  WaslPalette get wasl => Theme.of(this).brightness == Brightness.dark
      ? WaslPalette.dark
      : WaslPalette.light;
}

/// خدمة المظهر: الوضع (فاتح/داكن/حسب النظام) وحجم الخط، محفوظة محلياً على الجهاز.
/// الوضع الافتراضي داكن (السلوك السابق)، والحجم الافتراضي عادي.
class ThemeService {
  static const _kMode = 'theme_mode';
  static const _kFont = 'font_scale';

  /// وضع المظهر الحالي (يُستمع إليه من MaterialApp)
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  /// معامل تكبير الخط (1.0 = عادي)
  static final ValueNotifier<double> fontScale = ValueNotifier(1.0);

  /// مستويات حجم الخط المعروضة في الإعدادات
  static const fontLevels = <String, double>{
    'صغير': 0.85,
    'عادي': 1.0,
    'كبير': 1.15,
    'أكبر': 1.3,
  };

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode.value = switch (p.getString(_kMode)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      fontScale.value = p.getDouble(_kFont) ?? 1.0;
    } catch (_) {
      // بلا تخزين (ويب/قيد) نبقى على الافتراضي
    }
  }

  static Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kMode, m.name);
    } catch (_) {}
  }

  static Future<void> setFontScale(double s) async {
    fontScale.value = s;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kFont, s);
    } catch (_) {}
  }
}

class WaslTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: WaslColors.indigo,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: WaslPalette.dark.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: WaslPalette.dark.surface,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: WaslPalette.dark.surface,
          contentTextStyle: TextStyle(color: WaslPalette.dark.textPrimary),
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: WaslColors.glass,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: WaslColors.indigo,
          brightness: Brightness.light,
          surface: WaslPalette.light.bg,
        ),
        scaffoldBackgroundColor: WaslPalette.light.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: WaslPalette.light.surface,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: WaslPalette.light.surface,
          contentTextStyle: TextStyle(color: WaslPalette.light.textPrimary),
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: WaslPalette.light.glass,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      );
}
