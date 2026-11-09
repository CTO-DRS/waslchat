import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';
import '../theme.dart';
import 'location_bubble.dart';

/// ورقة مشاركة الموقع (0.4.6 — بند المرحلة 1).
///
/// التدفق الكامل: طلب الإذن → التأكد من خدمة الموقع → جلب الموقع الحالي
/// → معاينة وتأكيد → إرجاع [LocationContent] للإرسال المشفّر.
///
/// الخصوصية: القراءة على الجهاز فقط، والإرسال يُشفَّر قبل الرفع. في
/// القنوات غير المشفّرة تعرض الورقة تحذيراً صريحاً قبل التأكيد.
class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({super.key, required this.encrypted});

  /// هل هذه المحادثة مشفّرة بين الطرفين؟ (لعرض التحذير الصادق)
  final bool encrypted;

  /// يفتح الورقة ويعيد [LocationContent] أو null إن أُلغي
  static Future<LocationContent?> show(
          BuildContext context, {required bool encrypted}) =>
      showModalBottomSheet<LocationContent>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.wasl.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => LocationPickerSheet(encrypted: encrypted),
      );

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  bool _loading = true;
  String? _error;
  bool _recoverable = false; // الخطأ يُصلَح من الإعدادات (إذن/خدمة)
  Position? _pos;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _loading = true;
      _error = null;
      _recoverable = false;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() {
          _loading = false;
          _error = 'إذن الموقع مرفوض — اسمح للتطبيق بالوصول لموقعك لإرساله';
          _recoverable = true;
        });
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error = 'الإذن مرفوض نهائياً — فعّله من إعدادات التطبيق';
          _recoverable = true;
        });
        return;
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        setState(() {
          _loading = false;
          _error = 'خدمة الموقع مقفلة — فعّلها من إعدادات الجهاز';
          _recoverable = true;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _pos = pos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحديد الموقع — تأكد من الخدمة وحاول مجدداً';
      });
    }
  }

  void _confirm() {
    final p = _pos;
    if (p == null) return;
    try {
      final content = LocationContent(
        lat: p.latitude,
        lng: p.longitude,
        accuracyM: p.accuracy,
      );
      Navigator.pop(context, content);
    } catch (_) {
      setState(() => _error = 'تعذّر تجهيز الموقع للإرسال');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.location_on_rounded, color: wasl.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('مشاركة موقعك الحالي',
                  style: TextStyle(
                      color: wasl.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              widget.encrypted
                  ? 'الإحداثيات تُشفَّر قبل رفعها — الخادم لا يعرف موقعك'
                  : '⚠️ هذه القناة غير مشفّرة — موقعك سيكون صريحاً فيها',
              style: TextStyle(
                  color: widget.encrypted ? wasl.textFaint : wasl.danger,
                  fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text('جارٍ تحديد موقعك…',
                    style: TextStyle(color: wasl.textFaint, fontSize: 13)),
              ]),
            )
          else if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: wasl.danger, fontSize: 14)),
            ),
            Row(children: [
              if (_recoverable)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Geolocator.openAppSettings(),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('فتح الإعدادات'),
                  ),
                ),
              if (_recoverable) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _locate,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ]),
          ] else if (_pos != null) ...[
            // معاينة الفقاعة كما ستظهر للمستقبل
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: wasl.bubbleOther,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: wasl.border),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: LocationBubble(
                  mine: false,
                  content: LocationContent(
                    lat: _pos!.latitude,
                    lng: _pos!.longitude,
                    accuracyM: _pos!.accuracy,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('إرسال الموقع'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ),
        ]),
      ),
    );
  }
}
