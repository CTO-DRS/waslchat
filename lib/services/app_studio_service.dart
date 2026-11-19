/// استوديو التطبيق (1.13.0): مظهر «وصل شات» كله على ذوقك من داخل التطبيق —
/// الألوان، الخلفية، البطاقات والقوائم، الأشرطة، الفقاعات، الحركة، والإشعار
/// المنبثق، مع سمات جاهزة تطبّق كل ذلك بلمسة واحدة.
///
/// كل الاختيارات محلية على جهازك حصراً (تخزين آمن، نص JSON واحد) ولا تغادره.
/// القيم الافتراضية تطابق مظهر التطبيق قبل الاستوديو حرفياً — فلا يتغير شيء
/// لمن لا يفتح الاستوديو.
///
/// استوديو المحادثة: تخصيص لكل محادثة (خلفية، فقاعات، حجم خط) يُحفظ بمعرّف
/// المحادثة، وما لم يُخصَّص يتبع اختيار التطبيق العام.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ==================== الخيارات ====================

/// خلفية التطبيق خلف كل الشاشات
enum StudioBackdrop {
  plain('افتراضي'),
  soft('تدرج هادئ'),
  aurora('شفق متحرك'),
  stars('نجوم'),
  dusk('غسق'),
  ocean('محيط'),
  forest('غابة'),
  sand('رمال'),
  dots('نقاط'),
  pure('نقي');

  const StudioBackdrop(this.label);
  final String label;

  /// خلفيات تتحرك (تتوقف عند إيقاف الحركة)
  bool get animated => this == aurora || this == stars;
}

/// شكل البطاقات والمجموعات
enum StudioSurface {
  glass('زجاجي'),
  solid('مصمت'),
  outlined('بإطار'),
  elevated('بارز');

  const StudioSurface(this.label);
  final String label;
}

/// استدارة الزوايا
enum StudioRoundness {
  sharp('حادة', 0.45),
  soft('خفيفة', 0.75),
  round('مستديرة', 1.0),
  extra('دائرية جداً', 1.3);

  const StudioRoundness(this.label, this.factor);
  final String label;
  final double factor;
}

/// كثافة العناصر
enum StudioDensity {
  compact('مضغوطة'),
  comfortable('مريحة'),
  spacious('واسعة');

  const StudioDensity(this.label);
  final String label;
}

/// شكل قائمة المحادثات
enum StudioListStyle {
  flat('بسيطة'),
  cards('بطاقات');

  const StudioListStyle(this.label);
  final String label;
}

/// شكل الصورة الشخصية في القوائم
enum StudioAvatarShape {
  circle('دائرة'),
  squircle('مربع ناعم');

  const StudioAvatarShape(this.label);
  final String label;
}

/// الشريط العلوي
enum StudioAppBar {
  transparent('شفاف'),
  glass('زجاجي'),
  gradient('متدرج'),
  solid('مصمت');

  const StudioAppBar(this.label);
  final String label;
}

/// الشريط السفلي
enum StudioNav {
  floating('عائم'),
  classic('كلاسيكي'),
  minimal('بسيط');

  const StudioNav(this.label);
  final String label;
}

/// شريط الكتابة في المحادثة
enum StudioInput {
  rounded('مستدير'),
  pill('كبسولة'),
  outlined('بإطار'),
  minimal('بسيط');

  const StudioInput(this.label);
  final String label;
}

/// شكل الفقاعة
enum StudioBubbleShape {
  round('مستديرة', 20),
  soft('ناعمة', 14),
  sharp('حادة', 8);

  const StudioBubbleShape(this.label, this.radius);
  final String label;
  final double radius;
}

/// تعبئة فقاعتي
enum StudioBubbleFill {
  gradient('متدرجة'),
  solid('لون واحد');

  const StudioBubbleFill(this.label);
  final String label;
}

/// مستوى الحركة في التطبيق
enum StudioMotion {
  full('كاملة'),
  reduced('خفيفة'),
  off('متوقفة');

  const StudioMotion(this.label);
  final String label;
}

/// شكل الإشعار المنبثق داخل التطبيق
enum StudioBanner {
  card('بطاقة'),
  pill('كبسولة'),
  toast('شريط سفلي');

  const StudioBanner(this.label);
  final String label;
}

