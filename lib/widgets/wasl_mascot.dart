import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_studio_service.dart';

/// «وصول» — شخصية وصل المتحركة (1.13.0)
///
/// مستوحاة من شعار التطبيق: فقاعة محادثة زرقاء تدور حولها حلقة كالكوكب،
/// والنقاط الثلاث صارت وجهاً: عينان تنظران نحو لمستك ونقطة وسطى تتحول
/// إلى فم يتغير بالمزاج. كلها مرسومة بـCustomPainter بلا أي ملفات حركة.
///
/// تحترم «مستوى الحركة» في الاستوديو: «خفيفة» تُبقي الرمش وردّ الفعل فقط،
/// و«متوقفة» ترسم صورة ثابتة بلا أي مؤقت.
enum MascotMood {
  idle,
  happy,
  thinking,
  waving,
  sleepy,
  celebrating,
  sad,

  /// يغطي عينيه (أثناء كتابة كلمة المرور)
  shy,

  /// ينظر باهتمام (أثناء كتابة البريد)
  curious,
}

class WaslMascot extends StatefulWidget {
  const WaslMascot({
    super.key,
    this.size = 160,
    this.mood = MascotMood.idle,
    this.look,
    this.gaze,
    this.onTap,
    this.color,
  });

  final double size;
  final MascotMood mood;

  /// اتجاه نظر ثابت (-1..1 لكل محور) يتقدم على [gaze]
  final Offset? look;

  /// موضع لمسة عامة على الشاشة (إحداثيات عامة) — العينان تتبعانها
  final ValueListenable<Offset?>? gaze;
  final VoidCallback? onTap;

  /// لون الجسم (افتراضياً أزرق الشعار)
  final Color? color;

  @override
  State<WaslMascot> createState() => _WaslMascotState();
}


