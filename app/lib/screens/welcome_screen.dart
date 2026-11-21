import 'package:material_ui/material_ui.dart';

import '../services/app_studio_service.dart';
import '../theme.dart';
import '../widgets/studio_backdrop.dart';
import '../widgets/wasl_mascot.dart';

/// جولة الترحيب (1.13.0): تظهر أول مرة فقط قبل الدخول، ويمكن إعادتها من
/// الإعدادات. أربع صفحات تُسحب بالإصبع، و«وصول» يتفاعل مع كل صفحة ومع لمستك،
/// وآخر صفحة تختار فيها سمة التطبيق وتراها تتغير أمامك مباشرة.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone, this.replay = false});

  final Future<void> Function() onDone;

  /// إعادة الجولة من الإعدادات (تُغلق بالرجوع بدل الانتقال للدخول)
  final bool replay;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomePage {
  const _WelcomePage(this.title, this.body, this.mood, this.icon);
  final String title;
  final String body;
  final MascotMood mood;
  final IconData icon;
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _pages = <_WelcomePage>[
    _WelcomePage('مرحباً بك في وصل',
        'أنا «وصول»، رفيقك هنا.\nمحادثات ومكالمات وقنوات ومجتمعات في تطبيق واحد سريع وخفيف.',
        MascotMood.waving, Icons.waving_hand_rounded),
    _WelcomePage('محادثات آمنة ودرع وصل',
        'رسائلك الخاصة مشفّرة بينك وبين من تكلّمه فقط — حتى نحن لا نراها.\nو«درع وصل» يحميك من الابتزاز والتهديد.',
        MascotMood.shy, Icons.shield_rounded),
    _WelcomePage('ذكاء يساعدك',
        'ملخص لما فاتك، ردود سريعة، ترجمة فورية، وصياغة بأسلوبك — والكثير منه يعمل على جوالك نفسه.',
        MascotMood.thinking, Icons.auto_awesome_rounded),
    _WelcomePage('اجعله على ذوقك',
        'اختر سمة تعجبك الآن، ويمكنك تغيير كل شيء لاحقاً من «استوديو التطبيق».',
        MascotMood.happy, Icons.palette_rounded),
  ];

  final _ctrl = PageController();
  final _gaze = ValueNotifier<Offset?>(null);
  double _page = 0;
  bool _cheer = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _page = _ctrl.page ?? 0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _gaze.dispose();
    super.dispose();
  }

  int get _index => _page.round().clamp(0, _pages.length - 1);

  MascotMood get _mood {
    if (_cheer) return MascotMood.celebrating;
    return _pages[_index].mood;
  }

  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    await widget.onDone();
    if (widget.replay && mounted) Navigator.of(context).maybePop();
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    final motion = AppStudioService.style.value.motion;
    if (motion == StudioMotion.off) {
      _ctrl.jumpToPage(_index + 1);
    } else {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _pickTheme(StudioTheme t) async {
    await AppStudioService.applyTheme(t);
    if (t.mode != null) await ThemeService.set(t.mode!);
    if (!mounted) return;
    setState(() => _cheer = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _cheer = false);
  }

  void _pokeMascot() {
    setState(() => _cheer = true);
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _cheer = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
    final mascotSize = (h * 0.26).clamp(140.0, 230.0);
    return Scaffold(
      body: Listener(
        onPointerDown: (e) => _gaze.value = e.position,
        onPointerMove: (e) => _gaze.value = e.position,
        onPointerUp: (_) => Future<void>.delayed(
            const Duration(milliseconds: 900), () => _gaze.value = null),
        child: Stack(children: [
          // شفق متحرك بألوان السمة الحالية
          Positioned.fill(
            child: ValueListenableBuilder<StudioStyle>(
              valueListenable: AppStudioService.style,
              builder: (_, s, _) => StudioBackdropLayer(
                  style: s.copyWith(backdrop: StudioBackdrop.aurora)),
            ),
          ),
          SafeArea(
            child: Column(children: [
              // شريط علوي: تخطي
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(children: [
                  ShaderMask(
                    shaderCallback: (r) => WaslColors.gradient.createShader(r),
                    child: const Text('وصل شات',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  const Spacer(),
                  if (_index < _pages.length - 1)
                    TextButton(
                      onPressed: _finish,
                      child: Text('تخطي',
                          style: TextStyle(
                              color: context.textSecondary, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
              // الشخصية: تنزاح مع السحب (تأثير عمق)
              SizedBox(
                height: mascotSize + 30,
                child: Center(
                  child: Transform.translate(
                    offset: Offset((_page - _page.roundToDouble()) * -60, 0),
                    child: WaslMascot(
                      size: mascotSize,
                      mood: _mood,
                      gaze: _gaze,
                      onTap: _pokeMascot,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    final delta = (i - _page).clamp(-1.0, 1.0);
                    return Opacity(
                      opacity: (1 - delta.abs() * 0.8).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(delta * 80, 0),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
                          child: Column(children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                  gradient: WaslColors.gradient,
                                  borderRadius: BorderRadius.circular(16)),
                              child: Icon(p.icon, color: Colors.white, size: 26),
                            ),
                            const SizedBox(height: 14),
                            Text(p.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Text(p.body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.6,
                                    color: context.textSecondary)),
                            if (i == _pages.length - 1) ...[
                              const SizedBox(height: 18),
                              _ThemeChooser(onPick: _pickTheme),
                            ],
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // النقاط + زر التالي
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                child: Row(children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsetsDirectional.only(end: 6),
                      width: i == _index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: i == _index ? WaslColors.gradient : null,
                        color: i == _index ? null : context.hairline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  SizedBox(
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: WaslColors.gradient,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                              color: WaslColors.accent.withValues(alpha: 0.4),
                              blurRadius: 18,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      child: TextButton(
                        onPressed: _next,
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 26)),
                        child: Text(
                            _index == _pages.length - 1
                                ? (widget.replay ? 'تم' : 'ابدأ الآن')
                                : 'التالي',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// اختيار سمة جاهزة بتغيير مباشر
class _ThemeChooser extends StatelessWidget {
  const _ThemeChooser({required this.onPick});
  final ValueChanged<StudioTheme> onPick;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StudioStyle>(
      valueListenable: AppStudioService.style,
      builder: (context, s, _) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in StudioCatalog.themes)
            StudioThemeChip(
              theme: t,
              selected: (s.themeId ?? (s.isDefault ? 'wasl_night' : null)) == t.id,
              onTap: () => onPick(t),
            ),
        ],
      ),
    );
  }
}

/// شريحة سمة: دائرة بتدرج ألوانها + اسمها (تُستخدم في الترحيب والاستوديو)
class StudioThemeChip extends StatelessWidget {
  const StudioThemeChip(
      {super.key, required this.theme, required this.selected, required this.onTap});
  final StudioTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = theme.style;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? st.accentColor.withValues(alpha: 0.16) : context.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? st.accentColor : context.hairline,
              width: selected ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: st.gradient,
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : null,
          ),
          const SizedBox(height: 6),
          Text(theme.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ]),
      ),
    );
  }
}
