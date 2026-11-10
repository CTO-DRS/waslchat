import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../services/room_permissions_service.dart';
import '../theme.dart';

/// نتيجة شاشة معلومات المجموعة للمحادثة
class GroupInfoResult {
  const GroupInfoResult({this.title, this.left = false});
  final String? title;
  final bool left;
}

/// معلومات المجموعة الخاصة: الأعضاء والأدوار والإضافة والإزالة والمغادرة وتغيير الاسم
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.conversationId, required this.title});
  final String conversationId;
  final String title;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final String _me = supabase.auth.currentUser?.id ?? '';
  late String _title = widget.title;
  List<Map<String, dynamic>> _members = [];
  String _myRole = 'member';
  int _keyVersion = 1;
  bool _loading = true;
  bool _busy = false;
  bool _screenshotBlock = false;

  // صلاحيات الغرفة (0.5.0 — المرحلة 3): تُحمّل مع البقية،
  // والمالك وحده يعدّلها (الخادم يفرض ذلك على كل حال)
  RoomPerms? _perms;
  bool _savingPerms = false;

  // رابط الدعوة (المرحلة 1) — للمالك والمشرفين، وللأعضاء إن فتحها المالك (0.5.0)
  String? _inviteCode;
  bool _inviteLoading = false;
  bool _showQr = false;

  bool get _isAdmin => _myRole == 'owner' || _myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    try {
      final conv = await supabase
          .from('conversations')
          .select('title, group_key_version, screenshot_block')
          .eq('id', widget.conversationId)
          .maybeSingle();
      final rows = await supabase
          .from('conversation_participants')
          .select('user_id, role, joined_at, profiles(username, display_name)')
          .eq('conversation_id', widget.conversationId);
      final list = List<Map<String, dynamic>>.from(rows);
      const order = {'owner': 0, 'admin': 1, 'member': 2};
      list.sort((a, b) {
        final r = (order[a['role']] ?? 3).compareTo(order[b['role']] ?? 3);
        if (r != 0) return r;
        return _nameOf(a).compareTo(_nameOf(b));
      });
      if (!mounted) return;
      setState(() {
        _title = (conv?['title'] as String?) ?? _title;
        _keyVersion = (conv?['group_key_version'] as int?) ?? 1;
        _screenshotBlock = conv?['screenshot_block'] as bool? ?? false;
        _members = list;
        _myRole = (list.firstWhere((m) => m['user_id'] == _me,
                orElse: () => {'role': 'member'})['role'] as String?) ??
            'member';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _snack('تعذّر تحميل معلومات المجموعة');
    }
    // صلاحيات الغرفة تُجلب بعد دوري — أقسام الدعوة تعتمد عليها
    try {
      final p = await RoomPermissionsService.fetch(widget.conversationId);
      if (mounted) setState(() => _perms = p);
    } catch (_) {}
    // رابط الدعوة يُحمّل منفصلاً — تعطّله لا يفسد بقية الشاشة
    unawaited(_loadInvite());
  }

  /// يجلب الرمز النشط إن كنت مالكاً أو مشرفاً أو عضواً بصلاحية الدعوة
  Future<void> _loadInvite() async {
    if (!(_perms?.canInvite ?? _isAdmin)) return;
    if (mounted) setState(() => _inviteLoading = true);
    try {
      final r = await supabase
          .rpc('group_get_invite', params: {'p_conv': widget.conversationId});
      if (mounted) {
        setState(() {
          _inviteCode = r as String?;
          _inviteLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _inviteLoading = false);
    }
  }

  Future<void> _createInvite() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await supabase.rpc('group_create_invite',
          params: {'p_conv': widget.conversationId});
      if (mounted) {
        setState(() {
          _inviteCode = r as String?;
          _showQr = false;
        });
        _snack('تم إنشاء رابط الدعوة — انسخه أو اعرض رمز QR');
      }
    } catch (_) {
      _snack('تعذّر إنشاء رابط الدعوة');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeInvite() async {
    final ok = await _confirm(
        'إبطال رابط الدعوة؟',
        'لن يستطيع أي شخص الانضمام بالرابط القديم، ويمكنك إنشاء رابط جديد في أي وقت.',
        'إبطال');
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await supabase.rpc('group_revoke_invite',
          params: {'p_conv': widget.conversationId});
      if (mounted) {
        setState(() {
          _inviteCode = null;
          _showQr = false;
        });
      }
    } catch (_) {
      _snack('تعذّر إبطال الرابط');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// نسخ نص جاهز للمشاركة: الرمز + الرابط العميق
  void _copyInvite() {
    final code = _inviteCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(
        text: 'انضم إلى مجموعة «$_title» على وصل شات\n'
            'app.waslchat://join/$code\n'
            'أو أدخل الرمز في التطبيق: $code'));
    _snack('نُسخ رابط الدعوة — شاركه مع من تثق بهم');
  }

  /// قسم رابط الدعوة: إنشاء ونسخ وQR وإبطال (المالك والمشرفون)
  Widget _inviteSection() {
    final code = _inviteCode;
    return Column(children: [
      ListTile(
        leading: CircleAvatar(
          backgroundColor: context.wasl.violetSoft,
          child: const Icon(Icons.link_rounded, color: WaslColors.violet),
        ),
        title: const Text('رابط الدعوة'),
        subtitle: Text(_inviteLoading
            ? '…'
            : code == null
                ? 'أنشئ رابطاً وشاركه لينضم الأشخاص بلا بحث'
                : 'الرمز: $code'),
        trailing: _inviteLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : code == null
                ? TextButton(
                    onPressed: _busy ? null : _createInvite,
                    child: const Text('إنشاء'))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: _showQr ? 'إخفاء رمز QR' : 'عرض رمز QR',
                      icon: Icon(_showQr
                          ? Icons.qr_code_2_rounded
                          : Icons.qr_code_rounded),
                      onPressed: () => setState(() => _showQr = !_showQr),
                    ),
                    IconButton(
                      tooltip: 'نسخ الرابط',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: _copyInvite,
                    ),
                    IconButton(
                      tooltip: 'إبطال الرابط',
                      icon: Icon(Icons.link_off_rounded,
                          color: context.wasl.danger),
                      onPressed: _busy ? null : _revokeInvite,
                    ),
                  ]),
      ),
      if (code != null && _showQr)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(children: [
            // خلفية بيضاء إلزامية لقراءة QR في الوضعين
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                  data: 'app.waslchat://join/$code',
                  size: 190,
                  backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            Text('امسح الرمز بكاميرا الجوال لفتح وصل شات والانضمام',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: context.wasl.textFaint)),
          ]),
        ),
    ]);
  }

  String _nameOf(Map<String, dynamic> m) {
    final p = m['profiles'] as Map<String, dynamic>?;
    return ((p?['display_name'] ?? p?['username'] ?? '') as String);
  }

  String _roleLabel(String role) => switch (role) {
        'owner' => 'المؤسس',
        'admin' => 'مشرف',
        _ => '',
      };

  Future<void> _run(Future<void> Function() job, String fail) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      await _load();
    } catch (_) {
      _snack(fail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// بعد إزالة عضو: نولّد مفتاحاً جديداً للأعضاء الباقين فوراً
  void _rotateNow() {
    E2eService.invalidateGroupKey(widget.conversationId);
    unawaited(E2eService.groupKey(widget.conversationId).then((_) => _load()));
  }

  Future<void> _toggleScreenshotBlock() async {
    final v = !_screenshotBlock;
    setState(() => _screenshotBlock = v);
    try {
      await supabase.rpc('set_screenshot_block',
          params: {'p_conv': widget.conversationId, 'p_block': v});
    } catch (_) {
      setState(() => _screenshotBlock = !v);
      _snack('تعذّر الحفظ');
    }
  }

  /// تبديل صلاحية غرفة (المالك فقط — الخادم يفرض ذلك)
  Future<void> _togglePerm(RoomPermKey k, bool v) async {
    final current = _perms;
    if (current == null || _savingPerms) return;
    final updated =
        RoomPerms(role: current.role, perms: {...current.perms, k.key: v});
    setState(() {
      _perms = updated;
      _savingPerms = true;
    });
    try {
      final saved = await RoomPermissionsService.save(
          widget.conversationId, updated.perms);
      if (mounted) {
        setState(() =>
            _perms = RoomPerms(role: current.role, perms: saved));
      }
      // قسم الدعوة يتغيّر فوراً مع member_invites
      unawaited(_loadInvite());
    } catch (e) {
      if (mounted) setState(() => _perms = current);
      _snack(RoomPermissionsService.rejectionMessage(e));
    } finally {
      if (mounted) setState(() => _savingPerms = false);
    }
  }

  /// قسم صلاحيات الغرفة (0.5.0): للقراءة للجميع، والتعديل للمالك وحده.
  /// القيم المعروضة هي القيم المخصّصة للغرفة (أو الافتراضي) وليست حالتي أنا
  Widget _permissionsSection() {
    final perms = _perms;
    final isOwner = _myRole == 'owner';
    final entries = <(RoomPermKey, IconData, String)>[
      (
        RoomPermKey.media,
        Icons.collections_outlined,
        'صور وفيديو وملفات وملصقات وموقع وبطاقات — للأعضاء'
      ),
      (
        RoomPermKey.voice,
        Icons.mic_none_outlined,
        'التسجيل الصوتي المضغوط — للأعضاء'
      ),
      (
        RoomPermKey.polls,
        Icons.poll_outlined,
        'إنشاء الاستطلاعات والتصويت فيها — للأعضاء'
      ),
      (
        RoomPermKey.invites,
        Icons.link_outlined,
        'روابط الدعوة — كانت للمشرفين فقط سابقاً'
      ),
      (
        RoomPermKey.manageMembers,
        Icons.manage_accounts_outlined,
        'إضافة وإزالة الأعضاء — ساري على المشرفين'
      ),
      (
        RoomPermKey.editInfo,
        Icons.edit_note_outlined,
        'تغيير اسم المجموعة — ساري على المشرفين'
      ),
    ];
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.rule_outlined, color: WaslColors.indigo),
        title: const Text('صلاحيات الغرفة'),
        subtitle: Text(isOwner
            ? 'اضبط ما يستطيع الأعضاء والمشرفون فعله — يسري فوراً ويُفرض من الخادم'
            : 'يضبطها مالك المجموعة — عرض للقراءة'),
      ),
      for (final (k, icon, desc) in entries)
        SwitchListTile(
          secondary: Icon(icon, color: WaslColors.teal),
          title: Text(k.label),
          subtitle: Text(desc),
          value: perms != null
              ? (perms.perms[k.key] ?? kRoomPermDefaults[k.key] ?? false)
              : (kRoomPermDefaults[k.key] ?? false),
          onChanged: isOwner && !_savingPerms
              ? (v) => _togglePerm(k, v)
              : null,
        ),
    ]);
  }

  Future<bool> _confirm(String title, String body, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _title);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اسم المجموعة'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || name == _title) return;
    await _run(
      () => supabase.rpc('group_rename',
          params: {'p_conv': widget.conversationId, 'p_title': name}),
      'تعذّر تغيير الاسم',
    );
  }

  Future<void> _remove(Map<String, dynamic> m) async {
    final ok = await _confirm('إزالة ${_nameOf(m)}؟',
        'لن يرى الرسائل الجديدة، وسيُغيَّر مفتاح تشفير المجموعة للأعضاء الباقين.', 'إزالة');
    if (!ok) return;
    await _run(() async {
      await supabase.rpc('group_remove_member',
          params: {'p_conv': widget.conversationId, 'p_user': m['user_id']});
      _rotateNow();
    }, 'تعذّرت الإزالة');
  }

  Future<void> _setRole(Map<String, dynamic> m, String role) => _run(
        () => supabase.rpc('group_set_role', params: {
          'p_conv': widget.conversationId,
          'p_user': m['user_id'],
          'p_role': role,
        }),
        'تعذّر تغيير الدور',
      );

  Future<void> _leave() async {
    final ok = await _confirm(
        'مغادرة المجموعة؟',
        _myRole == 'owner'
            ? 'ستنتقل ملكية المجموعة إلى مشرف أو أقدم عضو، ويُغيَّر مفتاح التشفير للباقين.'
            : 'لن تصلك رسائلها بعد الآن، ويُغيَّر مفتاح التشفير للباقين.',
        'مغادرة');
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await supabase.rpc('group_leave', params: {'p_conv': widget.conversationId});
      E2eService.invalidateGroupKey(widget.conversationId);
      if (mounted) Navigator.pop(context, const GroupInfoResult(left: true));
    } catch (_) {
      _snack('تعذّرت المغادرة');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMembers() async {
    final existing = _members.map((m) => m['user_id'] as String).toSet();
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.wasl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddMembersSheet(exclude: existing),
    );
    if (picked == null || picked.isEmpty) return;
    await _run(() async {
      await supabase.rpc('group_add_members',
          params: {'p_conv': widget.conversationId, 'p_members': picked});
      // تغليف المفتاح الحالي للأعضاء الجدد
      E2eService.invalidateGroupKey(widget.conversationId);
      unawaited(E2eService.groupKey(widget.conversationId));
    }, 'تعذّرت الإضافة');
  }

  Widget? _memberMenu(Map<String, dynamic> m) {
    final uid = m['user_id'] as String;
    final role = m['role'] as String? ?? 'member';
    final canManage = _myRole == 'owner' || (_perms?.canManageMembers ?? true);
    if (uid == _me || role == 'owner' || !_isAdmin || !canManage) return null;
    final canRemove = _myRole == 'owner' || role == 'member';
    final items = <PopupMenuEntry<String>>[
      if (_myRole == 'owner' && role == 'member')
        const PopupMenuItem(value: 'promote', child: Text('ترقية إلى مشرف')),
      if (_myRole == 'owner' && role == 'admin')
        const PopupMenuItem(value: 'demote', child: Text('إلغاء الإشراف')),
      if (canRemove)
        PopupMenuItem(
            value: 'remove',
            child: Text('إزالة من المجموعة',
                style: TextStyle(color: context.wasl.danger))),
    ];
    if (items.isEmpty) return null;
    return PopupMenuButton<String>(
      enabled: !_busy,
      itemBuilder: (_) => items,
      onSelected: (v) {
        switch (v) {
          case 'promote':
            _setRole(m, 'admin');
          case 'demote':
            _setRole(m, 'member');
          case 'remove':
            _remove(m);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, GroupInfoResult(title: _title));
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('معلومات المجموعة')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  const SizedBox(height: 8),
                  const Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: WaslColors.teal,
                      child: Icon(Icons.groups_2, color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(
                      child: Text(_title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    if (_isAdmin)
                      IconButton(
                        tooltip: 'تغيير الاسم',
                        onPressed:
                            (_busy || !(_perms?.canEditInfo ?? true))
                                ? null
                                : _rename,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                  ]),
                  Text('${_members.length} أعضاء',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.wasl.textFaint)),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.lock_outline, color: WaslColors.teal),
                    title: const Text('الرسائل مشفّرة بين الأعضاء'),
                    subtitle: Text('إصدار مفتاح المجموعة: $_keyVersion — يتغيّر عند خروج أي عضو'),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.screenshot_monitor_outlined,
                        color: WaslColors.teal),
                    title: const Text('منع لقطات الشاشة'),
                    subtitle: Text(_isAdmin
                        ? 'يخفي المجموعة من لقطات الشاشة على أندرويد (المالك والمشرفون)'
                        : 'المالك والمشرفون فقط يغيّرون هذا الإعداد'),
                    value: _screenshotBlock,
                    onChanged: _isAdmin ? (_) => _toggleScreenshotBlock() : null,
                  ),
                  const Divider(),
                  _permissionsSection(),
                  const Divider(),
                  if (_isAdmin && (_perms?.canManageMembers ?? true))
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: WaslColors.indigo,
                        child: Icon(Icons.person_add_alt_1, color: Colors.white),
                      ),
                      title: const Text('إضافة أعضاء'),
                      onTap: _busy ? null : _addMembers,
                    ),
                  if (_isAdmin || (_perms?.canInvite ?? false)) _inviteSection(),
                  for (final m in _members)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: context.wasl.surface,
                        child: Text(_nameOf(m).isNotEmpty ? _nameOf(m).characters.first : '?'),
                      ),
                      title: Text(m['user_id'] == _me ? '${_nameOf(m)} (أنت)' : _nameOf(m)),
                      subtitle: _roleLabel(m['role'] as String? ?? '').isEmpty
                          ? null
                          : Text(_roleLabel(m['role'] as String),
                              style: const TextStyle(color: WaslColors.teal)),
                      trailing: _memberMenu(m),
                    ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.logout_rounded, color: context.wasl.danger),
                    title: Text('مغادرة المجموعة',
                        style: TextStyle(color: context.wasl.danger)),
                    onTap: _busy ? null : _leave,
                  ),
                ],
              ),
      ),
    );
  }
}

