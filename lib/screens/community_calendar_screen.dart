import 'package:flutter/material.dart';
import '../config.dart';

import '../services/calendar_grid_service.dart';
import '../services/hijri_service.dart';
import '../theme.dart';

/// لوحة التقويم الشهري للمجتمع (المرحلة 9 ب — 0.23.0)
///
/// شبكة شهر كامل (هجري افتراضياً وتبديل ميلادي) فوق خدمة الهجري المتحققة
/// الحسابية، وأحداث المجتمع تظهر على أيامها بنقاط — والنقر على يوم يعرض
/// أحداثه أسفل الشبكة. كل الحساب محلي: الشبكة والتحويلات دالة نقية
/// (`CalendarGridService`) والأحداث تُجلب من قائمة أحداث المجتمع الموجودة
/// أصلاً — بلا أي شبكة إضافية ولا تخزين جديد.
class CommunityCalendarScreen extends StatefulWidget {
  const CommunityCalendarScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  final String communityId;
  final String communityName;

  @override
  State<CommunityCalendarScreen> createState() =>
      _CommunityCalendarScreenState();
}

class _CommunityCalendarScreenState extends State<CommunityCalendarScreen> {
  bool _hijri = true;
  bool _loading = true;
  List<Map<String, dynamic>> _events = const [];

  // الشهر الحالي بالتقويمين — يبدأ من الشهر الحالي
  late (int, int) _hijriMonth = () {
    final (hy, hm, _) = HijriService.toHijri(DateTime.now());
    return (hy, hm);
  }();
  late (int, int) _gregMonth = (DateTime.now().year, DateTime.now().month);