/// شكل شاشة القفل عند فتح التطبيق
enum StudioLock {
  aurora('شفق'),
  mascot('وصول'),
  glass('زجاجي'),
  minimal('بسيط'),
  night('ليلي');

  const StudioLock(this.label);
  final String label;
}

T _enumOf<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// ==================== النمط ====================

/// كل اختيارات الاستوديو في كائن واحد غير قابل للتغيير
@immutable
class StudioStyle {
  const StudioStyle({
    this.accent = 0xFF6366F1,
    this.accent2 = 0xFF14B8A6,
    this.backdrop = StudioBackdrop.plain,
    this.surface = StudioSurface.glass,
    this.roundness = StudioRoundness.round,
    this.density = StudioDensity.comfortable,
    this.listStyle = StudioListStyle.flat,
    this.avatarShape = StudioAvatarShape.circle,
    this.appBar = StudioAppBar.transparent,
    this.nav = StudioNav.floating,
    this.navLabels = true,
    this.input = StudioInput.rounded,
    this.bubbleShape = StudioBubbleShape.round,
    this.bubbleTail = false,
    this.bubbleFill = StudioBubbleFill.gradient,
    this.ownBubble,
    this.otherBubble,
    this.motion = StudioMotion.full,
    this.banner = StudioBanner.card,
    this.bannerTop = true,
    this.bannerSeconds = 4,
    this.bannerPreview = true,
    this.themeId,
    this.lockOn = true,
    this.lockStyle = StudioLock.aurora,
    this.haptics = true,
    this.autoDayNight = false,
  });

  /// اللون الأساسي واللون المرافق (ARGB)
  final int accent;
  final int accent2;
  final StudioBackdrop backdrop;
  final StudioSurface surface;
  final StudioRoundness roundness;
  final StudioDensity density;
  final StudioListStyle listStyle;
  final StudioAvatarShape avatarShape;
  final StudioAppBar appBar;
  final StudioNav nav;
  final bool navLabels;
  final StudioInput input;
  final StudioBubbleShape bubbleShape;
  final bool bubbleTail;
  final StudioBubbleFill bubbleFill;

  /// لون فقاعتي المخصص (null = من اللون الأساسي)
  final int? ownBubble;

  /// صبغة فقاعة الطرف الآخر (null = الافتراضي)
  final int? otherBubble;
  final StudioMotion motion;
  final StudioBanner banner;
  final bool bannerTop;
  final int bannerSeconds;
  final bool bannerPreview;

  /// السمة الجاهزة المطبقة آخر مرة (للعرض فقط)
  final String? themeId;

  /// شاشة القفل عند كل فتح (للمسجّلين)
  final bool lockOn;
  final StudioLock lockStyle;

  /// اهتزازات لمس خفيفة
  final bool haptics;

  /// فاتح نهاراً وداكن ليلاً تلقائياً
  final bool autoDayNight;

  static const defaults = StudioStyle();

  Color get accentColor => Color(accent);
  Color get accent2Color => Color(accent2);

