import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/app_icon_service.dart';
import '../services/app_lock_service.dart';
import '../services/app_studio_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/in_app_banner.dart';
import '../widgets/lock_gate.dart';
import '../widgets/studio_backdrop.dart';
import '../widgets/wasl_mascot.dart';
import '../widgets/wasl_sheet.dart';
import 'voice_studio_screen.dart';
import 'welcome_screen.dart';

/// «استوديو التطبيق» (1.13.0): غيّر شكل وصل كله من مكان واحد، وشاهد
/// النتيجة مباشرة في المعاينة أعلى الشاشة قبل أن تخرج.
class AppStudioScreen extends StatefulWidget {
  const AppStudioScreen({super.key});

  @override
  State<AppStudioScreen> createState() => _AppStudioScreenState();
}

class _AppStudioScreenState extends State<AppStudioScreen> {
  String _icon = AppIconService.classic;
  bool _iconBusy = false;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    AppLockService.hasPin().then((v) {
      if (mounted) setState(() => _hasPin = v);
    });
    AppIconService.current().then((v) {
      if (mounted) setState(() => _icon = v);
    });
  }

  void _up(StudioStyle Function(StudioStyle s) f) {
    AppStudioService.tick();
    AppStudioService.update(f);
  }

  void _previewLock() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => WaslLockScreen(
        pin: false,
        bio: false,
        busy: false,
        unlocking: false,
        onBiometric: () {},
        onUnlock: () => Navigator.of(ctx).pop(),
      ),
    ));
  }

  Future<void> _setupPin() async {
    final pin = await Navigator.of(context).push<String>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PinSetupScreen()));
    if (pin == null) return;
    final ok = await AppLockService.setPin(pin);
    if (!mounted) return;
    setState(() => _hasPin = ok || _hasPin);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'تم حفظ رمز القفل' : 'تعذّر حفظ الرمز')));
  }

  Future<void> _removePin() async {
    await AppLockService.removePin();
    if (mounted) setState(() => _hasPin = false);
  }

  Future<void> _applyTheme(StudioTheme t) async {
    await AppStudioService.applyTheme(t);
    if (t.mode != null) await ThemeService.set(t.mode!);
  }

  Future<void> _pickIcon(String id) async {
    if (_iconBusy || id == _icon) return;
    setState(() => _iconBusy = true);
    final ok = await AppIconService.set(id);
    if (!mounted) return;
    setState(() {
      _iconBusy = false;
      if (ok) _icon = id;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'تم تغيير أيقونة التطبيق — قد تحتاج الشاشة الرئيسية ثوانيَ لتتحدّث'
            : 'تغيير الأيقونة متاح على أندرويد فقط')));
  }

  Future<void> _reset() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إعادة الضبط'),
        content: const Text(
            'يعود شكل التطبيق كما كان أول مرة: الألوان والخلفية والأشرطة والفقاعات والحركة والإشعار المنبثق وحجم الخط وخلفية المحادثة.\n\nالأيقونة والوضع الداكن/الفاتح وتخصيص كل محادثة تبقى كما هي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('أعد الضبط')),
        ],
      ),
    );
    if (go != true) return;
    await AppStudioService.reset();
    await FontScaleService.set(1.0);
    await WallpaperService.set(0);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('عاد التطبيق لشكله الأصلي')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StudioStyle>(
      valueListenable: AppStudioService.style,
      builder: (context, s, _) => Scaffold(
        appBar: AppBar(
          title: const Text('استوديو التطبيق',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: StudioPreview(style: s),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: [
                // ---------- السمات الجاهزة ----------
                const SheetSectionLabel('السمات الجاهزة'),
                _Box(children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final t in StudioCatalog.themes)
                        StudioThemeChip(
                          theme: t,
                          selected:
                              (s.themeId ?? (s.isDefault ? 'wasl_night' : null)) == t.id,
                          onTap: () => _applyTheme(t),
                        ),
                    ],
                  ),
                ]),

                // ---------- الألوان ----------
                const SheetSectionLabel('الألوان'),
                _Box(children: [
                  _Label('الوضع'),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeService.mode,
                    builder: (_, m, __) => _Chips<ThemeMode>(
                      values: const [ThemeMode.dark, ThemeMode.light, ThemeMode.system],
                      current: m,
                      label: (v) => switch (v) {
                        ThemeMode.dark => 'داكن',
                        ThemeMode.light => 'فاتح',
                        ThemeMode.system => 'حسب الجوال',
                      },
                      onPick: ThemeService.set,
                    ),
                  ),
                  _Label('لوحات جاهزة'),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final p in StudioCatalog.palettes)
                      _PaletteDot(
                        palette: p,
                        selected: s.accent == p.accent && s.accent2 == p.accent2,
                        onTap: () => _up((x) => x.copyWith(accent: p.accent, accent2: p.accent2)),
                      ),
                  ]),
                  _Label('لون من اختيارك'),
                  _Swatches(
                    colors: StudioCatalog.swatches,
                    selected: s.accent,
                    onPick: (c) => _up((x) => x.copyWith(accent: c)),
                  ),
                ]),

                // ---------- الخلفية ----------
                const SheetSectionLabel('الخلفية'),
                _Box(children: [
                  _Label('خلفية التطبيق'),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final b in StudioBackdrop.values)
                      _BackdropTile(
                        style: s.copyWith(backdrop: b),
                        label: b.label,
                        selected: s.backdrop == b,
                        onTap: () => _up((x) => x.copyWith(backdrop: b)),
                      ),
                  ]),
                  _Label('خلفية المحادثات'),
                  ValueListenableBuilder<int>(
                    valueListenable: WallpaperService.index,
                    builder: (context, sel, _) => Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var i = 0; i < WallpaperService.wallpapers.length; i++)
                        _MiniTile(
                          label: WallpaperService.wallpapers[i].name,
                          selected: sel == i,
                          onTap: () => WallpaperService.set(i),
                          child: CustomPaint(
                            painter: WallpaperPainter(WallpaperService.wallpapers[i],
                                dark: Theme.of(context).brightness == Brightness.dark),
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ]),
                  ),
                  _Hint('لكل محادثة خلفيتها الخاصة أيضاً: «المزيد» داخل المحادثة ← استوديو المحادثة'),
                ]),

                // ---------- البطاقات والقوائم ----------
                const SheetSectionLabel('البطاقات والقوائم'),
                _Box(children: [
                  _Label('شكل البطاقات'),
                  _Chips<StudioSurface>(
                    values: StudioSurface.values,
                    current: s.surface,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(surface: v)),
                  ),
                  _Label('الزوايا'),
                  _Chips<StudioRoundness>(
                    values: StudioRoundness.values,
                    current: s.roundness,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(roundness: v)),
                  ),
                  _Label('المسافات'),
                  _Chips<StudioDensity>(
                    values: StudioDensity.values,
                    current: s.density,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(density: v)),
                  ),
                  _Label('قائمة المحادثات'),
                  _Chips<StudioListStyle>(
                    values: StudioListStyle.values,
                    current: s.listStyle,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(listStyle: v)),
                  ),
                  _Label('الصور الشخصية'),
                  _Chips<StudioAvatarShape>(
                    values: StudioAvatarShape.values,
                    current: s.avatarShape,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(avatarShape: v)),
                  ),
                ]),

                // ---------- الأشرطة ----------
                const SheetSectionLabel('الأشرطة'),
                _Box(children: [
                  _Label('الشريط العلوي'),
                  _Chips<StudioAppBar>(
                    values: StudioAppBar.values,
                    current: s.appBar,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(appBar: v)),
                  ),
                  _Label('الشريط السفلي'),
                  _Chips<StudioNav>(
                    values: StudioNav.values,
                    current: s.nav,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(nav: v)),
                  ),
                  _Toggle(
                    title: 'أسماء الأقسام تحت الأيقونات',
                    value: s.navLabels,
                    onChanged: (v) => _up((x) => x.copyWith(navLabels: v)),
                  ),
                  _Label('شريط الكتابة'),
                  _Chips<StudioInput>(
                    values: StudioInput.values,
                    current: s.input,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(input: v)),
                  ),
                ]),

                // ---------- الفقاعات ----------
                const SheetSectionLabel('الفقاعات'),
                _Box(children: [
                  _Label('الشكل'),
                  _Chips<StudioBubbleShape>(
                    values: StudioBubbleShape.values,
                    current: s.bubbleShape,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(bubbleShape: v)),
                  ),
                  _Toggle(
                    title: 'ذيل صغير كفقاعة الكلام',
                    value: s.bubbleTail,
                    onChanged: (v) => _up((x) => x.copyWith(bubbleTail: v)),
                  ),
                  _Label('تعبئة رسائلي'),
                  _Chips<StudioBubbleFill>(
                    values: StudioBubbleFill.values,
                    current: s.bubbleFill,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(bubbleFill: v)),
                  ),
                  _Label('لون رسائلي'),
                  _Swatches(
                    colors: StudioCatalog.swatches,
                    selected: s.ownBubble,
                    autoLabel: 'مثل اللون الأساسي',
                    onPick: (c) => _up((x) => x.copyWith(ownBubble: () => c)),
                    onAuto: () => _up((x) => x.copyWith(ownBubble: () => null)),
                  ),
                  _Label('صبغة رسائل الآخرين'),
                  _Swatches(
                    colors: StudioCatalog.otherTints,
                    selected: s.otherBubble,
                    autoLabel: 'افتراضي',
                    onPick: (c) => _up((x) => x.copyWith(otherBubble: () => c)),
                    onAuto: () => _up((x) => x.copyWith(otherBubble: () => null)),
                  ),
                ]),

                // ---------- الخطوط ----------
                const SheetSectionLabel('الخطوط'),
                _Box(children: [
                  ValueListenableBuilder<double>(
                    valueListenable: FontScaleService.scale,
                    builder: (_, f, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Chips<double>(
                          values: [for (final o in FontScaleService.options) o.$1],
                          current: f,
                          label: (v) => FontScaleService.options
                              .firstWhere((o) => o.$1 == v)
                              .$2,
                          onPick: FontScaleService.set,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('هكذا ستبدو رسائلك',
                              style: TextStyle(color: context.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ]),

                // ---------- الحركة ----------
                const SheetSectionLabel('الحركة'),
                _Box(children: [
                  _Chips<StudioMotion>(
                    values: StudioMotion.values,
                    current: s.motion,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(motion: v)),
                  ),
                  _Hint(switch (s.motion) {
                    StudioMotion.full => 'كل الحركات تعمل: الخلفيات المتحركة و«وصول» والانتقالات.',
                    StudioMotion.reduced => 'حركة هادئة: انتقالات بتلاشٍ بسيط، والخلفيات ثابتة.',
                    StudioMotion.off => 'بلا حركة: مريح للعين ويوفر البطارية.',
                  }),
                ]),

                // ---------- الأيقونة ----------
                const SheetSectionLabel('أيقونة التطبيق'),
                _Box(children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final v in AppIconService.variants)
                      _MiniTile(
                        label: v.label,
                        selected: _icon == v.id,
                        onTap: () => _pickIcon(v.id),
                        child: Image.asset(v.asset, fit: BoxFit.cover),
                      ),
                  ]),
                  if (kIsWeb) _Hint('تغيير الأيقونة متاح في تطبيق أندرويد.'),
                ]),

                // ---------- الإشعارات المنبثقة ----------
                const SheetSectionLabel('الإشعارات المنبثقة'),
                _Box(children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: PushService.enabled,
                    builder: (_, on, __) => _Toggle(
                      title: 'الإشعارات',
                      value: on,
                      onChanged: PushService.setEnabled,
                    ),
                  ),
                  _Label('الشكل داخل التطبيق'),
                  _Chips<StudioBanner>(
                    values: StudioBanner.values,
                    current: s.banner,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(banner: v)),
                  ),
                  if (s.banner != StudioBanner.toast) ...[
                    _Label('المكان'),
                    _Chips<bool>(
                      values: const [true, false],
                      current: s.bannerTop,
                      label: (v) => v ? 'أعلى الشاشة' : 'أسفل الشاشة',
                      onPick: (v) => _up((x) => x.copyWith(bannerTop: v)),
                    ),
                  ],
                  _Label('المدة'),
                  _Chips<int>(
                    values: const [3, 4, 6, 8],
                    current: s.bannerSeconds,
                    label: (v) => '$v ثوانٍ',
                    onPick: (v) => _up((x) => x.copyWith(bannerSeconds: v)),
                  ),
                  _Toggle(
                    title: 'إظهار نص الرسالة',
                    subtitle: 'عند الإيقاف يظهر «رسالة جديدة» فقط',
                    value: s.bannerPreview,
                    onChanged: (v) => _up((x) => x.copyWith(bannerPreview: v)),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: () => WaslBanner.show(
                          'وصول', 'هكذا ستصلك الرسائل وأنت داخل التطبيق 👋'),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('جرّبه الآن'),
                    ),
                  ),
                ]),

                // ---------- شاشة القفل ----------
                const SheetSectionLabel('شاشة القفل'),
                _Box(children: [
                  _Toggle(
                    title: 'شاشة القفل عند فتح التطبيق',
                    subtitle: 'تظهر عند كل فتح وبعد 30 ثانية في الخلفية',
                    value: s.lockOn,
                    onChanged: (v) => _up((x) => x.copyWith(lockOn: v)),
                  ),
                  _Label('الشكل'),
                  _Chips<StudioLock>(
                    values: StudioLock.values,
                    current: s.lockStyle,
                    label: (v) => v.label,
                    onPick: (v) => _up((x) => x.copyWith(lockStyle: v)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: _previewLock,
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('معاينة'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _setupPin,
                      icon: const Icon(Icons.pin_rounded),
                      label: Text(_hasPin ? 'تغيير رمز القفل' : 'ضع رمز قفل'),
                    ),
                    if (_hasPin)
                      TextButton(onPressed: _removePin, child: const Text('إزالة الرمز')),
                  ]),
                  _Hint(_hasPin
                      ? 'الرمز مفعّل: لا يدخل أحد دونه، حتى لو أُطفئت شاشة القفل.'
                      : 'بلا رمز ولا بصمة تُفتح الشاشة بالسحب. للبصمة: الإعدادات ← قفل التطبيق.'),
                ]),

                // ---------- لمسات ----------
                const SheetSectionLabel('لمسات'),
                _Box(children: [
                  _Toggle(
                    title: 'اهتزاز خفيف عند اللمس',
                    value: s.haptics,
                    onChanged: (v) => _up((x) => x.copyWith(haptics: v)),
                  ),
                  _Toggle(
                    title: 'فاتح نهاراً وداكن ليلاً',
                    subtitle: 'يتبدل تلقائياً عند 6 صباحاً و6 مساءً',
                    value: s.autoDayNight,
                    onChanged: (v) => _up((x) => x.copyWith(autoDayNight: v)),
                  ),
                ]),

                // ---------- الأصوات + إعادة الضبط ----------
                const SheetSectionLabel('الأصوات'),
                GlassGroup([
                  SheetTile(
                    icon: Icons.music_note_rounded,
                    color: WaslColors.teal,
                    title: 'استوديو الصوت',
                    subtitle: kIsWeb
                        ? 'متاح في تطبيق الجوال'
                        : 'نغمات الإشعار والرنين، أو اصنع نغمتك',
                    trailing: Icon(Icons.chevron_left_rounded, color: context.textFaint),
                    onTap: kIsWeb
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const VoiceStudioScreen())),
                  ),
                ]),
                const SizedBox(height: 18),
                GlassGroup([
                  SheetTile(
                    icon: Icons.restart_alt_rounded,
                    danger: true,
                    title: 'إعادة الضبط',
                    subtitle: 'أرجع الشكل كما كان أول مرة',
                    onTap: _reset,
                  ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ==================== المعاينة الحية ====================

/// نموذج مصغّر من التطبيق: شريط علوي، محادثتان، فقاعتان، شريط كتابة،
/// وشريط سفلي — يتغير فوراً مع كل اختيار.
class StudioPreview extends StatelessWidget {
  const StudioPreview({super.key, required this.style, this.chat, this.height = 236});
  final StudioStyle style;
  final ChatStyle? chat;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? WaslColors.darkBg : WaslColors.lightBg;
    final look = BubbleLook.resolve(s, chat);
    final otherBase = dark ? WaslColors.darkSurface : WaslColors.lightBubble;
    final surface = dark ? WaslColors.darkSurface : WaslColors.lightSurface;
    final glass = dark ? WaslColors.glass : WaslColors.lightGlass;
    final hair = context.hairline;
    final pureBg = dark ? Colors.black : Colors.white;

    Widget avatar(Color c) => Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c,
            shape: s.avatarShape == StudioAvatarShape.circle
                ? BoxShape.circle
                : BoxShape.rectangle,
            borderRadius: s.avatarShape == StudioAvatarShape.squircle
                ? BorderRadius.circular(8)
                : null,
          ),
        );

    Widget row(String name, Color c, {bool unread = false}) {
      final inner = Row(children: [
        avatar(c),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            Container(
                height: 5,
                width: 70,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                    color: hair, borderRadius: BorderRadius.circular(3))),
          ]),
        ),
        if (unread)
          Container(
            width: 16,
            height: 12,
            decoration: BoxDecoration(
                gradient: s.gradient, borderRadius: BorderRadius.circular(6)),
          ),
      ]);
      if (s.listStyle == StudioListStyle.flat) {
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: inner);
      }
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(6),
        decoration: studioSurfaceDecoration(s, dark: dark, radius: s.r(12)),
        child: inner,
      );
    }

    Widget bubble(bool mine, double w) => Align(
          alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            width: w,
            height: 20,
            decoration: look.decoration(mine: mine, otherBase: otherBase).copyWith(
                borderRadius: _scaleRadius(look.borderRadius(mine: mine), 0.55)),
          ),
        );

    final appBarColor = switch (s.appBar) {
      StudioAppBar.transparent => Colors.transparent,
      StudioAppBar.glass => glass,
      StudioAppBar.solid => surface,
      StudioAppBar.gradient => s.accentColor,
    };

    final navDeco = switch (s.nav) {
      StudioNav.floating => BoxDecoration(
          color: glass,
          borderRadius: BorderRadius.circular(s.r(16)),
          border: Border.all(color: hair)),
      StudioNav.classic => BoxDecoration(
          color: surface, border: Border(top: BorderSide(color: hair))),
      StudioNav.minimal => const BoxDecoration(),
    };

    final inputDeco = switch (s.input) {
      StudioInput.rounded =>
        BoxDecoration(color: glass, borderRadius: BorderRadius.circular(s.r(10))),
      StudioInput.pill => BoxDecoration(color: glass, borderRadius: BorderRadius.circular(20)),
      StudioInput.outlined => BoxDecoration(
          border: Border.all(color: hair), borderRadius: BorderRadius.circular(s.r(10))),
      StudioInput.minimal => BoxDecoration(border: Border(bottom: BorderSide(color: hair))),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: s.backdrop == StudioBackdrop.pure ? pureBg : base,
          border: Border.all(color: hair),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(children: [
          Positioned.fill(
              child: StudioBackdropLayer(style: s, animate: s.backdrop.animated)),
          Row(children: [
            // نصف القائمة
            Expanded(
              child: Column(children: [
                Container(
                  height: 30,
                  color: appBarColor,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('المحادثات',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: s.appBar == StudioAppBar.gradient ? Colors.white : null)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [
                      row('سارة', WaslColors.indigo, unread: true),
                      row('العائلة', WaslColors.teal),
                      row('أحمد', WaslColors.violet),
                    ]),
                  ),
                ),
                Container(
                  height: 30,
                  margin: s.nav == StudioNav.floating
                      ? const EdgeInsets.fromLTRB(6, 0, 6, 6)
                      : EdgeInsets.zero,
                  decoration: navDeco,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(
                              [
                                Icons.chat_bubble_rounded,
                                Icons.groups_2_outlined,
                                Icons.campaign_outlined,
                                Icons.settings_outlined
                              ][i],
                              size: 12,
                              color: i == 0 ? s.accentColor : context.textFaint),
                          if (s.navLabels)
                            Container(
                                width: 12,
                                height: 2,
                                margin: const EdgeInsets.only(top: 2),
                                color: i == 0 ? s.accentColor : hair),
                        ]),
                    ],
                  ),
                ),
              ]),
            ),
            Container(width: 1, color: hair),
            // نصف المحادثة
            Expanded(
              child: Column(children: [
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [
                      bubble(false, 70),
                      bubble(true, 84),
                      bubble(false, 52),
                      bubble(true, 64),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Row(children: [
                    Expanded(child: Container(height: 22, decoration: inputDeco)),
                    const SizedBox(width: 4),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: s.gradient),
                      child: const Icon(Icons.send_rounded, size: 11, color: Colors.white),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
          const PositionedDirectional(
            end: 4,
            top: 0,
            child: IgnorePointer(child: WaslMascot(size: 44, mood: MascotMood.happy)),
          ),
        ]),
      ),
    );
  }

  static BorderRadiusGeometry _scaleRadius(BorderRadiusGeometry r, double k) {
    if (r is BorderRadius) {
      return BorderRadius.only(
        topLeft: r.topLeft * k,
        topRight: r.topRight * k,
        bottomLeft: r.bottomLeft * k,
        bottomRight: r.bottomRight * k,
      );
    }
    if (r is BorderRadiusDirectional) {
      return BorderRadiusDirectional.only(
        topStart: r.topStart * k,
        topEnd: r.topEnd * k,
        bottomStart: r.bottomStart * k,
        bottomEnd: r.bottomEnd * k,
      );
    }
    return r;
  }
}

