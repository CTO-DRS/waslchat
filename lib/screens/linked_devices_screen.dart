import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_security_service.dart';
import '../services/e2e_service.dart';
import '../theme.dart';

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String _fpGroups(String fp) {
  if (fp.length < 16) return fp.isEmpty ? '—' : fp;
  final h = fp.substring(0, 16).toUpperCase();
  return '${h.substring(0, 4)} ${h.substring(4, 8)} ${h.substring(8, 12)} ${h.substring(12, 16)}';
}

String _seenLabel(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return 'نشط الآن';
  return 'آخر ظهور ${_ago(d)}';
}

String _ago(Duration d) {
  if (d.inDays >= 30) {
    return 'قبل ${d.inDays ~/ 30} شهر';
  }
  if (d.inDays >= 1) return 'قبل ${d.inDays} يوم';
  if (d.inHours >= 1) return 'قبل ${d.inHours} ساعة';
  return 'قبل ${d.inMinutes} دقيقة';
}

IconData _platformIcon(String p) {
  switch (p) {
    case 'أندرويد':
      return Icons.android_rounded;
    case 'آيفون':
      return Icons.phone_iphone_rounded;
    case 'الويب':
      return Icons.language_rounded;
    case 'ماك':
      return Icons.laptop_mac_rounded;
    case 'ويندوز':
      return Icons.laptop_windows_rounded;
    default:
      return Icons.devices_other_rounded;
  }
}

/// الأجهزة المرتبطة: كل جهاز سجّل دخوله لهذا الحساب له هوية تشفير ومفاتيح
/// أولية خاصّة به — رسائل v3 تُغلَّف لكل جهاز على حدة.
class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  bool _loading = true;
  List<DeviceRow> _devices = [];
  String? _current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // مطابقة فورية عند فتح الشاشة: جلسات أجهزة أُزيلت فتُسقط هنا أولاً
    unawaited(DeviceSecurityService.reconcile());
    final rows = await E2eService.listDevices();
    if (!mounted) return;
    setState(() {
      _devices = rows;
      _current = E2eService.currentDeviceId;
      _loading = false;
    });
  }

  Future<void> _remove(DeviceRow d) async {
    final mine = d.id == _current;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إزالة الجهاز؟'),
        content: Text(mine
            ? 'هذا هو جهازك الحالي: تُحذف مفاتيحه الأولية من الخادم فوراً وتُسقط جلساته على بقية الأجهزة لحظياً، وستتوقف رسائل التشفير الجديدة عن الوصول إليه حتى تعيد فتح التطبيق فتُسجَّل له هوية جديدة.'
            : 'تُحذف مفاتيحه الأولية والمكممة ML-KEM من الخادم فوراً وتُسقط جلساته محلياً على بقية الأجهزة لحظياً بحدث الخادم فلن يصله أي رسالة مشفرة جديدة من التطبيقات المحدثة، وإن ظل مسجلاً الدخول فسيُعيد تسجيل نفسه بهوية جديدة عند فتح التطبيق عليه وسيظهر هنا من جديد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('إزالة')),
        ],
      ),
    );
    if (go != true) return;
    await E2eService.removeDevice(d.id);
    if (!mounted) return;
    _snack(context, mine ? 'أُزيل هذا الجهاز — أعد فتح التطبيق لإعادة التسجيل' : 'أُزيل الجهاز');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأجهزة المرتبطة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: context.surfaceAlt,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'كل جهاز سجّل دخوله لهذا الحساب يولّد هوية تشفير ومفاتيح أولية خاصّة به لا تخرج منه — ومنذ 0.24.0 يرافق كل مفتاح أولي مفتاح ما بعد الكم ML-KEM لبدء جلسات هجينة، وتدخل الوسائط الجلسة المتدرجة كالنصوص. إزالة جهاز إزالة كاملة: حذف مخزونه من الخادم فوراً وإسقاط جلساته على بقية الأجهزة لحظياً.',
                      style: TextStyle(height: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final d in _devices)
                  Card(
                    color: context.surfaceAlt,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Icon(_platformIcon(d.platform),
                          color: d.id == _current ? WaslColors.teal : WaslColors.indigo, size: 30),
                      title: Text(
                        '${d.name.isEmpty ? 'جهاز' : d.name}${d.id == _current ? ' — هذا الجهاز' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'بصمة المفتاح ${_fpGroups(d.fp)}\n${_seenLabel(d.lastSeen.toLocal())}',
                        style: const TextStyle(height: 1.5),
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        tooltip: 'إزالة',
                        onPressed: () => _remove(d),
                      ),
                    ),
                  ),
                if (_devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('لا أجهزة مسجلة بعد — أعد فتح التطبيق')),
                  ),
              ],
            ),
    );
  }
}