  /// تدرج الهوية (يساوي WaslColors.gradient الأصلي في الافتراضي)
  LinearGradient get gradient => LinearGradient(
        colors: [Color(accent), Color(accent2)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      );

  double r(double base) => base * roundness.factor;

  bool get isDefault => jsonEncode(toJson()) == jsonEncode(defaults.toJson());

  StudioStyle copyWith({
    int? accent,
    int? accent2,
    StudioBackdrop? backdrop,
    StudioSurface? surface,
    StudioRoundness? roundness,
    StudioDensity? density,
    StudioListStyle? listStyle,
    StudioAvatarShape? avatarShape,
    StudioAppBar? appBar,
    StudioNav? nav,
    bool? navLabels,
    StudioInput? input,
    StudioBubbleShape? bubbleShape,
    bool? bubbleTail,
    StudioBubbleFill? bubbleFill,
    int? Function()? ownBubble,
    int? Function()? otherBubble,
    StudioMotion? motion,
    StudioBanner? banner,
    bool? bannerTop,
    int? bannerSeconds,
    bool? bannerPreview,
    String? Function()? themeId,
    bool? lockOn,
    StudioLock? lockStyle,
    bool? haptics,
    bool? autoDayNight,
  }) =>
      StudioStyle(
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        backdrop: backdrop ?? this.backdrop,
        surface: surface ?? this.surface,
        roundness: roundness ?? this.roundness,
        density: density ?? this.density,
        listStyle: listStyle ?? this.listStyle,
        avatarShape: avatarShape ?? this.avatarShape,
        appBar: appBar ?? this.appBar,
        nav: nav ?? this.nav,
        navLabels: navLabels ?? this.navLabels,
        input: input ?? this.input,
        bubbleShape: bubbleShape ?? this.bubbleShape,
        bubbleTail: bubbleTail ?? this.bubbleTail,
        bubbleFill: bubbleFill ?? this.bubbleFill,
        ownBubble: ownBubble != null ? ownBubble() : this.ownBubble,
        otherBubble: otherBubble != null ? otherBubble() : this.otherBubble,
        motion: motion ?? this.motion,
        banner: banner ?? this.banner,
        bannerTop: bannerTop ?? this.bannerTop,
        bannerSeconds: bannerSeconds ?? this.bannerSeconds,
        bannerPreview: bannerPreview ?? this.bannerPreview,
        themeId: themeId != null ? themeId() : this.themeId,
        lockOn: lockOn ?? this.lockOn,
        lockStyle: lockStyle ?? this.lockStyle,
        haptics: haptics ?? this.haptics,
        autoDayNight: autoDayNight ?? this.autoDayNight,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'accent': accent,
        'accent2': accent2,
        'backdrop': backdrop.name,
        'surface': surface.name,
        'roundness': roundness.name,
        'density': density.name,
        'list': listStyle.name,
        'avatar': avatarShape.name,
        'appBar': appBar.name,
        'nav': nav.name,
        'navLabels': navLabels,
        'input': input.name,
        'bubbleShape': bubbleShape.name,
        'bubbleTail': bubbleTail,
        'bubbleFill': bubbleFill.name,
        'own': ownBubble,
        'other': otherBubble,
        'motion': motion.name,
        'banner': banner.name,
        'bannerTop': bannerTop,
        'bannerSeconds': bannerSeconds,
        'bannerPreview': bannerPreview,
        'theme': themeId,
        'lockOn': lockOn,
        'lock': lockStyle.name,
        'haptics': haptics,
        'dayNight': autoDayNight,
      };

  /// قراءة متسامحة: أي حقل ناقص أو تالف يعود لقيمته الافتراضية
  factory StudioStyle.fromJson(Map<String, dynamic> j) {
    const d = defaults;
    int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
    return StudioStyle(
      accent: asInt(j['accent']) ?? d.accent,
      accent2: asInt(j['accent2']) ?? d.accent2,
      backdrop: _enumOf(StudioBackdrop.values, j['backdrop'], d.backdrop),
      surface: _enumOf(StudioSurface.values, j['surface'], d.surface),
      roundness: _enumOf(StudioRoundness.values, j['roundness'], d.roundness),
      density: _enumOf(StudioDensity.values, j['density'], d.density),
      listStyle: _enumOf(StudioListStyle.values, j['list'], d.listStyle),
      avatarShape: _enumOf(StudioAvatarShape.values, j['avatar'], d.avatarShape),
      appBar: _enumOf(StudioAppBar.values, j['appBar'], d.appBar),
      nav: _enumOf(StudioNav.values, j['nav'], d.nav),
      navLabels: j['navLabels'] is bool ? j['navLabels'] as bool : d.navLabels,
      input: _enumOf(StudioInput.values, j['input'], d.input),
      bubbleShape: _enumOf(StudioBubbleShape.values, j['bubbleShape'], d.bubbleShape),
      bubbleTail: j['bubbleTail'] is bool ? j['bubbleTail'] as bool : d.bubbleTail,
      bubbleFill: _enumOf(StudioBubbleFill.values, j['bubbleFill'], d.bubbleFill),
      ownBubble: asInt(j['own']),
      otherBubble: asInt(j['other']),
      motion: _enumOf(StudioMotion.values, j['motion'], d.motion),
      banner: _enumOf(StudioBanner.values, j['banner'], d.banner),
      bannerTop: j['bannerTop'] is bool ? j['bannerTop'] as bool : d.bannerTop,
      bannerSeconds: (asInt(j['bannerSeconds']) ?? d.bannerSeconds).clamp(2, 10),
      bannerPreview:
          j['bannerPreview'] is bool ? j['bannerPreview'] as bool : d.bannerPreview,
      themeId: j['theme'] is String ? j['theme'] as String : null,
      lockOn: j['lockOn'] is bool ? j['lockOn'] as bool : d.lockOn,
      lockStyle: _enumOf(StudioLock.values, j['lock'], d.lockStyle),
      haptics: j['haptics'] is bool ? j['haptics'] as bool : d.haptics,
      autoDayNight: j['dayNight'] is bool ? j['dayNight'] as bool : d.autoDayNight,
    );
  }

  static StudioStyle decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return StudioStyle.fromJson(j);
    } catch (_) {}
    return defaults;
  }

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is StudioStyle && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

