import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_studio_service.dart';
import '../theme.dart';

/// خلفية التطبيق المختارة من «استوديو التطبيق» (1.13.0) — تُرسم خلف الصفحة
/// كاملة. الشفق والنجوم يتحركان بهدوء، ويتوقفان عند تخفيف الحركة أو إيقافها.
class StudioBackdropView extends StatelessWidget {
  const StudioBackdropView({super.key, required this.child, this.preview});
  final Widget child;

  /// لمعاينة خلفية دون تطبيقها (الاستوديو)
  final StudioStyle? preview;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StudioStyle>(
      valueListenable: AppStudioService.style,
      builder: (context, s, _) {
        final st = preview ?? s;
        if (st.backdrop == StudioBackdrop.plain) return child;
        return Stack(fit: StackFit.passthrough, children: [
          Positioned.fill(child: StudioBackdropLayer(style: st)),
          child,
        ]);
      },
    );
  }
}

/// طبقة الرسم وحدها (تُستخدم في المعاينات المصغّرة أيضاً)
class StudioBackdropLayer extends StatefulWidget {
  const StudioBackdropLayer({super.key, required this.style, this.animate = true});
  final StudioStyle style;
  final bool animate;

  @override
  State<StudioBackdropLayer> createState() => _StudioBackdropLayerState();
}

class _StudioBackdropLayerState extends State<StudioBackdropLayer>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _shouldAnimate =>
      widget.animate &&
      widget.style.backdrop.animated &&
      widget.style.motion == StudioMotion.full;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StudioBackdropLayer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_shouldAnimate) {
      _c ??= AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();
    } else {
      _c?.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = _c;
    return RepaintBoundary(
      child: CustomPaint(
        painter: StudioBackdropPainter(
          kind: widget.style.backdrop,
          accent: widget.style.accentColor,
          accent2: widget.style.accent2Color,
          dark: dark,
          t: c,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class StudioBackdropPainter extends CustomPainter {
  StudioBackdropPainter({
    required this.kind,
    required this.accent,
    required this.accent2,
    required this.dark,
    this.t,
  }) : super(repaint: t);

  final StudioBackdrop kind;
  final Color accent;
  final Color accent2;
  final bool dark;
  final Animation<double>? t;

  static final List<Offset> _stars = () {
    final r = math.Random(7);
    return List.generate(110, (_) => Offset(r.nextDouble(), r.nextDouble()));
  }();

  void _blob(Canvas canvas, Offset c, double radius, Color color) {
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: radius)),
    );
  }

  void _linear(Canvas canvas, Rect rect, List<Color> colors) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: colors,
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = dark ? WaslColors.darkBg : WaslColors.lightBg;
    canvas.drawRect(rect, Paint()..color = base);
    final w = size.width, h = size.height;
    final a = dark ? 1.0 : 0.6; // شدة الألوان على الفاتح أخف للحفاظ على التباين
    final v = t?.value ?? 0.0;
    final ph = v * 2 * math.pi;
    switch (kind) {
      case StudioBackdrop.plain:
      case StudioBackdrop.pure:
        break;
      case StudioBackdrop.soft:
        _blob(canvas, Offset(w * 0.9, h * 0.08), w * 0.9,
            accent.withValues(alpha: 0.20 * a));
        _blob(canvas, Offset(w * 0.05, h * 0.95), w * 0.9,
            accent2.withValues(alpha: 0.16 * a));
      case StudioBackdrop.aurora:
        _blob(canvas, Offset(w * (0.75 + 0.18 * math.sin(ph)), h * (0.15 + 0.06 * math.cos(ph))),
            w * 0.85, accent.withValues(alpha: 0.30 * a));
        _blob(canvas, Offset(w * (0.2 + 0.2 * math.cos(ph * 1.0)), h * (0.45 + 0.08 * math.sin(ph))),
            w * 0.8, accent2.withValues(alpha: 0.24 * a));
        _blob(canvas, Offset(w * (0.6 + 0.15 * math.sin(ph + 2)), h * (0.85 + 0.05 * math.cos(ph))),
            w * 0.75, const Color(0xFFA855F7).withValues(alpha: 0.20 * a));
      case StudioBackdrop.stars:
        if (dark) {
          _linear(canvas, rect, const [Color(0xFF0A0F24), Color(0xFF04060F)]);
        } else {
          _linear(canvas, rect, const [Color(0xFFE6ECFA), Color(0xFFF6F8FD)]);
        }
        _blob(canvas, Offset(w * 0.85, h * 0.1), w * 0.6, accent.withValues(alpha: 0.18 * a));
        final p = Paint();
        for (var i = 0; i < _stars.length; i++) {
          final s = _stars[i];
          final tw = 0.5 + 0.5 * math.sin(ph * 3 + i * 1.7);
          p.color = (dark ? Colors.white : accent)
              .withValues(alpha: (dark ? 0.25 : 0.18) + (dark ? 0.55 : 0.2) * tw);
          canvas.drawCircle(Offset(s.dx * w, s.dy * h), (i % 3 == 0 ? 1.6 : 1.0), p);
        }
      case StudioBackdrop.dusk:
        _linear(canvas, rect, dark
            ? const [Color(0xFF2A1438), Color(0xFF120B1E), Color(0xFF0B0F1A)]
            : const [Color(0xFFFCE7F3), Color(0xFFF5EEFF), Color(0xFFF2F4FA)]);
        _blob(canvas, Offset(w * 0.1, h * 0.9), w * 0.8,
            const Color(0xFFF97316).withValues(alpha: 0.16 * a));
      case StudioBackdrop.ocean:
        _linear(canvas, rect, dark
            ? const [Color(0xFF062A3A), Color(0xFF071A2B), Color(0xFF0B0F1A)]
            : const [Color(0xFFE0F2FE), Color(0xFFECFEFF), Color(0xFFF2F4FA)]);
        _blob(canvas, Offset(w * 0.9, h * 0.2), w * 0.7,
            const Color(0xFF14B8A6).withValues(alpha: 0.14 * a));
      case StudioBackdrop.forest:
        _linear(canvas, rect, dark
            ? const [Color(0xFF07261C), Color(0xFF0A1A14), Color(0xFF0B0F1A)]
            : const [Color(0xFFDCFCE7), Color(0xFFF0FDF4), Color(0xFFF2F4FA)]);
        _blob(canvas, Offset(w * 0.15, h * 0.15), w * 0.7,
            const Color(0xFF65A30D).withValues(alpha: 0.12 * a));
      case StudioBackdrop.sand:
        _linear(canvas, rect, dark
            ? const [Color(0xFF2B2113), Color(0xFF1A140C), Color(0xFF0F0D0A)]
            : const [Color(0xFFFDF3E1), Color(0xFFF8EEDC), Color(0xFFF5F0E8)]);
        _blob(canvas, Offset(w * 0.85, h * 0.12), w * 0.6,
            const Color(0xFFF59E0B).withValues(alpha: 0.14 * a));
      case StudioBackdrop.dots:
        const gap = 24.0;
        final p = Paint()..color = accent.withValues(alpha: dark ? 0.16 : 0.18);
        for (double y = gap / 2; y < h; y += gap) {
          for (double x = gap / 2; x < w; x += gap) {
            canvas.drawCircle(Offset(x, y), 1.3, p);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant StudioBackdropPainter old) =>
      old.kind != kind ||
      old.accent != accent ||
      old.accent2 != accent2 ||
      old.dark != dark ||
      old.t != t;
}

/// زخرفة سطح حسب اختيار «شكل البطاقات» — مشتركة بين المعاينة والقوائم
BoxDecoration studioSurfaceDecoration(StudioStyle s, {required bool dark, required double radius}) {
  final glass = dark ? WaslColors.glass : WaslColors.lightGlass;
  final surface = dark ? WaslColors.darkSurface : WaslColors.lightSurface;
  final hair = dark ? Colors.white24 : Colors.black.withValues(alpha: 0.10);
  return switch (s.surface) {
    StudioSurface.glass => BoxDecoration(
        color: glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: hair.withValues(alpha: 0.5))),
    StudioSurface.solid =>
      BoxDecoration(color: surface, borderRadius: BorderRadius.circular(radius)),
    StudioSurface.outlined => BoxDecoration(
        borderRadius: BorderRadius.circular(radius), border: Border.all(color: hair)),
    StudioSurface.elevated => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ]),
  };
}



