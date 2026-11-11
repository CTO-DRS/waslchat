import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../services/invite_service.dart';
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
  final String _me = supabase.auth.currentUser!.id;
  late String _title = widget.title;
  List<Map<String, dynamic>> _members = [];
  String _myRole = 'member';
  int _keyVersion = 1;
  Map<String, dynamic>? _invite;
  bool _loading = true;
  bool _busy = false;

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
          .select('title, group_key_version')
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
        _members = list;
        _myRole = (list.firstWhere((m) => m['user_id'] == _me,
                orElse: () => {'role': 'member'})['role'] as String?) ??
            'member';
        _loading = false;
      });
      // الدعوة تُجلب بهدوء للمشرفين فقط (يفشل للبقية بلا أثر)
      if (_isAdmin) _loadInvite();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _snack('تعذّر تحميل معلومات المجموعة');
    }
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

  Future<void> _loadInvite() async {
    try {
      final inv = await InviteService.fetch(widget.conversationId);
      if (mounted) setState(() => _invite = inv);
    } catch (_) {
      // بلا ترحيل 017 أو ليس مشرفاً — لا شيء
    }
  }

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

  /// إدارة رابط الدعوة: إنشاء إن لم توجد، أو فتح ورقة العرض
  Future<void> _manageInvite() async {
    if (!InviteService.isActive(_invite)) {
      await _run(() async {
        final code = await InviteService.create(widget.conversationId);
        await _loadInvite();
        if (mounted) _showInviteSheet(code);
      }, 'تعذّر إنشاء رابط الدعوة (تأكد من تطبيق ترحيل 017)');
      return;
    }
    _showInviteSheet(_invite!['code'] as String);
  }

  void _showInviteSheet(String code) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WaslColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _InviteSheet(
        code: code,
        onRegenerate: () async {
          final c = await InviteService.create(widget.conversationId);
          await _loadInvite();
          if (ctx.mounted) {
            Navigator.pop(ctx);
            _showInviteSheet(c);
          }
        },
        onRevoke: () async {
          await InviteService.revoke(widget.conversationId);
          await _loadInvite();
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
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
      backgroundColor: WaslColors.darkSurface,
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
    if (uid == _me || role == 'owner' || !_isAdmin) return null;
    final canRemove = _myRole == 'owner' || role == 'member';
    final items = <PopupMenuEntry<String>>[
      if (_myRole == 'owner' && role == 'member')
        const PopupMenuItem(value: 'promote', child: Text('ترقية إلى مشرف')),
      if (_myRole == 'owner' && role == 'admin')
        const PopupMenuItem(value: 'demote', child: Text('إلغاء الإشراف')),
      if (canRemove)
        const PopupMenuItem(
            value: 'remove',
            child: Text('إزالة من المجموعة', style: TextStyle(color: Colors.redAccent))),
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
                        onPressed: _busy ? null : _rename,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                  ]),
                  Text('${_members.length} أعضاء',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60)),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.lock_outline, color: WaslColors.teal),
                    title: const Text('الرسائل مشفّرة بين الأعضاء'),
                    subtitle: Text('إصدار مفتاح المجموعة: $_keyVersion — يتغيّر عند خروج أي عضو'),
                  ),
                  const Divider(),
                  if (_isAdmin) ...[
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: WaslColors.teal,
                        child: Icon(Icons.link_rounded, color: Colors.white),
                      ),
                      title: const Text('رابط الدعوة'),
                      subtitle: Text(InviteService.isActive(_invite)
                          ? 'فعّال — أي شخص لديه الرابط ينضم إلى المجموعة'
                          : 'غير مفعل — اضغط لإنشاء رابط انضمام'),
                      onTap: _busy ? null : _manageInvite,
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: WaslColors.indigo,
                        child: Icon(Icons.person_add_alt_1, color: Colors.white),
                      ),
                      title: const Text('إضافة أعضاء'),
                      onTap: _busy ? null : _addMembers,
                    ),
                  ],
                  for (final m in _members)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: WaslColors.darkSurface,
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
                    leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    title: const Text('مغادرة المجموعة',
                        style: TextStyle(color: Colors.redAccent)),
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

/// ورقة عرض رابط الدعوة: الرمز والرابط وQR والنسخ والتجديد والتعطيل
class _InviteSheet extends StatelessWidget {
  const _InviteSheet({
    required this.code,
    required this.onRegenerate,
    required this.onRevoke,
  });

  final String code;
  final Future<void> Function() onRegenerate;
  final Future<void> Function() onRevoke;

  String get _url => InviteService.urlFor(code);

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('نُسخ $label إلى الحافظة')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('رابط دعوة المجموعة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('أي شخص يملك هذا الرابط ينضم إلى المجموعة فوراً.',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: _url,
                size: 170,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            _url,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, letterSpacing: 0.3),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copy(context, _url, 'الرابط'),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ الرابط'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copy(context, code, 'الرمز $code'),
                icon: const Icon(Icons.dialpad_rounded, size: 18),
                label: Text('الرمز: $code'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('تم'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => onRegenerate(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('تجديد الرمز'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => onRevoke(),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('تعطيل'),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
            'تجديد الرمز يعطّل الرابط القديم فوراً. تعطيل الرابط يمنع أي انضمام جديد حتى تُنشئ رابطاً جديداً.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ]),
      ),
    );
  }
}
