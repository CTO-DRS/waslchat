import 'package:flutter/material.dart';

import '../config.dart';
import '../services/moderation_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// أدوات الإشراف في المجتمع (v0.11.0): كتم مؤقت، طرد وحظر، فلتر كلمات، سجل إشراف.
/// متاحة لمالك المجتمع ومشرفيه فقط — الفرض النهائي من الخادم (ترحيل 023).
class CommunityModerationScreen extends StatefulWidget {
  const CommunityModerationScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.myRole,
  });
  final String communityId;
  final String communityName;
  final String myRole;

  @override
  State<CommunityModerationScreen> createState() =>
      _CommunityModerationScreenState();
}

class _CommunityModerationScreenState
    extends State<CommunityModerationScreen> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _mutes = [];
  List<Map<String, dynamic>> _bans = [];
  List<Map<String, dynamic>> _filters = [];
  List<Map<String, dynamic>> _log = [];
  bool _loading = true;
  bool _amOwner = false;

  @override
  void initState() {
    super.initState();
    _amOwner = widget.myRole == 'owner';
    _load();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      final cid = widget.communityId;
      final r = await Future.wait<dynamic>([
        supabase.rpc('community_members_list', params: {'cid': cid}),
        supabase.rpc('community_mutes_list', params: {'cid': cid}),
        supabase.rpc('community_bans_list', params: {'cid': cid}),
        supabase.from('community_word_filters')
            .select('id, pattern, created_at')
            .eq('community_id', cid)
            .order('created_at'),
        supabase.rpc('community_mod_log_list', params: {'cid': cid}),
      ]);
      if (!mounted) return;
      setState(() {
        _members = List<Map<String, dynamic>>.from(r[0] as List);
        _mutes = List<Map<String, dynamic>>.from(r[1] as List);
        _bans = List<Map<String, dynamic>>.from(r[2] as List);
        _filters = List<Map<String, dynamic>>.from(r[3] as List);
        _log = List<Map<String, dynamic>>.from(r[4] as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ============ صلاحيات التراتب: المالك فوق المشرف فوق العضو ============
  bool _canActOn(Map<String, dynamic> member) {
    final role = member['role'] as String? ?? 'member';
    if (role == 'owner') return false;
    if (role == 'admin') return _amOwner;
    return true;
  }

  String _roleLabel(String role) => switch (role) {
        'owner' => 'مالك',
        'admin' => 'مشرف',
        _ => 'عضو',
      };

  // ============ الإجراءات عبر دوال الخادم ============
  Future<void> _mute(Map<String, dynamic> member, int minutes) async {
    final reason = await _askReason('سبب الكتم (اختياري)');
    if (reason == null) return;
    try {
      await supabase.rpc('community_mute', params: {
        'cid': widget.communityId,
        'uid': member['user_id'],
        'p_minutes': minutes,
        'p_reason': reason,
      });
      _snack('تم كتم ${member['name']}');
      _load();
    } catch (_) {
      _snack('تعذّر تنفيذ الكتم');
    }
  }

  Future<void> _unmute(Map<String, dynamic> row) async {
    try {
      await supabase.rpc('community_unmute',
          params: {'cid': widget.communityId, 'uid': row['user_id']});
      _snack('رُفع الكتم عن ${row['name']}');
      _load();
    } catch (_) {
      _snack('تعذّر رفع الكتم');
    }
  }

  Future<void> _kick(Map<String, dynamic> member) async {
    final res = await _askKickConfirm(member);
    if (res == null) return;
    try {
      await supabase.rpc('community_kick', params: {
        'cid': widget.communityId,
        'uid': member['user_id'],
        'p_ban': res.$1,
        'p_reason': res.$2,
      });
      _snack(res.$1 ? 'طُرد وحُظر ${member['name']}' : 'طُرد ${member['name']}');
      _load();
    } catch (_) {
      _snack('تعذّر تنفيذ الطرد');
    }
  }

  Future<void> _unban(Map<String, dynamic> row) async {
    try {
      await supabase.rpc('community_unban',
          params: {'cid': widget.communityId, 'uid': row['user_id']});
      _snack('رُفع الحظر عن ${row['name']}');
      _load();
    } catch (_) {
      _snack('تعذّر رفع الحظر');
    }
  }

  Future<void> _addFilter() async {
    final word = await _askText(
        title: 'كلمة محجوبة جديدة',
        hint: 'الكلمة أو العبارة',
        action: 'إضافة');
    if (word == null || word.trim().isEmpty) return;
    try {
      final fid = await supabase.rpc('community_add_filter',
          params: {'cid': widget.communityId, 'p_pattern': word.trim()});
      if (fid == null) {
        _snack('الكلمة موجودة في الفلتر بالفعل');
      } else {
        _snack('أُضيفت إلى الفلتر');
      }
      _load();
    } catch (_) {
      _snack('تعذّر إضافة الكلمة');
    }
  }

  Future<void> _removeFilter(Map<String, dynamic> row) async {
    try {
      await supabase.rpc('community_remove_filter', params: {'fid': row['id']});
      _load();
    } catch (_) {
      _snack('تعذّر إزالة الكلمة');
    }
  }

  // ============ حوارات الإدخال والتأكيد ============
  Future<String?> _askText({
    required String title,
    required String hint,
    required String action,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true ? ctrl.text : null;
  }

  Future<String?> _askReason(String title) => _askText(
      title: title, hint: 'السبب يظهر في سجل الإشراف', action: 'تنفيذ');

  Future<(bool, String?)?> _askKickConfirm(Map<String, dynamic> member) async {
    final reason = TextEditingController();
    var ban = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('طرد ${member['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: reason,
                maxLength: 300,
                decoration: const InputDecoration(
                    hintText: 'السبب (اختياري — يظهر في السجل)'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: ban,
                onChanged: (v) => setState(() => ban = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('منع العودة (حظر)'),
                subtitle: Text('لا يستطيع الانضمام مجدداً',
                    style: TextStyle(fontSize: 12, color: ctx.textTertiary)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ban ? 'طرد وحظر' : 'طرد'),
            ),
          ],
        ),
      ),
    );
    return ok == true ? (ban, reason.text.trim().isEmpty ? null : reason.text.trim()) : null;
  }

  // ============ ورقة إجراءات العضو ============
  Future<void> _memberSheet(Map<String, dynamic> member) async {
    final mutedUntil = DateTime.tryParse('${member['muted_until'] ?? ''}');
    final now = DateTime.now();
    final canAct = _canActOn(member);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                UserAvatar(name: member['name'] as String? ?? '?',
                    url: member['avatar_url'] as String?, radius: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member['name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        mutedUntil != null && mutedUntil.isAfter(now)
                            ? 'مكتوم حتى ${ModerationService.formatUntil(mutedUntil, now)}'
                            : _roleLabel(member['role'] as String? ?? 'member'),
                        style: TextStyle(fontSize: 12.5, color: ctx.textTertiary),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (canAct) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('كتم مؤقت',
                      style: TextStyle(fontSize: 12.5, color: ctx.textTertiary)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, minutes) in ModerationService.muteChoices)
                      ActionChip(
                        label: Text(label),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _mute(member, minutes);
                        },
                      ),
                  ],
                ),
                if (mutedUntil != null && mutedUntil.isAfter(now))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.mic_outlined, size: 18),
                      label: const Text('رفع الكتم'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _unmute(member);
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('طرد من المجتمع'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _kick(member);
                  },
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'لا يمكنك إدارة ${_roleLabel(member['role'] as String? ?? 'member')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: ctx.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ الواجهة ============
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('أدوات الإشراف',
                  style: TextStyle(
                      color: context.appBarText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              Text(widget.communityName,
                  style: TextStyle(color: context.textTertiary, fontSize: 12)),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'الأعضاء'),
              Tab(text: 'المكتومون'),
              Tab(text: 'المحظورون'),
              Tab(text: 'فلتر الكلمات'),
              Tab(text: 'السجل'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _membersTab(),
                  _mutesTab(),
                  _bansTab(),
                  _filtersTab(),
                  _logTab(),
                ],
              ),
      ),
    );
  }

  Widget _listWrap({required List<Widget> children, required bool empty, IconData? icon, String? title, String? subtitle}) {
    if (empty) {
      return GlassEmptyState(icon: icon ?? Icons.shield_outlined, title: title ?? 'لا شيء بعد', subtitle: subtitle ?? '');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children),
    );
  }

  Widget _membersTab() {
    final actionable = _members.where(_canActOn).length;
    return _listWrap(
      empty: _members.isEmpty,
      icon: Icons.group_outlined,
      title: 'لا أعضاء',
      subtitle: '',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '$actionable عضواً يمكنك إدارته كـ${_amOwner ? 'مالك' : 'مشرف'} — اضغط على العضو',
            style: TextStyle(fontSize: 12.5, color: context.textTertiary),
          ),
        ),
        for (final m in _members)
          ListTile(
            leading: UserAvatar(
                name: m['name'] as String? ?? '?',
                url: m['avatar_url'] as String?,
                radius: 20,
                color: (m['role'] as String? ?? 'member') == 'member'
                    ? WaslColors.indigo
                    : WaslColors.teal),
            title: Text(m['name'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Row(children: [
              Text(_roleLabel(m['role'] as String? ?? 'member'),
                  style: TextStyle(
                      fontSize: 11.5,
                      color: (m['role'] as String? ?? 'member') == 'member'
                          ? context.textTertiary
                          : WaslColors.teal,
                      fontWeight: FontWeight.w700)),
              if (m['muted_until'] != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.mic_off_outlined, size: 12, color: Colors.orangeAccent),
                const SizedBox(width: 3),
                Text('مكتوم', style: const TextStyle(fontSize: 11.5, color: Colors.orangeAccent)),
              ],
            ]),
            trailing: _canActOn(m)
                ? const Icon(Icons.more_vert, size: 18)
                : null,
            onTap: () => _memberSheet(m),
          ),
      ],
    );
  }

  Widget _mutesTab() => _listWrap(
        empty: _mutes.isEmpty,
        icon: Icons.mic_off_outlined,
        title: 'لا يوجد مكتومون',
        subtitle: 'الكتم يمنع الرسائل النصية والوسائط في كل غرف المجتمع',
        children: [
          for (final m in _mutes) _muteTile(m),
        ],
      );

  Widget _muteTile(Map<String, dynamic> m) {
    final until = DateTime.tryParse('${m['until_at'] ?? ''}');
    final now = DateTime.now();
    final remaining =
        until == null ? null : until.difference(now);
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.orangeAccent,
        child: Icon(Icons.mic_off_outlined, color: Colors.white, size: 20),
      ),
      title: Text(m['name'] as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${until == null ? '' : 'حتى ${ModerationService.formatUntil(until, now)}'}'
        '${remaining == null || remaining.isNegative ? '' : ' · متبقٍ ${ModerationService.formatRemaining(remaining)}'}'
        '${m['reason'] != null ? ' · ${m['reason']}' : ''}',
        style: TextStyle(fontSize: 12.5, color: context.textTertiary),
      ),
      trailing: TextButton(
        onPressed: () => _unmute(m),
        child: const Text('رفع الكتم'),
      ),
    );
  }

  Widget _bansTab() => _listWrap(
        empty: _bans.isEmpty,
        icon: Icons.block_outlined,
        title: 'لا يوجد محظورون',
        subtitle: 'المحظور مطرود لا يستطيع الانضمام إلى المجتمع مجدداً',
        children: [
          for (final b in _bans)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.block_outlined, color: Colors.white, size: 20),
              ),
              title: Text(b['name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${b['reason'] != null ? '${b['reason']} · ' : ''}${shortTime(b['created_at'] as String?)}',
                style: TextStyle(fontSize: 12.5, color: context.textTertiary),
              ),
              trailing: TextButton(
                onPressed: () => _unban(b),
                child: const Text('رفع الحظر'),
              ),
            ),
        ],
      );

  Widget _filtersTab() => _listWrap(
        empty: _filters.isEmpty,
        icon: Icons.filter_alt_outlined,
        title: 'الفلتر فارغ',
        subtitle: 'أضف كلمات تُرفض رسائل الأعضاء إذا تُعِدتها — بالمطابقة العربية بلا تشكيل',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'الرسائل الجديدة والمعدّلة فقط — مشرفو المجتمع يتجاوزون الفلتر',
              style: TextStyle(fontSize: 12.5, color: context.textTertiary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة كلمة محجوبة'),
              onPressed: _addFilter,
            ),
          ),
          for (final f in _filters)
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined, color: Colors.redAccent),
              title: Text('«${f['pattern']}»',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(shortTime(f['created_at'] as String?),
                  style: TextStyle(fontSize: 12, color: context.textTertiary)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'إزالة',
                onPressed: () => _removeFilter(f),
              ),
            ),
        ],
      );

  Widget _logTab() => _listWrap(
        empty: _log.isEmpty,
        icon: Icons.history_outlined,
        title: 'السجل فارغ',
        subtitle: 'كل إجراء إشراف يُسجَّل هنا تلقائياً بمن نفّذه ومتى',
        children: [
          for (final l in _log) _logTile(l),
        ],
      );

  Widget _logTile(Map<String, dynamic> l) {
    final icon = ModerationService.actionIcon(l['action'] as String? ?? '');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.glass,
        child: Icon(icon ?? Icons.shield_outlined, size: 18, color: context.iconStd),
      ),
      title: Text(ModerationService.describeLog(l),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: Text(shortTime(l['created_at'] as String?),
          style: TextStyle(fontSize: 11.5, color: context.textTertiary)),
    );
  }
}