// ==================== اللوحات والسمات ====================

/// زوج ألوان جاهز (الأساسي + المرافق)
class StudioPalette {
  const StudioPalette(this.name, this.accent, this.accent2);
  final String name;
  final int accent;
  final int accent2;
}

/// سمة جاهزة تطبّق كل شيء دفعة واحدة
class StudioTheme {
  const StudioTheme(this.id, this.name, this.style, {this.mode});
  final String id;
  final String name;
  final StudioStyle style;

  /// وضع المظهر المناسب للسمة (null = لا يغيّر الوضع الحالي)
  final ThemeMode? mode;
}

class StudioCatalog {
  StudioCatalog._();

  /// لوحات الألوان — اللون الأساسي لكل منها يحقق تبايناً ≥3:1 مع النص الأبيض
  static const palettes = <StudioPalette>[
    StudioPalette('وصل', 0xFF6366F1, 0xFF14B8A6),
    StudioPalette('بنفسج', 0xFF7C3AED, 0xFFEC4899),
    StudioPalette('سماء', 0xFF2563EB, 0xFF06B6D4),
    StudioPalette('زمرد', 0xFF059669, 0xFF10B981),
    StudioPalette('غروب', 0xFFEA580C, 0xFFDB2777),
    StudioPalette('ورد', 0xFFDB2777, 0xFFF472B6),
    StudioPalette('ذهب', 0xFFA16207, 0xFFF59E0B),
    StudioPalette('ياقوت', 0xFFDC2626, 0xFFF97316),
    StudioPalette('محيط', 0xFF0284C7, 0xFF14B8A6),
    StudioPalette('ليلك', 0xFFC026D3, 0xFF8B5CF6),
    StudioPalette('رمادي', 0xFF475569, 0xFF94A3B8),
    StudioPalette('غابة', 0xFF16A34A, 0xFF65A30D),
  ];

  /// ألوان حرة للاختيار (اللون الأساسي أو لون فقاعتي) — كلها ≥3:1 مع الأبيض
  static const swatches = <int>[
    0xFF6366F1, 0xFF4F46E5, 0xFF7C3AED, 0xFF8B5CF6, 0xFFC026D3, 0xFFDB2777,
    0xFFE11D48, 0xFFDC2626, 0xFFEA580C, 0xFFD97706, 0xFFA16207, 0xFF65A30D,
    0xFF16A34A, 0xFF059669, 0xFF0D9488, 0xFF0891B2, 0xFF0284C7, 0xFF2563EB,
    0xFF1E3A8A, 0xFF475569, 0xFF92400E, 0xFF111827,
  ];

  /// صبغات فقاعة الطرف الآخر — تُمزج بخفة فوق لون الفقاعة الأصلي
  static const otherTints = <int>[
    0xFF6366F1, 0xFF14B8A6, 0xFF8B5CF6, 0xFFEC4899, 0xFFF59E0B, 0xFF22C55E,
    0xFF0EA5E9, 0xFFEF4444,
  ];

