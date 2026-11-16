import 'package:flutter/material.dart';

import '../services/hijri_occasions_service.dart';
import '../services/hijri_service.dart';
import '../services/push_service.dart';
import '../theme.dart';

/// المناسبات الهجرية (المرحلة 14 ب — 1.4.0): قائمة المناسبات القادمة
/// محسوبة محلياً فوق HijriService المتحققة، ومفتاح تذكير واحد يجدول
/// **إشعارات محلية على جهازك حصراً** (قناة wasl-reminders نفسها) —
/// والحدود الصادقة معروضة في الشاشة نفسها: التقويم حسابي والرؤية قد
/// تزيح يوماً، والتذكير تعريف لا إفتاء.
class HijriOccasionsScreen extends StatefulWidget {
  const HijriOccasionsScreen({super.key});

  @override
  State<HijriOccasionsScreen> createState() => _HijriOccasionsScreenState();
}

class _HijriOccasionsScreenState extends State<HijriOccasionsScreen> {
  bool _loading = true;
  bool _on = false;
  List<HijriOccasionAhead> _upcoming = const [];
  List<String> _markers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final on = await HijriOccasionsStore.enabled();
    final markers = await HijriOccasionsStore.markers();
    // مطابقة شبكة أمان: إن كان التفعيل قائماً جدول ما لم يجدول بعد
    if (on && mounted) {
      await _scheduleMissing(markers);
    }
    if (!mounted) return;
    setState(() {
      _on = on;
      _markers = markers;
      _upcoming = HijriOccasionsService.upcoming(
          now: DateTime.now(), withinDays: 120, limit: 5);
      _loading = false;
    });
  }

  Future<void> _scheduleMissing(List<String> markers) async {
    final upcoming = HijriOccasionsService.upcoming(
        now: DateTime.now(), withinDays: 120, limit: 5);
    final list = List<String>.from(markers);
    for (final a in upcoming) {
      final key = HijriOccasionsService.markerKey(a);
      if (list.contains(key)) continue;
      final err = await PushService.scheduleLocalReminder(
        title: a.occasion.title,
        body: '${a.occasion.title} ${HijriOccasionsService.daysLabel(a.days)}'
            ' — تذكير محلي من وصل شات',
        fireAt: HijriOccasionsStore.fireAtFor(a),
      );
      if (err == null) {
        list.add(key);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        }
        break; // رسالة صادقة واحدة تكفي — لا نكرر الفشل
      }
    }
    await HijriOccasionsStore.saveMarkers(list);
  }

  Future<void> _toggle(bool on) async {
    setState(() => _on = on);
    await HijriOccasionsStore.setEnabled(on);
    if (on) {
      await _scheduleMissing(_markers);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'جدولت تذكيرات المناسبات القادمة محلياً على جهازك — الصباح الثامن بيوم كل مناسبة')));
    } else {
      // الإلغاء بمطابقة المعرف الحتمي — بلا تخزين معرفات
      for (final key in _markers) {
        final parts = key.split('-').map(int.tryParse).toList();
        if (parts.length != 3 || parts.any((p) => p == null)) continue;
        final g = HijriService.toGregorian(parts[0]!, parts[1]!, parts[2]!);
        await PushService.cancelLocalReminder(DateTime(g.year, g.month, g.day, 8, 0));
      }
      await HijriOccasionsStore.saveMarkers(const []);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أُلغيت تذكيرات المناسبات المجدولة — لن تُجدول غيرها')));
    }
    if (!mounted) return;
    final markers = await HijriOccasionsStore.markers();
    setState(() => _markers = markers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المناسبات الهجرية')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: context.surfaceAlt,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: SwitchListTile(
                    value: _on,
                    onChanged: _toggle,
                    activeThumbColor: WaslColors.teal,
                    title: const Text('تذكير إشعارات محلية',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text(
                        'إشعار على جهازك صباح الثامن بيوم كل مناسبة قادمة — بلا خادم وبلا أي شبكة',
                        style: TextStyle(height: 1.4)),
                  ),
                ),
                const SizedBox(height: 10),
                for (final a in _upcoming)
                  Card(
                    color: context.surfaceAlt,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Icon(
                        a.occasion.month == 9
                            ? Icons.dark_mode_outlined
                            : Icons.celebration_outlined,
                        color: WaslColors.teal,
                        size: 28,
                      ),
                      title: Text(a.occasion.title,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${a.occasion.detail}\n'
                          '${HijriOccasionsService.dateLabel(a)} · سنة ${a.hijriYear}هـ'
                          '${_markers.contains(HijriOccasionsService.markerKey(a)) ? ' · التذكير مجدول ✓' : ''}',
                          style: const TextStyle(height: 1.5, fontSize: 12.5)),
                      isThreeLine: true,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: WaslColors.teal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          HijriOccasionsService.daysLabel(a.days),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: WaslColors.teal),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'حدود صادقة: التقويم الهجري هنا حسابي بمدنة ثابتة فوق خدمة الهجري المتحققة — الرؤية الشرعية قد تزيح يوماً عن الحساب، والتذكير تعريف بالمناسبة لا إفتاء. الإشعارات محلية على جهازك حصراً ولا يغادر أي حرف، والإيقاف يلغي ما جُدول. الجدولة تعمل على أندرويد حالياً مثل التذكيرات الذكية.',
                  style: TextStyle(height: 1.6, fontSize: 12.5),
                ),
              ],
            ),
    );
  }
}