/// بحث واختيار أعضاء جدد
class _AddMembersSheet extends StatefulWidget {
  const _AddMembersSheet({required this.exclude});
  final Set<String> exclude;

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  final Map<String, String> _selected = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    try {
      final data = await supabase
          .from('profiles')
          .select('id, username, display_name')
          .ilike('username', '%$q%')
          .limit(20);
      final list = List<Map<String, dynamic>>.from(data)
          .where((p) => !widget.exclude.contains(p['id']))
          .toList();
      if (mounted) setState(() => _results = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _search,
                decoration: const InputDecoration(
                    hintText: 'ابحث باسم المستخدم', prefixIcon: Icon(Icons.search)),
              ),
            ),
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final e in _selected.entries)
                      Chip(
                        label: Text(e.value),
                        onDeleted: () => setState(() => _selected.remove(e.key)),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(children: [
                for (final p in _results)
                  CheckboxListTile(
                    value: _selected.containsKey(p['id']),
                    title: Text((p['display_name'] ?? p['username'] ?? '') as String),
                    subtitle: Text('@${p['username']}'),
                    onChanged: (v) => setState(() {
                      final id = p['id'] as String;
                      if (v == true) {
                        _selected[id] = (p['display_name'] ?? p['username'] ?? '') as String;
                      } else {
                        _selected.remove(id);
                      }
                    }),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.keys.toList()),
                  child: Text(_selected.isEmpty ? 'اختر أعضاء' : 'إضافة (${_selected.length})'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