class _WaslMascotState extends State<WaslMascot> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
  late final AnimationController _tap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  Timer? _blinkTimer;
  Offset _gaze = Offset.zero;
  Offset _gazeTarget = Offset.zero;
  final _rnd = math.Random();

  StudioMotion get _motion => AppStudioService.style.value.motion;

  @override
  void initState() {
    super.initState();
    _loop.addListener(_smoothGaze);
    widget.gaze?.addListener(_onGaze);
    AppStudioService.style.addListener(_syncMotion);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant WaslMascot old) {
    super.didUpdateWidget(old);
    if (old.gaze != widget.gaze) {
      old.gaze?.removeListener(_onGaze);
      widget.gaze?.addListener(_onGaze);
    }
    if (old.mood != widget.mood &&
        widget.mood == MascotMood.celebrating &&
        _motion != StudioMotion.off) {
      _tap.forward(from: 0);
    }
  }

  void _syncMotion() {
    final m = _motion;
    if (m == StudioMotion.full) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
    if (m == StudioMotion.off) {
      _blinkTimer?.cancel();
      _blinkTimer = null;
    } else if (_blinkTimer == null) {
      _scheduleBlink();
    }
    if (mounted) setState(() {});
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2200 + _rnd.nextInt(3200)), () async {
      if (!mounted) return;
      await _blink.forward(from: 0);
      if (!mounted) return;
      await _blink.reverse();
      if (mounted && _motion != StudioMotion.off) _scheduleBlink();
    });
  }

  void _onGaze() {
    final p = widget.gaze?.value;
    final box = context.findRenderObject() as RenderBox?;
    if (p == null || box == null || !box.hasSize) {
      _gazeTarget = Offset.zero;
    } else {
      final c = box.localToGlobal(box.size.center(Offset.zero));
      final d = p - c;
      final len = d.distance;
      final reach = widget.size * 1.6;
      _gazeTarget = len < 1 ? Offset.zero : d / len * (len / reach).clamp(0.0, 1.0);
    }
    if (!_loop.isAnimating) setState(() => _gaze = _gazeTarget);
  }

  void _smoothGaze() {
    final target = widget.look ?? _gazeTarget;
    _gaze = Offset.lerp(_gaze, target, 0.12)!;
  }

  void _handleTap() {
    if (_motion != StudioMotion.off) _tap.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    widget.gaze?.removeListener(_onGaze);
    AppStudioService.style.removeListener(_syncMotion);
    _loop.dispose();
    _blink.dispose();
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    return Semantics(
      label: 'وصول، شخصية وصل',
      button: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _blink, _tap]),
              builder: (context, _) => CustomPaint(
                painter: MascotPainter(
                  mood: widget.mood,
                  time: _loop.value,
                  blink: _blink.value,
                  tap: _tap.isAnimating ? _tap.value : 0,
                  gaze: _loop.isAnimating ? _gaze : (look ?? _gaze),
                  color: widget.color ?? const Color(0xFF3B82F6),
                  still: _motion != StudioMotion.full,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رسام الشخصية — عام ليُختبر رسمه في كل الأمزجة
class MascotPainter extends CustomPainter {
  MascotPainter({
    required this.mood,
    this.time = 0,
    this.blink = 0,
    this.tap = 0,
    this.gaze = Offset.zero,
    this.color = const Color(0xFF3B82F6),
    this.still = false,
  });

  final MascotMood mood;

  /// 0..1 دورة الحركة المستمرة
  final double time;

  /// 0..1 إغلاق العينين للرمش
  final double blink;

  /// 0..1 تقدم ردّ فعل اللمس (قفزة + غمزة)
  final double tap;
  final Offset gaze;
  final Color color;
  final bool still;

  static const _ink = Color(0xFF0B1530);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide / 100;
    final ph = time * 2 * math.pi;
    // طفو هادئ + قفزة اللمس + قفز الاحتفال
    var dy = still ? 0.0 : math.sin(ph) * 2.6 * u;
    final bounce = math.sin(tap * math.pi);
    dy -= bounce * 9 * u;
    if (mood == MascotMood.celebrating && !still) {
      dy -= (math.sin(ph * 4).abs()) * 5 * u;
    }
    final squash = 1 + 0.08 * math.sin(tap * math.pi * 2) * (1 - tap);
    final center = Offset(size.width / 2, size.height / 2 + 4 * u + dy);

    // ظل أرضي
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2 + 40 * u),
          width: (34 - bounce * 8) * u,
          height: 5 * u),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * u),
    );

    // توهج خلفي
    canvas.drawCircle(
      center,
      34 * u,
      Paint()
        ..color = color.withValues(alpha: mood == MascotMood.sad ? 0.12 : 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * u),
    );

    final tilt = mood == MascotMood.thinking
        ? -0.10
        : (mood == MascotMood.sad ? 0.05 : 0.0) +
            (still ? 0 : math.sin(ph * 0.5) * 0.03);
    final ringAngle = -0.32 + (still ? 0 : math.sin(ph) * 0.05);
    final orbit = still ? 0.62 : (time * (mood == MascotMood.celebrating ? 3 : 1)) % 1.0;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.scale(1 / squash, squash);

    _ring(canvas, u, ringAngle, back: true);
    _moon(canvas, u, ringAngle, orbit, back: true);
    _arms(canvas, u, ph);
    _body(canvas, u);
    _face(canvas, u, ph);
    _ring(canvas, u, ringAngle, back: false);
    _moon(canvas, u, ringAngle, orbit, back: false);
    _hands(canvas, u, ph);
    canvas.restore();

    _extras(canvas, size, u, ph, center);
  }

  // ---------- الحلقة المدارية ----------
  Rect _ringRect(double u) => Rect.fromCenter(center: Offset.zero, width: 94 * u, height: 30 * u);

  void _ring(Canvas canvas, double u, double angle, {required bool back}) {
    canvas.save();
    canvas.rotate(angle);
    final rect = _ringRect(u);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * u
      ..color = const Color(0xFF5EEAD4).withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.2 * u);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6 * u
      ..shader = const LinearGradient(colors: [
        Color(0xFFE2E8F0),
        Color(0xFFFFFFFF),
        Color(0xFF94A3B8),
      ]).createShader(rect);
    // النصف الخلفي أعلى الجسم، والأمامي أسفله
    final start = back ? math.pi : 0.0;
    canvas.drawArc(rect, start, math.pi, false, glow);
    canvas.drawArc(rect, start, math.pi, false, line);
    canvas.restore();
  }

  void _moon(Canvas canvas, double u, double angle, double orbit, {required bool back}) {
    final a = orbit * 2 * math.pi;
    final isBack = math.sin(a) < 0;
    if (isBack != back) return;
    canvas.save();
    canvas.rotate(angle);
    final p = Offset(47 * u * math.cos(a), 15 * u * math.sin(a));
    canvas.drawCircle(
        p,
        3.4 * u,
        Paint()
          ..color = const Color(0xFF5EEAD4).withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * u));
    canvas.drawCircle(p, 2.2 * u, Paint()..color = Colors.white);
    canvas.restore();
  }

  // ---------- الجسم ----------
  void _body(Canvas canvas, double u) {
    final rect = Rect.fromCenter(center: Offset.zero, width: 50 * u, height: 45 * u);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(16 * u));
    final body = Path()..addRRect(rr);
    // الذيل: زاوية الفقاعة أسفل اليسار
    final tail = Path()
      ..moveTo(-14 * u, 19 * u)
      ..lineTo(-21 * u, 31 * u)
      ..quadraticBezierTo(-10 * u, 27 * u, -3 * u, 21 * u)
      ..close();
    final all = Path.combine(PathOperation.union, body, tail);
    final light = Color.lerp(color, Colors.white, 0.35)!;
    final deep = Color.lerp(color, const Color(0xFF1E3A8A), 0.45)!;
    final c1 = mood == MascotMood.sad ? Color.lerp(light, Colors.blueGrey, 0.35)! : light;
    final c2 = mood == MascotMood.sad ? Color.lerp(deep, Colors.blueGrey, 0.35)! : deep;
    canvas.drawPath(
      all,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ).createShader(rect.inflate(6 * u)),
    );
    // لمعة زجاجية
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(-19 * u, -19 * u, 22 * u, 8 * u), Radius.circular(5 * u)),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      all,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 * u
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  // ---------- الوجه ----------
  void _face(Canvas canvas, double u, double ph) {
    var g = gaze;
    if (mood == MascotMood.thinking) g = const Offset(-0.7, -0.8);
    if (mood == MascotMood.curious) g = Offset(g.dx * 0.5, 0.9);
    final shift = Offset(g.dx.clamp(-1.0, 1.0) * 3.2 * u, g.dy.clamp(-1.0, 1.0) * 2.6 * u);
    final eyeY = -4 * u;
    final left = Offset(-12 * u, eyeY) + shift;
    final right = Offset(12 * u, eyeY) + shift;
    final ink = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4 * u;

    // الخدود
    if (mood == MascotMood.happy ||
        mood == MascotMood.celebrating ||
        mood == MascotMood.shy ||
        mood == MascotMood.waving) {
      final blush = Paint()..color = const Color(0xFFFB7185).withValues(alpha: 0.45);
      canvas.drawOval(Rect.fromCenter(center: Offset(-17 * u, 5 * u), width: 8 * u, height: 4.5 * u), blush);
      canvas.drawOval(Rect.fromCenter(center: Offset(17 * u, 5 * u), width: 8 * u, height: 4.5 * u), blush);
    }

    final wink = tap > 0 && tap < 0.85;
    void eye(Offset c, {bool isRight = false}) {
      final r = 4.6 * u;
      // عين مغلقة: سعيدة ^ أو نائمة ‿
      if (mood == MascotMood.sleepy) {
        canvas.drawArc(Rect.fromCircle(center: c + Offset(0, 1 * u), radius: r), 0.15, math.pi - 0.3, false, stroke);
        return;
      }
      if (mood == MascotMood.celebrating || (wink && isRight)) {
        canvas.drawArc(Rect.fromCircle(center: c + Offset(0, 2 * u), radius: r), math.pi + 0.2, math.pi - 0.4, false, stroke);
        return;
      }
      final open = (1 - blink).clamp(0.08, 1.0) * (mood == MascotMood.sad ? 0.8 : 1.0);
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 2 * open), ink);
      if (open > 0.4) {
        canvas.drawCircle(c + Offset(-1.4 * u, -1.6 * u), 1.4 * u, Paint()..color = Colors.white);
      }
      if (mood == MascotMood.sad) {
        // حاجب مائل حزين
        final s = isRight ? -1.0 : 1.0;
        canvas.drawLine(c + Offset(-4 * u * s, -8 * u), c + Offset(3 * u * s, -6 * u), stroke..strokeWidth = 1.8 * u);
        stroke.strokeWidth = 2.4 * u;
      }
    }

    eye(left);
    eye(right, isRight: true);

    // النقطة الوسطى = الفم
    final m = Offset(shift.dx * 0.6, 8 * u + shift.dy * 0.4);
    switch (mood) {
      case MascotMood.idle:
      case MascotMood.curious:
        canvas.drawCircle(m, 3.2 * u, ink);
      case MascotMood.happy:
      case MascotMood.waving:
        canvas.drawArc(Rect.fromCenter(center: m + Offset(0, -2.5 * u), width: 11 * u, height: 8 * u), 0.2, math.pi - 0.4, false, stroke);
      case MascotMood.celebrating:
        final p = Path()
          ..moveTo(m.dx - 6 * u, m.dy - 2 * u)
          ..quadraticBezierTo(m.dx, m.dy + 9 * u, m.dx + 6 * u, m.dy - 2 * u)
          ..close();
        canvas.drawPath(p, ink);
        canvas.drawCircle(m + Offset(0, 2.8 * u), 1.8 * u, Paint()..color = const Color(0xFFFB7185));
      case MascotMood.sad:
        canvas.drawArc(Rect.fromCenter(center: m + Offset(0, 3 * u), width: 10 * u, height: 7 * u), math.pi + 0.25, math.pi - 0.5, false, stroke);
      case MascotMood.thinking:
        canvas.drawCircle(m + Offset(4 * u, 0), 2.2 * u, ink);
      case MascotMood.sleepy:
        canvas.drawOval(Rect.fromCenter(center: m, width: 4 * u, height: (2.6 + (still ? 0 : math.sin(ph * 2)) * 1.2) * u), ink);
      case MascotMood.shy:
        canvas.drawArc(Rect.fromCenter(center: m + Offset(0, -1.5 * u), width: 7 * u, height: 5 * u), 0.3, math.pi - 0.6, false, stroke);
    }
  }

  // ---------- الذراعان ----------
  void _arms(Canvas canvas, double u, double ph) {
    final p = Paint()..color = Color.lerp(color, const Color(0xFF1E3A8A), 0.3)!;
    if (mood == MascotMood.waving) {
      final a = still ? 0.0 : math.sin(ph * 5) * 0.45;
      canvas.save();
      canvas.translate(24 * u, -2 * u);
      canvas.rotate(-0.9 + a);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, -3 * u, 16 * u, 6 * u), Radius.circular(3 * u)), p);
      canvas.drawCircle(Offset(17 * u, 0), 4.2 * u, p);
      canvas.restore();
      canvas.drawCircle(Offset(-26 * u, 8 * u), 4 * u, p);
    } else if (mood == MascotMood.celebrating) {
      final a = still ? 0.0 : math.sin(ph * 6) * 0.2;
      for (final s in [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(s * 23 * u, -4 * u);
        canvas.rotate(s * (-1.1 + a));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, -3 * u, 15 * u * s, 6 * u), Radius.circular(3 * u)), p);
        canvas.restore();
      }
    } else if (mood != MascotMood.shy) {
      canvas.drawCircle(Offset(-26 * u, 8 * u), 4 * u, p);
      canvas.drawCircle(Offset(26 * u, 8 * u), 4 * u, p);
    }
  }

  /// يدان تغطيان العينين (حياء كلمة المرور)
  void _hands(Canvas canvas, double u, double ph) {
    if (mood != MascotMood.shy) return;
    final p = Paint()..color = Color.lerp(color, Colors.white, 0.15)!;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * u
      ..color = Colors.white.withValues(alpha: 0.5);
    final peek = still ? 0.0 : (math.sin(ph * 2) > 0.85 ? 2.5 * u : 0.0);
    for (final s in [-1.0, 1.0]) {
      final c = Offset(s * 12 * u, -3.5 * u + (s > 0 ? peek : 0));
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 15 * u, height: 11 * u), Radius.circular(5.5 * u));
      canvas.drawRRect(r, p);
      canvas.drawRRect(r, edge);
    }
  }

  // ---------- مؤثرات حول الشخصية ----------
  void _extras(Canvas canvas, Size size, double u, double ph, Offset center) {
    switch (mood) {
      case MascotMood.sleepy:
        for (var i = 0; i < 3; i++) {
          final t = still ? (i / 3) : ((time * 2 + i / 3) % 1.0);
          final tp = TextPainter(
            text: TextSpan(
                text: 'z',
                style: TextStyle(
                    fontSize: (7 + i * 3) * u,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF93C5FD).withValues(alpha: 1 - t))),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, center + Offset((22 + t * 12 + i * 4) * u, (-26 - t * 22) * u));
        }
      case MascotMood.thinking:
        final p = Paint()..color = Colors.white.withValues(alpha: 0.85);
        for (var i = 0; i < 3; i++) {
          final k = still ? 1.0 : (0.6 + 0.4 * math.sin(ph * 2 + i));
          canvas.drawCircle(center + Offset((26 + i * 7) * u, (-26 - i * 8) * u), (2 + i * 1.4) * u * k, p);
        }
      case MascotMood.celebrating:
        const colors = [Color(0xFFF59E0B), Color(0xFF14B8A6), Color(0xFFEC4899), Color(0xFF6366F1), Color(0xFF22C55E)];
        final prog = still ? 0.6 : (time * 3) % 1.0;
        for (var i = 0; i < 14; i++) {
          final a = i / 14 * 2 * math.pi + 0.3;
          final dist = (18 + prog * 32) * u;
          final pos = center + Offset(math.cos(a) * dist, math.sin(a) * dist * 0.8 - prog * 8 * u);
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(a + prog * 6);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 3.4 * u, height: 1.8 * u),
              Paint()..color = colors[i % colors.length].withValues(alpha: 1 - prog * 0.8));
          canvas.restore();
        }
      case MascotMood.sad:
        final t = still ? 0.3 : (time * 1.5) % 1.0;
        final drop = center + Offset(-14 * u, (4 + t * 14) * u);
        final p = Path()
          ..moveTo(drop.dx, drop.dy - 3 * u)
          ..quadraticBezierTo(drop.dx + 2.4 * u, drop.dy + 1 * u, drop.dx, drop.dy + 2 * u)
          ..quadraticBezierTo(drop.dx - 2.4 * u, drop.dy + 1 * u, drop.dx, drop.dy - 3 * u);
        canvas.drawPath(p, Paint()..color = const Color(0xFF7DD3FC).withValues(alpha: 1 - t));
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant MascotPainter o) =>
      o.mood != mood ||
      o.time != time ||
      o.blink != blink ||
      o.tap != tap ||
      o.gaze != gaze ||
      o.color != color ||
      o.still != still;
}

/// بديل شاشة العطل الرمادية في نسخة الإصدار: «وصول» حزين ورسالة هادئة
class MascotErrorView extends StatelessWidget {
  const MascotErrorView({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox.square(
            dimension: 90,
            child: CustomPaint(
                painter: MascotPainter(mood: MascotMood.sad, still: true)),
          ),
          const SizedBox(height: 8),
          const Text('تعذّر عرض هذا الجزء',
              style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                  decoration: TextDecoration.none)),
        ]),
      ),
    );
  }
}
