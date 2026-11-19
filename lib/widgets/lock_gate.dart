import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/app_lock_service.dart';
import '../services/app_studio_service.dart';
import '../services/hijri_service.dart';
import '../theme.dart';
import 'common.dart';
import 'studio_backdrop.dart';
import 'wasl_mascot.dart';

/// شاشة القفل (1.13.0) — فوق التطبيق كله لمن سجّل دخوله:
/// - تظهر عند كل فتح، وعند العودة بعد أكثر من 30 ثانية في الخلفية.
/// - إن فعّلت البصمة أو رمز PIN فهي قفل حقيقي يظهر عند كل عودة،
///   وإلا فهي شاشة ترحيب تُفتح بالسحب.
/// - شكلها وتشغيلها من «استوديو التطبيق ← شاشة القفل».
/// التطبيق يبقى مبنياً تحتها (لا تضيع الشاشة المفتوحة) لكنه محجوب كلياً.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  /// مهلة الخلفية قبل إظهار شاشة الدخول غير المؤمّنة
  static const grace = Duration(seconds: 30);

  /// هل يجب القفل عند العودة؟ (منطق نقي للاختبار)
  static bool shouldLockOnResume({
    required bool signedIn,
    required bool secure,
    required bool lockOn,
    required Duration away,
  }) {
    if (!signedIn) return false;
    if (secure) return away > const Duration(seconds: 1);
    return lockOn && away > grace;
  }

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _bio = false;
  bool _pin = false;
  bool _locked = false;
  bool _authenticating = false;
  bool _unlocking = false;
  DateTime? _awaySince;

  bool get _signedIn => supabase.auth.currentSession != null;
  bool get _secure => _bio || _pin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // فتح بارد: نقفل فوراً لمن سجّل دخوله (بلا انتظار التخزين)
    if (_signedIn && AppStudioService.style.value.lockOn) _locked = true;
    _loadSecurity(initial: true);
  }

  Future<void> _loadSecurity({bool initial = false}) async {
    final bio = await AppLockService.isEnabled();
    final pin = await AppLockService.hasPin();
    if (!mounted) return;
    setState(() {
      _bio = bio;
      _pin = pin;
      if (initial && _signedIn && (bio || pin)) _locked = true;
    });
    if (initial && _locked && bio) _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return; // نافذة البصمة نفسها توقف التطبيق مؤقتاً
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _awaySince ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final since = _awaySince;
    _awaySince = null;
    if (since == null || _locked) return;
    _loadSecurity().then((_) {
      if (!mounted) return;
      if (LockGate.shouldLockOnResume(
        signedIn: _signedIn,
        secure: _secure,
        lockOn: AppStudioService.style.value.lockOn,
        away: DateTime.now().difference(since),
      )) {
        setState(() {
          _locked = true;
          _unlocking = false;
        });
        if (_bio) _authenticate();
      }
    });
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final ok = await AppLockService.authenticate();
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (ok) _unlock();
  }

  void _unlock() {
    if (_unlocking) return;
    AppStudioService.thump();
    setState(() => _unlocking = true);
    final ms = AppStudioService.motionOn ? 700 : 0;
    Future<void>.delayed(Duration(milliseconds: ms), () {
      if (mounted) {
        setState(() {
          _locked = false;
          _unlocking = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked && _signedIn;
    return Stack(children: [
      // التطبيق تحت القفل: بلا لمس ولا تركيز ولا حركة ولا قارئ شاشة
      IgnorePointer(
        ignoring: locked,
        child: ExcludeFocus(
          excluding: locked,
          child: ExcludeSemantics(
            excluding: locked,
            child: TickerMode(enabled: !locked || _unlocking, child: widget.child),
          ),
        ),
      ),
      if (locked)
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _unlocking ? 0 : 1,
            duration: Duration(
                milliseconds: AppStudioService.motionOn ? 450 : 0),
            curve: const Interval(0.35, 1),
            child: WaslLockScreen(
              pin: _pin,
              bio: _bio,
              busy: _authenticating,
              unlocking: _unlocking,
              onBiometric: _authenticate,
              onUnlock: _unlock,
            ),
          ),
        ),
    ]);
  }
}

/// تحية حسب الساعة (منطق نقي للاختبار)
String lockGreeting(int hour) {
  if (hour >= 4 && hour < 12) return 'صباح الخير';
  if (hour >= 12 && hour < 17) return 'نهارك سعيد';
  if (hour >= 17 && hour < 21) return 'مساء الخير';
  return 'طابت ليلتك';
}

/// تلميح غير المقروء دون كشف أي محتوى
String unreadHint(int n) => switch (n) {
      <= 0 => 'لا جديد — كل شيء هادئ',
      1 => 'لديك رسالة واحدة لم تُقرأ',
      2 => 'لديك رسالتان لم تُقرآ',
      <= 10 => 'لديك $n رسائل لم تُقرأ',
      _ => 'لديك $n رسالة لم تُقرأ',
    };

class WaslLockScreen extends StatefulWidget {
  const WaslLockScreen({
    super.key,
    required this.pin,
    required this.bio,
    required this.busy,
    required this.unlocking,
    required this.onBiometric,
    required this.onUnlock,
    this.preview,
  });

  final bool pin;
  final bool bio;
  final bool busy;
  final bool unlocking;
  final VoidCallback onBiometric;
  final VoidCallback onUnlock;

  /// نمط للمعاينة من الاستوديو (null = النمط الحالي)
  final StudioStyle? preview;

  @override
  State<WaslLockScreen> createState() => _WaslLockScreenState();
}

class _WaslLockScreenState extends State<WaslLockScreen>
    with SingleTickerProviderStateMixin {
  static String? _cachedName;
  final _gaze = ValueNotifier<Offset?>(null);
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  bool _awake = false;
  bool _wrong = false;
  String _entered = '';
  String? _name = _cachedName;
  int _len = 4;

  @override
  void initState() {
    super.initState();
    if (_name == null) _loadName();
    if (widget.pin) {
      AppLockService.pinLength().then((v) {
        if (mounted) setState(() => _len = v);
      });
    }
  }

  Future<void> _loadName() async {
    final u = supabase.auth.currentUser;
    if (u == null) return;
    String? n = u.userMetadata?['username'] as String?;
    try {
      final p = await supabase
          .from('profiles')
          .select('display_name, username')
          .eq('id', u.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      n = (p?['display_name'] as String?)?.trim().isNotEmpty == true
          ? p!['display_name'] as String
          : (p?['username'] as String? ?? n);
    } catch (_) {}
    if (n != null && mounted) {
      setState(() => _name = _cachedName = n!.split(' ').first);
    }
  }

  @override
  void dispose() {
    _gaze.dispose();
    _shake.dispose();
    super.dispose();
  }

  MascotMood get _mood {
    if (widget.unlocking) return MascotMood.celebrating;
    if (_wrong) return MascotMood.sad;
    if (widget.busy) return MascotMood.thinking;
    if (!_awake) return MascotMood.sleepy;
    if (_entered.isNotEmpty) return MascotMood.shy;
    return MascotMood.happy;
  }

  void _wake() {
    if (!_awake) setState(() => _awake = true);
  }

  Future<void> _digit(String d) async {
    if (widget.unlocking) return;
    AppStudioService.tick();
    _wake();
    if (d == '<') {
      if (_entered.isNotEmpty) {
        setState(() => _entered = _entered.substring(0, _entered.length - 1));
      }
      return;
    }
    if (_entered.length >= _len) return;
    setState(() {
      _entered += d;
      _wrong = false;
    });
    if (_entered.length == _len) {
      final ok = await AppLockService.checkPin(_entered);
      if (!mounted) return;
      ok ? widget.onUnlock() : _fail();
    }
  }

  void _fail() {
    AppStudioService.buzz();
    setState(() {
      _wrong = true;
      _entered = '';
    });
    if (AppStudioService.motionOn) _shake.forward(from: 0);
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _wrong = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StudioStyle>(
      valueListenable: AppStudioService.style,
      builder: (context, current, _) {
        final s = widget.preview ?? current;
        final kind = s.lockStyle;
        final dark = kind == StudioLock.night ||
            Theme.of(context).brightness == Brightness.dark;
        final bgStyle = s.copyWith(
          backdrop: switch (kind) {
            StudioLock.aurora || StudioLock.glass => StudioBackdrop.aurora,
            StudioLock.mascot => StudioBackdrop.soft,
            StudioLock.minimal => StudioBackdrop.plain,
            StudioLock.night => StudioBackdrop.stars,
          },
        );
        final content = _content(context, s, kind);
        return Material(
            color: dark ? const Color(0xFF05070D) : WaslColors.lightBg,
            child: Listener(
              onPointerDown: (e) {
                _wake();
                _gaze.value = e.position;
              },
              onPointerMove: (e) => _gaze.value = e.position,
              onPointerUp: (_) => Future<void>.delayed(
                  const Duration(milliseconds: 800), () {
                if (mounted) _gaze.value = null;
              }),
              child: Stack(children: [
                if (bgStyle.backdrop != StudioBackdrop.plain)
                  Positioned.fill(
                    child: Theme(
                      data: ThemeData(
                          brightness: dark ? Brightness.dark : Brightness.light),
                      child: StudioBackdropLayer(style: bgStyle),
                    ),
                  ),
                SafeArea(
                  child: kind == StudioLock.glass
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: (dark ? Colors.white : Colors.black)
                                        .withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(32),
                                    border: Border.all(
                                        color: (dark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.12)),
                                  ),
                                  child: content,
                                ),
                              ),
                            ),
                          ),
                        )
                      : content,
                ),
              ]),
            ),
        );
      },
    );
  }

  Widget _content(BuildContext context, StudioStyle s, StudioLock kind) {
    final text = Theme.of(context).brightness == Brightness.dark || kind == StudioLock.night
        ? Colors.white
        : WaslColors.ink;
    final soft = text.withValues(alpha: 0.7);
    final mascotSize = kind == StudioLock.mascot ? 190.0 : (kind == StudioLock.minimal ? 96.0 : 140.0);
    return ValueListenableBuilder<int>(
      valueListenable: AppStudioService.minuteTick,
      builder: (context, _, __) {
        final now = DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        final greet = '${lockGreeting(now.hour)}${_name == null ? '' : '، $_name'}';
        final clock = Text('$hh:$mm',
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: kind == StudioLock.mascot ? 44 : 68,
                fontWeight: kind == StudioLock.minimal ? FontWeight.w200 : FontWeight.w300,
                letterSpacing: 2,
                height: 1.0,
                color: text));
        return LayoutBuilder(builder: (context, c) {
          final tight = c.maxHeight < 620;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(children: [
                      clock,
                      const SizedBox(height: 6),
                      Text(HijriService.formatBoth(now),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: soft)),
                    ]),
                  ),
                  Column(children: [
                    AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                            math.sin(_shake.value * math.pi * 6) * 14 * (1 - _shake.value),
                            0),
                        child: child,
                      ),
                      child: WaslMascot(
                        size: tight ? mascotSize * 0.75 : mascotSize,
                        mood: _mood,
                        gaze: _gaze,
                        onTap: _wake,
                        color: kind == StudioLock.night ? const Color(0xFF6366F1) : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(greet,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800, color: text)),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: UnreadHub.total,
                      builder: (_, n, __) => Text(unreadHint(n),
                          style: TextStyle(fontSize: 13.5, color: soft)),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                    child: _unlockControl(context, s, text),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _unlockControl(BuildContext context, StudioStyle s, Color text) {
    if (widget.pin) {
      final cd = AppLockService.cooldownSeconds;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
            cd > 0
                ? 'محاولات كثيرة — انتظر $cd ثانية'
                : (_wrong ? 'رمز غير صحيح' : 'أدخل رمز القفل'),
            style: TextStyle(
                color: _wrong || cd > 0 ? Colors.redAccent : text.withValues(alpha: 0.8),
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _len; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _entered.length ? s.accentColor : Colors.transparent,
                border: Border.all(color: text.withValues(alpha: 0.6)),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        PinPad(
          onKey: _digit,
          color: text,
          extra: widget.bio
              ? IconButton(
                  // بلا تلميح: شاشة القفل فوق المتصفّح ولا طبقة تلميحات هناك
                  onPressed: widget.busy ? null : widget.onBiometric,
                  icon: Icon(Icons.fingerprint_rounded, size: 30, color: text),
                )
              : null,
        ),
      ]);
    }
    if (widget.bio) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: s.accentColor,
            minimumSize: const Size(220, 54),
            shape: const StadiumBorder()),
        onPressed: widget.busy ? null : widget.onBiometric,
        icon: const Icon(Icons.fingerprint_rounded),
        label: Text(widget.busy ? 'بانتظار التحقق…' : 'افتح بالبصمة'),
      );
    }
    return SlideToEnter(
      gradient: s.gradient,
      color: text,
      onDone: widget.onUnlock,
      onStart: _wake,
    );
  }
}

