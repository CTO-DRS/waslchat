import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';

// ملاحظة: material_ui يعيد تصدير flutter/material كاملاً — لا نستورد
// flutter/material هنا مباشرة تفادياً لتعارض الأسماء (نمط media_bubbles)

/// منتقي الموقع على الخريطة (2.3.1): بلاط OSM حقيقي 3×3 مع سحب وتكبير
/// ونقر لتحديد أي نقطة — والنتيجة إحداثيات صماء تمر بنفس مسار التشفير
/// النصي في chat_screen. الويدجت مستقل تماماً عن أي خدمة خارجية.
class LocationPick {
  const LocationPick(this.lat, this.lng, this.label);
  final double lat;
  final double lng;
  final String label;
}

/// إسقاط Web Mercator: خطوط عرض/طول ↔ بكسل عالم (256 لكل بلاطة)
(double, double) _worldPx(double lat, double lng, int z) {
  final n = 256.0 * (1 << z);
  final x = (lng + 180) / 360 * n;
  final rad = lat * math.pi / 180;
  final y =
      (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n;
  return (x, y);
}

(double, double) _fromWorldPx(double wx, double wy, int z) {
  final n = 256.0 * (1 << z);
  final lng = wx / n * 360 - 180;
  final yy = wy / n;
  final lat =
      math.atan(math.sinh(math.pi * (1 - 2 * yy))) * 180 / math.pi;
  return (lat, lng);
}

/// يفتح ورقة اختيار الموقع — يعيد null عند الإلغاء
Future<LocationPick?> showLocationPicker(BuildContext context,
    {double? initialLat, double? initialLng}) {
  return showModalBottomSheet<LocationPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LocationPicker(
        initialLat: initialLat, initialLng: initialLng),
  );
}

class _LocationPicker extends StatefulWidget {
  const _LocationPicker({this.initialLat, this.initialLng});
  final double? initialLat;
  final double? initialLng;

  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  static const _tilePx = 256.0;
  double lat = 24.7136, lng = 46.6753; // الرياض افتراضياً حتى يحدد GPS
  double? markLat, markLng;
  int z = 14;
  bool locating = false;
  final _label = TextEditingController(text: 'موقع محدد على الخريطة');

  @override
  void initState() {
    super.initState();
    lat = widget.initialLat ?? lat;
    lng = widget.initialLng ?? lng;
    markLat = lat;
    markLng = lng;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// سحب الخريطة: المركز يتحرك عكس إصبعك والدبوس يلازم المركز
  void _pan(Offset d, double s) {
    final (wx, wy) = _worldPx(lat, lng, z);
    final (nlat, nlng) =
        _fromWorldPx(wx - d.dx / s, wy - d.dy / s, z);
    setState(() {
      lat = nlat.clamp(-85.0, 85.0);
      lng = nlng;
      markLat = lat;
      markLng = lng;
    });
  }

  void _zoom(int dz) {
    final nz = (z + dz).clamp(5, 17);
    if (nz == z) return;
    setState(() => z = nz);
  }

  Future<void> _gps() async {
    setState(() => locating = true);
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12)));
      setState(() {
        lat = double.parse(p.latitude.toStringAsFixed(6));
        lng = double.parse(p.longitude.toStringAsFixed(6));
        markLat = lat;
        markLng = lng;
        _label.text = 'موقعي الحالي';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('تعذّر تحديد الموقع — تحقق من الصلاحية وتشغيل GPS')));
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Widget _tile(int tx, int ty, double s) {
    final n = 1 << z;
    final px = _tilePx * s;
    if (ty < 0 || ty >= n) {
      return Container(width: px, height: px, color: context.surfaceAlt);
    }
    final x = ((tx % n) + n) % n;
    return Image.network('https://tile.openstreetmap.org/$z/$x/$ty.png',
        width: px,
        height: px,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
              width: px,
              height: px,
              color: WaslColors.indigo.withValues(alpha: 0.20),
              alignment: Alignment.center,
              child: Icon(Icons.map_outlined, color: context.textTertiary),
            ));
  }

  @override
  Widget build(BuildContext context) {
    // شبكة 768 بكسل عالمياً تُحجَّم لتناسب عرض الشاشة مع بقاء الرياضيات صحيحة
    final availW = MediaQuery.of(context).size.width - 32.0;
    final s = (availW / (_tilePx * 3)).clamp(0.30, 1.0);
    final grid = _tilePx * 3 * s;
    final (cwx, cwy) = _worldPx(lat, lng, z);
    final tx0 = (cwx / _tilePx).floor() - 1;
    final ty0 = (cwy / _tilePx).floor() - 1;
    final gx0 = tx0 * _tilePx, gy0 = ty0 * _tilePx;
    final pinX = (cwx - gx0) * s, pinY = (cwy - gy0) * s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceAlt,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Row(children: [
              const SizedBox(width: 16),
              Icon(Icons.location_on_rounded, color: WaslColors.teal),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('حدد الموقع على الخريطة',
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary))),
              IconButton(
                  onPressed: () => _zoom(1), icon: const Icon(Icons.add)),
              IconButton(
                  onPressed: () => _zoom(-1),
                  icon: const Icon(Icons.remove)),
              const SizedBox(width: 8),
            ]),
            const SizedBox(height: 8),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: GestureDetector(
                  onPanUpdate: (d) => _pan(d.delta, s),
                  onTapUp: (d) {
                    final (mlat, mlng) = _fromWorldPx(
                        gx0 + d.localPosition.dx / s,
                        gy0 + d.localPosition.dy / s,
                        z);
                    setState(() {
                      markLat = mlat;
                      markLng = mlng;
                    });
                  },
                  child: SizedBox(
                    width: grid,
                    height: grid,
                    child: Stack(clipBehavior: Clip.hardEdge, children: [
                      for (int r = 0; r < 3; r++)
                        for (int c = 0; c < 3; c++)
                          Positioned(
                            left: c * _tilePx * s,
                            top: r * _tilePx * s,
                            child: _tile(tx0 + c, ty0 + r, s),
                          ),
                      Positioned(
                        left: pinX - 17,
                        top: pinY - 34,
                        child: const Icon(Icons.location_on_rounded,
                            size: 34,
                            color: Colors.redAccent,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black45)
                            ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _label,
                    maxLength: 60,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'وصف الموقع (اختياري)',
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: locating ? null : _gps,
                  icon: locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.gps_fixed_rounded, size: 18),
                  label: const Text('موقعي'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(
                        context,
                        LocationPick(
                            markLat ?? lat,
                            markLng ?? lng,
                            _label.text.trim().isEmpty
                                ? 'موقع محدد على الخريطة'
                                : _label.text.trim()));
                  },
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(markLat == null
                      ? 'إرسال'
                      : 'إرسال (${(markLat ?? lat).toStringAsFixed(4)}, ${(markLng ?? lng).toStringAsFixed(4)})'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
