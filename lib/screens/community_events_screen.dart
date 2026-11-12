import 'package:flutter/material.dart';

import '../config.dart';
import '../services/event_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// أحداث المجتمع وتذكيراتها (v0.12.0 — ترحيل 024):
/// قائمة أحداث المجتمع القادمة والجارية، وردود الحضور (سأحضر/ربما/لن أحضر)،
/// والإنشاء والتعديل لمشرفي المجتمع (أو منشئ الحدث). التذكير يصل إشعاراً من الخادم.
class CommunityEventsScreen extends StatefulWidget {
  const CommunityEventsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.myRole,
  });
  final String communityId;
  final String communityName;
  final String myRole;

  @override
  State<CommunityEventsScreen> createState() => _CommunityEventsScreenState();
}

class _CommunityEventsScreenState extends State<CommunityEventsScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  bool get _isAdmin => widget.myRole == 'owner' || widget.myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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

  /// رد على الحضور — الضغط على ردّي الحالي يلغيه (none من الخادم)
  Future<void> _respond(Map<String, dynamic> ev, String response) async {
    final current = ev['my_response'] as String?;
    final target = current == response ? 'none' : response;
    try {
      await supabase.rpc('community_event_respond',
          params: {'eid': ev['id'], 'p_response': target});
      await _load();
    } catch (_) {
      _snack('تعذّر تسجيل ردك');
    }
  }

  Future<void> _delete(Map<String, dynamic> ev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحدث'),
        content: Text('حذف «${ev['title']}» وردود الحضور نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('community_event_delete', params: {'eid': ev['id']});
      _snack('حُذف الحدث');
      _load();
    } catch (_) {
      _snack('تعذّر حذف الحدث');
    }
  }

  bool _canManage(Map<String, dynamic> ev) =>
      _isAdmin || ev['created_by'] == supabase.auth.currentUser?.id;

  bool _ended(Map<String, dynamic> ev) => (ev['ended'] as bool? ?? false);

  // ============ بطاقة الحدث ============
  Widget _card(Map<String, dynamic> ev) {
    final starts = DateTime.tryParse('${ev['starts_at'] ?? ''}')?.toLocal();
    final now = DateTime.now();
    final duration = (ev['duration_minutes'] as num?)?.toInt() ?? 60;
    final live = starts != null && CommunityEventService.isLive(starts, duration, now);
    final ended = _ended(ev);
    final going = (ev['going_count'] as num?)?.toInt() ?? 0;
    final maybe = (ev['maybe_count'] as num?)?.toInt() ?? 0;
    final my = ev['my_response'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(ev['title'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              ),
              if (live)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('جارٍ الآن',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.greenAccent)),
                )
              else if (ended)
                Text('انتهى', style: TextStyle(fontSize: 11.5, color: context.textFaint))
              else if (_canManage(ev))
                PopupMenuButton<String>(
                  tooltip: 'خيارات',
                  icon: Icon(Icons.more_vert, size: 20, color: context.iconStd),
                  onSelected: (v) {
                    if (v == 'edit') _openForm(ev: ev);
                    if (v == 'delete') _delete(ev);
                  },
                  itemBuilder: (_) => [
                    if (!ended)
                      const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
            ]),
            if (starts != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.schedule, size: 14, color: context.textTertiary),
                const SizedBox(width: 5),
                Text(
                  CommunityEventService.formatStartsAt(starts, now),
                  style: TextStyle(fontSize: 12.5, color: context.textSecondary),
                ),
                if (!live && !ended) ...[
                  const SizedBox(width: 8),
                  Text(
                    CommunityEventService.startsInLabel(starts.difference(now)),
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: WaslColors.teal,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ]),
            ],
            if ((ev['location'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.place_outlined, size: 14, color: context.textTertiary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(ev['location'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _rsvpChip(ev, 'going', 'سأحضر', going, my, ended),
                    _rsvpChip(ev, 'maybe', 'ربما', maybe, my, ended),
                    _rsvpChip(ev, 'not_going', 'لن أحضر', null, my, ended),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openDetails(ev),
                child: const Text('التفاصيل'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _rsvpChip(Map<String, dynamic> ev, String value, String label,
      int? count, String? my, bool disabled) {
    final active = my == value;
    return ActionChip(
      avatar: Icon(CommunityEventService.responseIcon(value),
          size: 16,
          color: active ? Colors.white : context.textTertiary),
      label: Text(count == null ? label : '$label${count > 0 ? ' $count' : ''}',
          style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
      backgroundColor: active ? WaslColors.indigo : null,
      labelStyle: TextStyle(color: active ? Colors.white : null),
      side: active ? BorderSide.none : BorderSide(color: context.hairline),
      onPressed: disabled ? null : () => _respond(ev, value),
    );
  }

  // ============ ورقة التفاصيل ============
  Future<void> _openDetails(Map<String, dynamic> ev) async {
    List<Map<String, dynamic>> rsvps = [];
    try {
      final data = await supabase
          .rpc('community_event_rsvps_list', params: {'eid': ev['id']});
      rsvps = List<Map<String, dynamic>>.from(data as List);
    } catch (_) {}
    if (!mounted) return;
    final starts = DateTime.tryParse('${ev['starts_at'] ?? ''}')?.toLocal();
    final remind = (ev['remind_minutes'] as num?)?.toInt() ?? 30;
    final my = ev['my_response'] as String?;
    final ended = _ended(ev);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          maxChildSize: 0.92,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(ev['title'] as String? ?? '',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              if (starts != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.schedule, size: 17, color: WaslColors.teal),
                  const SizedBox(width: 7),
                  Text(
                    '${CommunityEventService.formatStartsAt(starts, DateTime.now())} · ${CommunityEventService.startsInLabel(starts.difference(DateTime.now()))}',
                    style: TextStyle(fontSize: 13.5, color: ctx.textSecondary),
                  ),
                ]),
              ],
              if ((ev['location'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 17, color: WaslColors.violet),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(ev['location'] as String,
                        style: TextStyle(fontSize: 13.5, color: ctx.textSecondary)),
                  ),
                ]),
              ],
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.notifications_outlined,
                    size: 17, color: Colors.orangeAccent),
                const SizedBox(width: 7),
                Text(
                  remind == 0 ? 'بلا تذكير' : 'تذكير ${CommunityEventService.remindLabel(remind)}',
                  style: TextStyle(fontSize: 13, color: ctx.textTertiary),
                ),
              ]),
              if ((ev['description'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                Text(ev['description'] as String,
                    style: TextStyle(fontSize: 14, height: 1.7, color: ctx.textPrimary)),
              ],
              const SizedBox(height: 8),
              Text('أنشأه ${ev['creator_name'] ?? ''}',
                  style: TextStyle(fontSize: 12, color: ctx.textTertiary)),
              const SizedBox(height: 16),
              if (!ended) ...[
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            my == 'going' ? WaslColors.teal : ctx.glass,
                        foregroundColor: my == 'going' ? Colors.white : ctx.textPrimary,
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('سأحضر'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _respond(ev, 'going');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: my == 'maybe' ? WaslColors.violet : ctx.hairline),
                      ),
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('ربما'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _respond(ev, 'maybe');
                      },
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 18),
              for (final value in const ['going', 'maybe', 'not_going'])
                if (rsvps.any((r) => r['response'] == value))
                  _rsvpGroup(rsvps.where((r) => r['response'] == value).toList(), value),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rsvpGroup(List<Map<String, dynamic>> rows, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${CommunityEventService.responseLabel(value)} (${rows.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in rows)
                Chip(
                  avatar: UserAvatar(name: r['name'] as String? ?? '?',
                      url: r['avatar_url'] as String?, radius: 10),
                  label: Text(r['name'] as String? ?? '',
                      style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ============ نموذج الإنشاء والتعديل (للمشرفين ومنشئ الحدث) ============
  Future<void> _openForm({Map<String, dynamic>? ev}) async {
    final isEdit = ev != null;
    final title = TextEditingController(text: ev?['title'] as String? ?? '');
    final desc = TextEditingController(text: ev?['description'] as String? ?? '');
    final loc = TextEditingController(text: ev?['location'] as String? ?? '');
    final existing = isEdit ? DateTime.tryParse('${ev['starts_at'] ?? ''}')?.toLocal() : null;
    DateTime date = existing ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay time = existing != null
        ? TimeOfDay.fromDateTime(existing)
        : const TimeOfDay(hour: 20, minute: 0);
    int duration = isEdit
        ? ((ev['duration_minutes'] as num?)?.toInt() ?? 60)
        : 60;
    int remind = isEdit
        ? ((ev['remind_minutes'] as num?)?.toInt() ?? 30)
        : 30;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Text(isEdit ? 'تعديل الحدث' : 'حدث جديد',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(
                  controller: title,
                  autofocus: !isEdit,
                  maxLength: 120,
                  decoration: const InputDecoration(
                      labelText: 'عنوان الحدث', hintText: 'مثال: جلسة نقاش أسبوعية'),
                ),
                TextField(
                  controller: desc,
                  maxLength: 1000,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'الوصف (اختياري)', hintText: 'تفاصيل الحدث'),
                ),
                TextField(
                  controller: loc,
                  maxLength: 200,
                  decoration: const InputDecoration(
                      labelText: 'المكان أو الرابط (اختياري)',
                      hintText: 'قاعة المراجعة أو رابط الاجتماع'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(CommunityEventService.formatStartsAt(
                          DateTime(date.year, date.month, date.day, time.hour, time.minute),
                          DateTime.now())),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setSheet(() => date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(time.format(ctx)),
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: time);
                      if (t != null) setSheet(() => time = t);
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                Text('المدة', style: TextStyle(fontSize: 12.5, color: ctx.textTertiary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (label, m) in CommunityEventService.durationChoices)
                      ChoiceChip(
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: duration == m,
                        onSelected: (_) => setSheet(() => duration = m),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('التذكير قبل البدء',
                    style: TextStyle(fontSize: 12.5, color: ctx.textTertiary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (label, m) in CommunityEventService.remindChoices)
                      ChoiceChip(
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: remind == m,
                        onSelected: (_) => setSheet(() => remind = m),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: Icon(isEdit ? Icons.save_outlined : Icons.event_outlined, size: 18),
                  label: Text(isEdit ? 'حفظ التعديل' : 'إنشاء الحدث'),
                  onPressed: () async {
                    final starts =
                        DateTime(date.year, date.month, date.day, time.hour, time.minute);
                    if (title.text.trim().isEmpty) {
                      _snack('أدخل عنوان الحدث');
                      return;
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    try {
                      final params = {
                        'p_title': title.text.trim(),
                        'p_description': desc.text.trim(),
                        'p_location': loc.text.trim(),
                        'p_starts_at': starts.toUtc().toIso8601String(),
                        'p_duration_minutes': duration,
                        'p_remind_minutes': remind,
                      };
                      if (isEdit) {
                        await supabase.rpc('community_event_update',
                            params: {'eid': ev['id'], ...params});
                        _snack('عُدّل الحدث');
                      } else {
                        await supabase.rpc('community_event_create',
                            params: {'cid': widget.communityId, ...params});
                        _snack('أُنشئ الحدث — سيصل الأعضاء تذكير قبل بدئه');
                      }
                      _load();
                    } catch (_) {
                      _snack('تعذّر حفظ الحدث — تحقق من الوقت (بعد 5 دقائق على الأقل)');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ الواجهة ============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أحداث المجتمع',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(widget.communityName,
                style: TextStyle(color: context.textTertiary, fontSize: 12)),
          ],
        ),
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'community-events',
              onPressed: _openForm,
              icon: const Icon(Icons.event_outlined),
              label: const Text('حدث جديد'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: const GlassEmptyState(
                        icon: Icons.event_outlined,
                        title: 'لا أحداث بعد',
                        subtitle:
                            'أحداث المجتمع تظهر هنا مع ردود الحضور — ويصل الأعضاء تذكير قبل بدء كل حدث',
                      ),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, i) => _card(_events[i]),
                  ),
                ),
    );
  }
}