// ==================== عناصر صغيرة ====================

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassGroup([
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ]);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: context.textSecondary)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, style: TextStyle(fontSize: 12, color: context.textFaint)),
      );
}

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.values,
    required this.current,
    required this.label,
    required this.onPick,
  });
  final List<T> values;
  final T current;
  final String Function(T) label;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v)),
              selected: v == current,
              showCheckmark: false,
              selectedColor: WaslColors.accent.withValues(alpha: 0.25),
              side: BorderSide(
                  color: v == current ? WaslColors.accent : context.hairline),
              labelStyle: TextStyle(
                  fontWeight: v == current ? FontWeight.w800 : FontWeight.w500),
              onSelected: (_) => onPick(v),
            ),
        ],
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: TextStyle(fontSize: 12, color: context.textFaint)),
        value: value,
        onChanged: onChanged,
      );
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.colors,
    required this.selected,
    required this.onPick,
    this.autoLabel,
    this.onAuto,
  });
  final List<int> colors;
  final int? selected;
  final ValueChanged<int> onPick;
  final String? autoLabel;
  final VoidCallback? onAuto;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (onAuto != null)
            ChoiceChip(
              label: Text(autoLabel ?? 'تلقائي'),
              selected: selected == null,
              showCheckmark: false,
              onSelected: (_) => onAuto!(),
            ),
          for (final c in colors)
            Semantics(
              button: true,
              selected: selected == c,
              label: 'لون',
              child: GestureDetector(
                onTap: () => onPick(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: selected == c ? context.textPrimary : Colors.transparent,
                        width: 2.5),
                  ),
                  child: selected == c
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : null,
                ),
              ),
            ),
        ],
      );
}