/// احتفال قصير بقصاصات ملوّنة فوق الشاشة (أول رسالة في محادثة جديدة).
/// يتخطى نفسه عند تخفيف الحركة أو إيقافها، ولا يعترض اللمس.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.onDone});
  final VoidCallback onDone;

  static void show(BuildContext context) {
    if (!AppStudioService.motionFull) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry e;
    e = OverlayEntry(
      builder: (_) => ConfettiBurst(onDone: () {
        try {
          e.remove();
        } catch (_) {}
      }),
    );
    overlay.insert(e);
  }

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ConfettiPainter(_c, AppStudioService.style.value),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.s) : super(repaint: t);
  final Animation<double> t;
  final StudioStyle s;
  static final _r = math.Random(3);
  static final _bits = List.generate(
      46, (_) => (_r.nextDouble(), _r.nextDouble(), _r.nextDouble(), _r.nextInt(5)));

  @override
  void paint(Canvas canvas, Size size) {
    final v = Curves.easeOut.transform(t.value);
    final colors = [
      s.accentColor,
      s.accent2Color,
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
      const Color(0xFF22C55E),
    ];
    final origin = Offset(size.width / 2, size.height * 0.82);
    for (final (a, sp, rot, ci) in _bits) {
      final ang = -math.pi / 2 + (a - 0.5) * 2.2;
      final dist = (0.35 + sp * 0.55) * size.height * v;
      final p = origin +
          Offset(math.cos(ang) * dist, math.sin(ang) * dist + 260 * t.value * t.value);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(rot * 12 * t.value);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4),
          Paint()..color = colors[ci].withValues(alpha: (1 - t.value).clamp(0.0, 1.0)));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => false;
}