  static const themes = <StudioTheme>[
    StudioTheme('wasl_night', 'ليل وصل', StudioStyle(themeId: 'wasl_night'),
        mode: ThemeMode.dark),
    StudioTheme(
        'dawn',
        'فجر',
        StudioStyle(
          accent: 0xFFEA580C,
          accent2: 0xFFDB2777,
          backdrop: StudioBackdrop.soft,
          surface: StudioSurface.elevated,
          appBar: StudioAppBar.transparent,
          bubbleShape: StudioBubbleShape.soft,
          bubbleTail: true,
          themeId: 'dawn',
        ),
        mode: ThemeMode.light),
    StudioTheme(
        'desert',
        'صحراء',
        StudioStyle(
          accent: 0xFFA16207,
          accent2: 0xFFF59E0B,
          backdrop: StudioBackdrop.sand,
          surface: StudioSurface.solid,
          roundness: StudioRoundness.soft,
          avatarShape: StudioAvatarShape.squircle,
          bubbleShape: StudioBubbleShape.soft,
          bubbleFill: StudioBubbleFill.solid,
          themeId: 'desert',
        )),
    StudioTheme(
        'ocean',
        'محيط',
        StudioStyle(
          accent: 0xFF0284C7,
          accent2: 0xFF14B8A6,
          backdrop: StudioBackdrop.ocean,
          appBar: StudioAppBar.glass,
          bubbleTail: true,
          input: StudioInput.pill,
          themeId: 'ocean',
        ),
        mode: ThemeMode.dark),
    StudioTheme(
        'emerald',
        'زمرد',
        StudioStyle(
          accent: 0xFF059669,
          accent2: 0xFF10B981,
          backdrop: StudioBackdrop.forest,
          surface: StudioSurface.outlined,
          listStyle: StudioListStyle.cards,
          themeId: 'emerald',
        ),
        mode: ThemeMode.dark),
    StudioTheme(
        'rose',
        'وردي',
        StudioStyle(
          accent: 0xFFDB2777,
          accent2: 0xFFF472B6,
          backdrop: StudioBackdrop.dusk,
          roundness: StudioRoundness.extra,
          avatarShape: StudioAvatarShape.squircle,
          input: StudioInput.pill,
          bubbleTail: true,
          themeId: 'rose',
        )),
    StudioTheme(
        'classic',
        'كلاسيكي',
        StudioStyle(
          accent: 0xFF2563EB,
          accent2: 0xFF0891B2,
          surface: StudioSurface.solid,
          roundness: StudioRoundness.soft,
          appBar: StudioAppBar.solid,
          nav: StudioNav.classic,
          input: StudioInput.outlined,
          bubbleShape: StudioBubbleShape.sharp,
          bubbleTail: true,
          bubbleFill: StudioBubbleFill.solid,
          themeId: 'classic',
        ),
        mode: ThemeMode.light),
    StudioTheme(
        'contrast',
        'عالي التباين',
        StudioStyle(
          accent: 0xFF1E3A8A,
          accent2: 0xFF111827,
          backdrop: StudioBackdrop.pure,
          surface: StudioSurface.outlined,
          appBar: StudioAppBar.solid,
          nav: StudioNav.classic,
          input: StudioInput.outlined,
          bubbleFill: StudioBubbleFill.solid,
          motion: StudioMotion.reduced,
          themeId: 'contrast',
        )),
    StudioTheme(
        'aurora',
        'شفق',
        StudioStyle(
          accent: 0xFF7C3AED,
          accent2: 0xFF14B8A6,
          backdrop: StudioBackdrop.aurora,
          appBar: StudioAppBar.glass,
          listStyle: StudioListStyle.cards,
          themeId: 'aurora',
        ),
        mode: ThemeMode.dark),
    StudioTheme(
        'stars',
        'سماء النجوم',
        StudioStyle(
          accent: 0xFF4F46E5,
          accent2: 0xFF0EA5E9,
          backdrop: StudioBackdrop.stars,
          nav: StudioNav.minimal,
          themeId: 'stars',
        ),
        mode: ThemeMode.dark),
  ];

  static StudioTheme? themeById(String? id) {
    for (final t in themes) {
      if (t.id == id) return t;
    }
    return null;
  }
}

// ==================== الخدمة ====================

class AppStudioService {
  AppStudioService._();

  static const _key = 'app_studio_style_v1';
  static const _storage = FlutterSecureStorage();

  /// النمط الحالي — كل الواجهة تستمع له
  static final ValueNotifier<StudioStyle> style =
      ValueNotifier<StudioStyle>(StudioStyle.defaults);

