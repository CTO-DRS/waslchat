import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_service.dart';
import '../theme.dart';

/// فقاعة الموقع المشفّر (0.4.6).
///
/// - الإحداثيات مفكوكة التشفير قبل الوصول إلى هنا.
/// - الخريطة **مرسومة محلياً** عمداً: جلب بلاطات من مزوّد خرائط خارجي
///   كان سيكشف للمزوّد «أي جهاز فتح أي إحداثيات» — لا نفعل ذلك. الفتح
///   الفعلي في تطبيق الخرائط قرار صريح من المستخدم (زر «فتح في الخرائط»).
/// - الضغط على البطاقة يفتح تطبيق الخرائط (geo:)، وزر النسخ ينسخ
///   الإحداثيات نصاً.
class LocationBubble extends StatelessWidget {
  const LocationBubble({super.key, required this.content, required this.mine});

  final LocationContent content;
  final bool mine;

  void _openMaps(BuildContext context) async {
    final uri = Uri.parse(content.geoUri);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد تطبيق خرائط على هذا الجهاز')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    final fg = mine ? wasl.onBubbleMine : wasl.textPrimary;
    final faint = mine
        ? wasl.onBubbleMine.withValues(alpha: 0.75)
        : wasl.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // الخريطة المرسومة محلياً — بلا بلاطات خارجية
        GestureDetector(
          onTap: () => _openMaps(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 240,
              height: 150,
              child: CustomPaint(
                painter: _LocalMapPainter(
                  line: fg.withValues(alpha: 0.35),
                  grid: fg.withValues(alpha: 0.12),
                  pin: mine ? Colors.white : wasl.accent,
                  accuracy: (mine ? Colors.white : wasl.accent)
                      .withValues(alpha: 0.18),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on_rounded, size: 15, color: faint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              content.label ?? _coords,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(_coords,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: faint, fontSize: 11.5)),
          ),
          if (content.accuracyM != null) ...[
            const SizedBox(width: 6),
            Text('±${content.accuracyM!.round()} م',
                style: TextStyle(color: faint, fontSize: 11.5)),
          ],
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openMaps(context),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(children: [
                Icon(Icons.map_outlined, size: 13, color: faint),
                const SizedBox(width: 3),
                Text('فتح في الخرائط',
                    style: TextStyle(
                        color: faint,
                        fontSize: 11.5,
                        decoration: TextDecoration.underline)),
              ]),
            ),
          ),
        ]),
      ],
    );
  }

  String get _coords =>
      '${content.lat.toStringAsFixed(5)}, ${content.lng.toStringAsFixed(5)}';
}

/// خريطة مجرّدة مرسومة على الجهاز: شبكة إحداثيات، خطوط «طرق» ثابتة
/// حتمياً (دوال جيبية بلا عشوائية)، دائرة الدقة، ودبوس الموقع في المركز.
class _LocalMapPainter extends CustomPainter {
  _LocalMapPainter({
    required this.line,
    required this.grid,
    required this.pin,
    required this.accuracy,
  });

  final Color line;
  final Color grid;
  final Color pin;
  final Color accuracy;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;
    // شبكة الإحداثيات
    const step = 22.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // خطوط طرق مجرّدة حتمية (نمط ثابت لكل المواقع — لا يمثّل طرقاً حقيقية)
    final roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = line
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.28)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.18,
          size.width * 0.55, size.height * 0.42)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.68,
          size.width, size.height * 0.62);
    canvas.drawPath(path, roadPaint);
    final path2 = Path()
      ..moveTo(size.width * 0.24, size.height)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.55,
          size.width * 0.55, size.height * 0.42);
    canvas.drawPath(path2, roadPaint..strokeWidth = 2);

    final c = Offset(size.width / 2, size.height / 2);

    // دائرة الدقة
    canvas.drawCircle(c, size.width * 0.18, Paint()..color = accuracy);
    canvas.drawCircle(
        c,
        size.width * 0.18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = line);

    // الدبوس
    final needle = Path()
      ..moveTo(c.dx, c.dy - 22)
      ..conicTo(c.dx + 15, c.dy - 2, c.dx, c.dy + 10, 1.0)
      ..conicTo(c.dx - 15, c.dy - 2, c.dx, c.dy - 22, 1.0);
    canvas.drawShadow(needle, Colors.black, 2.0, false);
    canvas.drawPath(needle, Paint()..color = pin);
    canvas.drawCircle(
        c.translate(0, -8), 4.5, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _LocalMapPainter old) =>
      old.line != line || old.grid != grid || old.pin != pin;
}