  int? _selectedJdn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await supabase
          .rpc('community_events_list', params: {'cid': widget.communityId});
      if (!mounted) return;
      setState(() {
        _events = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// أحداث اليوم برقمه القياسي — بداية الحدث اليوم نفسه.
  Map<int, List<Map<String, dynamic>>> get _eventsByJdn {
    final m = <int, List<Map<String, dynamic>>>{};
    for (final ev in _events) {
      final starts =
          DateTime.tryParse('${ev['starts_at'] ?? ''}')?.toLocal();
      if (starts == null) continue;
      final jdn = HijriService.gregorianToJdn(starts.year, starts.month, starts.day);
      m.putIfAbsent(jdn, () => []).add(ev);
    }
    return m;
  }

  CalendarGrid get _grid => _hijri
      ? CalendarGridService.hijri(_hijriMonth.$1, _hijriMonth.$2)
      : CalendarGridService.gregorian(_gregMonth.$1, _gregMonth.$2);

  void _prev() {
    setState(() {
      if (_hijri) {
        _hijriMonth = CalendarGridService.hijriPrev(_hijriMonth.$1, _hijriMonth.$2);
      } else {
        _gregMonth = CalendarGridService.gregorianPrev(_gregMonth.$1, _gregMonth.$2);
      }
      _selectedJdn = null;
    });
  }

  void _next() {
    setState(() {
      if (_hijri) {
        _hijriMonth = CalendarGridService.hijriNext(_hijriMonth.$1, _hijriMonth.$2);
      } else {
        _gregMonth = CalendarGridService.gregorianNext(_gregMonth.$1, _gregMonth.$2);
      }
      _selectedJdn = null;
    });
  }

  void _toggleHijri() {
    // الانتقال بين التقويمين يحفظ اليوم المحدد نفسه
    final keep = _selectedJdn;
    setState(() => _hijri = !_hijri);
    if (_hijri) {
      final (y, m, d) = HijriService.jdnToGregorian(keep ?? _todayJdn);
      final (hy, hm, _) = HijriService.toHijri(DateTime(y, m, d));
      _hijriMonth = (hy, hm);
    } else {
      final (y, m, d) = HijriService.jdnToGregorian(keep ?? _todayJdn);
      _gregMonth = (y, m);
    }
    setState(() {});
  }

  int get _todayJdn {
    final n = DateTime.now();
    return HijriService.gregorianToJdn(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid;
    final events = _eventsByJdn;
    final todayJdn = _todayJdn;
    final selected = _selectedJdn;
    final selectedEvents =
        selected == null ? const <Map<String, dynamic>>[] : (events[selected] ?? const []);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('تقويم ${widget.communityName}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('هجري')),
              ButtonSegment(value: false, label: Text('ميلادي')),
            ],
            selected: {_hijri},
            onSelectionChanged: (_) => _toggleHijri(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // شريط التنقل بين الشهور
                Row(children: [
                  IconButton(
                      tooltip: 'الشهر السابق',
                      onPressed: _prev,
                      icon: const Icon(Icons.chevron_right)),
                  Expanded(
                    child: Text(grid.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  IconButton(
                      tooltip: 'الشهر التالي',
                      onPressed: _next,
                      icon: const Icon(Icons.chevron_left)),
                ]),
                const SizedBox(height: 6),
                // رأس الأسبوع
                Row(children: [
                  for (final w in CalendarGridService.weekHeader)
                    Expanded(
                      child: Text(w,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: context.textTertiary)),
                    ),
                ]),
                const SizedBox(height: 4),
                // شبكة الأيام
                ..._gridRows(grid, events, todayJdn),
                const SizedBox(height: 14),
                // أحداث اليوم المحدد
                if (selected != null)
                  ..._selectedEvents(selected, selectedEvents),
              ],
            ),
    );
  }

  List<Widget> _gridRows(
    CalendarGrid grid,
    Map<int, List<Map<String, dynamic>>> events,
    int todayJdn,
  ) {
    final rows = <Widget>[];
    var cells = <Widget>[];
    void flushRow() {
      while (cells.length < 7) {
        cells.add(const Expanded(child: SizedBox()));
      }
      rows.add(Row(children: cells));
      cells = <Widget>[];
    }

    for (var i = 0; i < grid.leadingBlanks; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    for (final (day, jdn) in grid.days) {
      final hasEvent = events.containsKey(jdn);
      final isToday = jdn == todayJdn;
      final isSelected = jdn == _selectedJdn;
      final cross = _hijri
          ? CalendarGridService.crossDayHijri(jdn)
          : CalendarGridService.crossDayGregorian(jdn);
      cells.add(Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _selectedJdn = jdn),
          child: Container(
            margin: const EdgeInsets.all(1.5),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? WaslColors.teal.withValues(alpha: 0.18)
                  : isToday
                      ? context.glass
                      : null,
              borderRadius: BorderRadius.circular(9),
              border: isToday
                  ? Border.all(color: WaslColors.teal, width: 1.4)
                  : null,
            ),
            child: Column(children: [
              Text('$day',
                  style: TextStyle(
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    fontSize: 13.5,
                    color: hasEvent ? WaslColors.teal : null,
                  )),
              Text('$cross',
                  style: TextStyle(
                      fontSize: 9.5, color: context.textFaint, height: 1.1)),
              SizedBox(
                height: 5,
                child: hasEvent
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var k = 0;
                            k < (events[jdn]!.length.clamp(1, 3));
                            k++)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: const BoxDecoration(
                                color: WaslColors.teal, shape: BoxShape.circle),
                          ),
                      ])
                    : null,
              ),
            ]),
          ),
        ),
      ));
      if (cells.length == 7) flushRow();
    }
    if (cells.isNotEmpty) flushRow();
    return rows;
  }

  List<Widget> _selectedEvents(int jdn, List<Map<String, dynamic>> list) {
    final date = HijriService.jdnToGregorian(jdn);
    final dateStr = HijriService.formatBoth(DateTime(date.$1, date.$2, date.$3));
    return [
      Text('أحداث ${dateStr.split(' · ').first}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 6),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('لا أحداث في هذا اليوم',
              style: TextStyle(color: context.textTertiary, fontSize: 13)),
        )
      else
        for (final ev in list)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.event_outlined, color: WaslColors.teal),
              title: Text(ev['title'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if ((ev['starts_at'] as String?) != null)
                  (() {
                    final d = DateTime.tryParse(ev['starts_at'] as String)
                            ?.toLocal() ??
                        DateTime.now();
                    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                  })(),
                if ((ev['location'] as String?)?.isNotEmpty == true)
                  ev['location'] as String,
              ].join(' · ')),
            ),
          ),
    ];
  }
}