  /// الحركة مسموحة؟ (تتوقف كلياً عند «متوقفة»)
  static bool get motionOn => style.value.motion != StudioMotion.off;

  /// حركة كاملة (الشخصية والخلفيات المتحركة)
  static bool get motionFull => style.value.motion == StudioMotion.full;

  static Future<void> load() async {
    try {
      style.value = StudioStyle.decode(await _storage.read(key: _key));
    } catch (_) {}
  }

  static Future<void> set(StudioStyle s) async {
    style.value = s;
    try {
      await _storage.write(key: _key, value: s.encode());
    } catch (_) {}
  }

  /// تعديل جزئي: أي تعديل يدوي يُسقط اسم السمة الجاهزة
  static Future<void> update(StudioStyle Function(StudioStyle s) f) =>
      set(f(style.value).copyWith(themeId: () => null));

  /// السمة تغيّر الشكل فقط — إعدادات القفل والاهتزاز والوضع التلقائي تبقى لك
  static Future<void> applyTheme(StudioTheme t) => set(keepPersonal(t.style, style.value));

  static Future<void> reset() => set(keepPersonal(StudioStyle.defaults, style.value));

  /// ينقل الإعدادات الشخصية (لا الشكلية) من [from] إلى [to]
  static StudioStyle keepPersonal(StudioStyle to, StudioStyle from) => to.copyWith(
        lockOn: from.lockOn,
        haptics: from.haptics,
        autoDayNight: from.autoDayNight,
      );

  /// الوضع الفعلي: «تلقائي حسب الوقت» = فاتح من 6 صباحاً حتى 6 مساءً
  static ThemeMode effectiveMode(ThemeMode chosen, StudioStyle s, DateTime now) {
    if (!s.autoDayNight) return chosen;
    return (now.hour >= 6 && now.hour < 18) ? ThemeMode.light : ThemeMode.dark;
  }

  /// نبضة كل دقيقة لتحديث الوضع التلقائي والساعة (تُشغَّل من main)
  static final ValueNotifier<int> minuteTick = ValueNotifier<int>(0);

  // ---------- اللمس ----------
  /// لمسة اختيار خفيفة (شرائح، تبويبات، أزرار رقمية)
  static void tick() {
    if (style.value.haptics) HapticFeedback.selectionClick();
  }

  /// لمسة تأكيد (إرسال، فتح القفل)
  static void thump() {
    if (style.value.haptics) HapticFeedback.mediumImpact();
  }

  /// اهتزاز خطأ (رمز خاطئ)
  static void buzz() {
    if (style.value.haptics) HapticFeedback.heavyImpact();
  }
}

// ==================== استوديو المحادثة ====================

/// تخصيص محادثة واحدة. كل حقل null = يتبع اختيار التطبيق العام
@immutable
class ChatStyle {
  const ChatStyle({
    this.wallpaper,
    this.imagePath,
    this.ownBubble,
    this.otherBubble,
    this.bubbleShape,
    this.bubbleFill,
    this.fontScale,
  });

  /// رقم خلفية من خلفيات المحادثة المضمنة (null = مثل التطبيق)
  final int? wallpaper;

  /// صورة من الجهاز (مسار محلي) — تتقدم على [wallpaper]
  final String? imagePath;
  final int? ownBubble;
  final int? otherBubble;
  final StudioBubbleShape? bubbleShape;
  final StudioBubbleFill? bubbleFill;

  /// تكبير نص هذه المحادثة فوق حجم خط التطبيق (null = 1.0)
  final double? fontScale;

  static const empty = ChatStyle();

  bool get isEmpty =>
      wallpaper == null &&
      imagePath == null &&
      ownBubble == null &&
      otherBubble == null &&
      bubbleShape == null &&
      bubbleFill == null &&
      fontScale == null;

  ChatStyle copyWith({
    int? Function()? wallpaper,
    String? Function()? imagePath,
    int? Function()? ownBubble,
    int? Function()? otherBubble,
    StudioBubbleShape? Function()? bubbleShape,
    StudioBubbleFill? Function()? bubbleFill,
    double? Function()? fontScale,
  }) =>
      ChatStyle(
        wallpaper: wallpaper != null ? wallpaper() : this.wallpaper,
        imagePath: imagePath != null ? imagePath() : this.imagePath,
        ownBubble: ownBubble != null ? ownBubble() : this.ownBubble,
        otherBubble: otherBubble != null ? otherBubble() : this.otherBubble,
        bubbleShape: bubbleShape != null ? bubbleShape() : this.bubbleShape,
        bubbleFill: bubbleFill != null ? bubbleFill() : this.bubbleFill,
        fontScale: fontScale != null ? fontScale() : this.fontScale,
      );