class _PaletteDot extends StatelessWidget {
  const _PaletteDot({required this.palette, required this.selected, required this.onTap});
  final StudioPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 58,
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(palette.accent), Color(palette.accent2)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                border: Border.all(
                    color: selected ? context.textPrimary : Colors.transparent, width: 2.5),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(palette.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
      );
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: selected ? WaslColors.accent : context.hairline,
                    width: selected ? 2.5 : 1),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
            ),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? WaslColors.accent : context.textSecondary)),
          ]),
        ),
      );
}

class _BackdropTile extends StatelessWidget {
  const _BackdropTile({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final StudioStyle style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = style.backdrop == StudioBackdrop.pure
        ? (dark ? Colors.black : Colors.white)
        : (dark ? WaslColors.darkBg : WaslColors.lightBg);
    return _MiniTile(
      label: label,
      selected: selected,
      onTap: onTap,
      child: Container(
        color: base,
        child: StudioBackdropLayer(style: style, animate: false),
      ),
    );
  }
}


/// إعداد رمز القفل: يُكتب مرتين للتأكيد (4 إلى 6 أرقام)
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  String _cur = '';
  bool _confirm = false;
  String? _err;

  void _key(String d) {
    AppStudioService.tick();
    setState(() {
      _err = null;
      if (d == '<') {
        if (_cur.isNotEmpty) _cur = _cur.substring(0, _cur.length - 1);
      } else if (_cur.length < 6) {
        _cur += d;
      }
    });
    if (_confirm && _cur.length == _first.length) {
      if (_cur == _first) {
        Navigator.of(context).pop(_cur);
      } else {
        AppStudioService.buzz();
        setState(() {
          _err = 'الرمزان غير متطابقين — ابدأ من جديد';
          _confirm = false;
          _first = '';
          _cur = '';
        });
      }
    }
  }

  void _next() {
    if (!AppLockService.validPin(_cur)) {
      setState(() => _err = 'الرمز من 4 إلى 6 أرقام');
      return;
    }
    setState(() {
      _first = _cur;
      _cur = '';
      _confirm = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = context.textPrimary;
    return Scaffold(
      appBar: AppBar(title: const Text('رمز القفل')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 8),
            WaslMascot(size: 110, mood: _err != null ? MascotMood.sad : MascotMood.shy),
            Text(_confirm ? 'اكتبه مرة أخرى للتأكيد' : 'اختر رمزاً من 4 إلى 6 أرقام',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_err ?? 'لا يُحفظ الرمز نفسه — فقط بصمة مشفّرة منه على جهازك',
                style: TextStyle(
                    fontSize: 12.5, color: _err != null ? Colors.redAccent : context.textFaint)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < (_confirm ? _first.length : 6); i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _cur.length ? WaslColors.accent : Colors.transparent,
                    border: Border.all(color: context.hairline),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            PinPad(onKey: _key, color: text),
            if (!_confirm)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                    onPressed: _cur.length >= 4 ? _next : null, child: const Text('التالي')),
              ),
          ]),
        ),
      ),
    );
  }
}