/// لوحة أرقام دائرية (القفل وإعداد الرمز)
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.onKey, required this.color, this.extra});
  final ValueChanged<String> onKey;
  final Color color;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox.square(
            dimension: 64,
            child: Material(
              color: color.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onKey(d),
                child: Center(
                  child: d == '<'
                      ? Icon(Icons.backspace_outlined, color: color)
                      : Text(d,
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w600, color: color)),
                ),
              ),
            ),
          ),
        );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox.square(dimension: 76, child: Center(child: extra)),
          key('0'),
          key('<'),
        ]),
      ]),
    );
  }
}

/// «اسحب للدخول»: مقبض يُسحب لنهاية الشريط مع توهّج متحرك
class SlideToEnter extends StatefulWidget {
  const SlideToEnter({
    super.key,
    required this.gradient,
    required this.color,
    required this.onDone,
    this.onStart,
  });
  final LinearGradient gradient;
  final Color color;
  final VoidCallback onDone;
  final VoidCallback? onStart;

  @override
  State<SlideToEnter> createState() => _SlideToEnterState();
}

class _SlideToEnterState extends State<SlideToEnter> {
  double _p = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    const h = 62.0;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: 'اسحب للدخول',
      onTap: widget.onDone,
      child: LayoutBuilder(builder: (context, c) {
        final w = math.min(c.maxWidth, 360.0);
        final travel = w - h;
        return SizedBox(
          width: w,
          height: h,
          child: GestureDetector(
            onHorizontalDragStart: (_) => widget.onStart?.call(),
            onHorizontalDragUpdate: (d) {
              if (_done) return;
              final dx = rtl ? -d.delta.dx : d.delta.dx;
              setState(() => _p = (_p + dx / travel).clamp(0.0, 1.0));
            },
            onHorizontalDragEnd: (_) {
              if (_done) return;
              if (_p > 0.8) {
                setState(() {
                  _p = 1;
                  _done = true;
                });
                widget.onDone();
              } else {
                setState(() => _p = 0);
              }
            },
            onTap: () => setState(() => _p = _p == 0 ? 0.12 : 0),
            child: Stack(children: [
              Container(
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(h / 2),
                  border: Border.all(color: widget.color.withValues(alpha: 0.18)),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: (1 - _p * 1.6).clamp(0.0, 1.0),
                  child: Text('اسحب للدخول  ${rtl ? '‹‹' : '››'}',
                      style: TextStyle(
                          color: widget.color.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ),
              AnimatedPositionedDirectional(
                duration: Duration(milliseconds: _p == 0 ? 220 : 0),
                curve: Curves.easeOutBack,
                start: _p * travel,
                top: 0,
                child: Container(
                  width: h,
                  height: h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.gradient,
                    boxShadow: [
                      BoxShadow(
                          color: widget.gradient.colors.first.withValues(alpha: 0.45),
                          blurRadius: 16),
                    ],
                  ),
                  child: Icon(
                      _done ? Icons.check_rounded : Icons.lock_open_rounded,
                      color: Colors.white),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