  Map<String, dynamic> toJson() => {
        if (wallpaper != null) 'wp': wallpaper,
        if (imagePath != null) 'img': imagePath,
        if (ownBubble != null) 'own': ownBubble,
        if (otherBubble != null) 'other': otherBubble,
        if (bubbleShape != null) 'shape': bubbleShape!.name,
        if (bubbleFill != null) 'fill': bubbleFill!.name,
        if (fontScale != null) 'font': fontScale,
      };

  factory ChatStyle.fromJson(Map<String, dynamic> j) {
    int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
    StudioBubbleShape? shape;
    for (final s in StudioBubbleShape.values) {
      if (s.name == j['shape']) shape = s;
    }
    StudioBubbleFill? fill;
    for (final f in StudioBubbleFill.values) {
      if (f.name == j['fill']) fill = f;
    }
    final font = j['font'];
    return ChatStyle(
      wallpaper: asInt(j['wp']),
      imagePath: j['img'] is String ? j['img'] as String : null,
      ownBubble: asInt(j['own']),
      otherBubble: asInt(j['other']),
      bubbleShape: shape,
      bubbleFill: fill,
      fontScale: font is num ? font.toDouble().clamp(0.8, 1.5) : null,
    );
  }

  static ChatStyle decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return ChatStyle.fromJson(j);
    } catch (_) {}
    return empty;
  }

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) => other is ChatStyle && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// شكل الفقاعة الفعلي بعد دمج تخصيص المحادثة مع اختيار التطبيق
@immutable
class BubbleLook {
  const BubbleLook({
    required this.radius,
    required this.tail,
    required this.gradient,
    required this.ownColor,
    required this.otherTint,
  });

  final double radius;
  final bool tail;

  /// تدرج فقاعتي (null = لون واحد [ownColor])
  final LinearGradient? gradient;
  final Color ownColor;

  /// صبغة فقاعة الطرف الآخر (null = اللون الافتراضي)
  final Color? otherTint;

  /// يدمج: تخصيص المحادثة ← ثم التطبيق
  static BubbleLook resolve(StudioStyle g, ChatStyle? c) {
    final shape = c?.bubbleShape ?? g.bubbleShape;
    final fill = c?.bubbleFill ?? g.bubbleFill;
    final own = c?.ownBubble ?? g.ownBubble;
    final other = c?.otherBubble ?? g.otherBubble;
    final ownColor = Color(own ?? g.accent);
    LinearGradient? grad;
    if (fill == StudioBubbleFill.gradient) {
      grad = own == null
          ? g.gradient
          : LinearGradient(
              colors: [ownColor, Color.lerp(ownColor, Colors.black, 0.28)!],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            );
    }
    return BubbleLook(
      radius: shape.radius * g.roundness.factor,
      tail: g.bubbleTail,
      gradient: grad,
      ownColor: ownColor,
      otherTint: other == null ? null : Color(other),
    );
  }

  /// لون فقاعة الطرف الآخر فوق اللون الأساسي للوضع
  Color otherColor(Color base) => otherTint == null
      ? base
      : Color.alphaBlend(otherTint!.withValues(alpha: 0.22), base);

  /// زوايا الفقاعة مع ذيل اختياري في جهة المرسل
  BorderRadiusGeometry borderRadius({required bool mine}) {
    final r = Radius.circular(radius);
    if (!tail) return BorderRadius.all(r);
    const t = Radius.circular(4);
    return mine
        ? BorderRadiusDirectional.only(
            topStart: r, topEnd: r, bottomStart: r, bottomEnd: t)
        : BorderRadiusDirectional.only(
            topStart: r, topEnd: r, bottomStart: t, bottomEnd: r);
  }

  BoxDecoration decoration({required bool mine, required Color otherBase}) =>
      BoxDecoration(
        gradient: mine ? gradient : null,
        color: mine ? (gradient == null ? ownColor : null) : otherColor(otherBase),
        borderRadius: borderRadius(mine: mine),
      );
}

class ChatStudioService {
  ChatStudioService._();

  static const _prefix = 'chat_studio_';
  static const _storage = FlutterSecureStorage();
  static final Map<String, ValueNotifier<ChatStyle>> _cache = {};

  /// مستمع تخصيص محادثة (يُحمَّل من التخزين أول مرة)
  static ValueNotifier<ChatStyle> of(String conversationId) {
    final existing = _cache[conversationId];
    if (existing != null) return existing;
    final n = ValueNotifier<ChatStyle>(ChatStyle.empty);
    _cache[conversationId] = n;
    () async {
      try {
        final raw = await _storage.read(key: '$_prefix$conversationId');
        n.value = ChatStyle.decode(raw);
      } catch (_) {}
    }();
    return n;
  }

  static Future<void> set(String conversationId, ChatStyle s) async {
    final n = _cache[conversationId] ??= ValueNotifier<ChatStyle>(s);
    n.value = s;
    try {
      if (s.isEmpty) {
        await _storage.delete(key: '$_prefix$conversationId');
      } else {
        await _storage.write(key: '$_prefix$conversationId', value: s.encode());
      }
    } catch (_) {}
  }

  static Future<void> reset(String conversationId) =>
      set(conversationId, ChatStyle.empty);

  /// للاختبارات: حقن قيمة دون تخزين
  @visibleForTesting
  static void debugPut(String conversationId, ChatStyle s) {
    (_cache[conversationId] ??= ValueNotifier<ChatStyle>(s)).value = s;
  }
}

// ==================== جولة الترحيب ====================

/// جولة الترحيب تظهر عند أول تسجيل دخول لكل حساب على هذا الجهاز —
/// لا قبل الدخول ولا عند كل فتح.
class WelcomeService {
  WelcomeService._();

  static const _prefix = 'welcome_seen_';
  static const _storage = FlutterSecureStorage();

  /// معرّف الحساب الذي ينتظر جولته الآن (null = لا جولة)
  static final ValueNotifier<String?> pendingFor = ValueNotifier<String?>(null);

  /// 1.13.1: الجولة لا تظهر إلا بعد إجراء دخول/تسجيل صريح من شاشة الدخول.
  /// Supabase قد يطلق حدث signedIn عند استعادة الجلسة أو تجديد الرمز، فلا
  /// يكفي الحدث وحده — شاشة الدخول «تسلّح» الجولة قبل طلب الدخول.
  static bool _armed = false;
  static bool get armed => _armed;

  /// تستدعيها شاشة الدخول قبل signIn/signUp/OAuth مباشرة
  static void expectSignIn() => _armed = true;

  /// إلغاء التسليح (فشل الدخول) — اختياري
  static void disarm() => _armed = false;

  /// يُستدعى عند حدث «تسجيل دخول»؛ يتجاهله ما لم يسبقه إجراء دخول صريح
  static Future<void> onSignedIn(String uid) async {
    if (!_armed) return;
    _armed = false;
    try {
      final seen = await _storage.read(key: '$_prefix$uid');
      if (seen != '1') pendingFor.value = uid;
    } catch (_) {}
  }

  /// جلسة موجودة عند فتح التطبيق (مستخدم كان داخلاً قبل التحديث):
  /// تُعلَّم الجولة كمشاهَدة بصمت لهذا الحساب. تبقى إعادتها من الإعدادات.
  static Future<void> onSessionRestored(String uid) async {
    if (pendingFor.value == uid) return;
    try {
      final seen = await _storage.read(key: '$_prefix$uid');
      if (seen != '1') await _storage.write(key: '$_prefix$uid', value: '1');
    } catch (_) {}
  }

  /// هل شوهدت الجولة لهذا الحساب؟ (للاختبارات والإعدادات)
  static Future<bool> seenFor(String uid) async {
    try {
      return await _storage.read(key: '$_prefix$uid') == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    final uid = pendingFor.value;
    pendingFor.value = null;
    if (uid == null) return;
    try {
      await _storage.write(key: '$_prefix$uid', value: '1');
    } catch (_) {}
  }
}
