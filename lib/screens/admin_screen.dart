import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/wasl_sheet.dart';
import 'shield_admin_screen.dart';

/// لوحة إدارة وصل شات (1.9.4) — تظهر لمسؤولي التطبيق فقط (is_app_admin).
/// كل إجراء هنا يتحقق منه الخادم مرة أخرى؛ إخفاء الشاشة ليس هو الحماية.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  /// هل المستخدم الحالي مسؤول؟ (يُستخدم لإظهار الدخول من الإعدادات)
  static Future<bool> isAdmin() async {
    try {
      return await supabase.rpc('is_app_admin') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  final _q = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = await supabase.rpc('admin_stats');
      final us = await supabase.rpc('admin_users', params: {'p_limit': 200, 'q': _q.text.trim()});
      if (!mounted) return;
      setState(() {
        _stats = st is Map ? Map<String, dynamic>.from(st) : null;
        _users = (us as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('تعذّر التحميل');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(String rpc, Map<String, dynamic> params, String ok) async {
    try {
      await supabase.rpc(rpc, params: params);
      _snack(ok);
      _load();
    } catch (e) {
      _snack(e.toString().contains('protected')
          ? 'لا يمكن تطبيق هذا على مسؤول أو حساب رسمي'
          : 'تعذّر التنفيذ');
    }
  }

  void _userActions(Map<String, dynamic> u) {
    final name = (u['display_name'] ?? u['username'] ?? '') as String;
    final verified = u['verified'] == true;
    final banned = u['banned'] == true;
    final protected = u['is_admin'] == true || u['is_official'] == true;
    showWaslSheet<void>(
      context,
      title: name,
      titleIcon: Icons.manage_accounts_rounded,
      children: (ctx) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text('@${u['username'] ?? ''} · ${u['email'] ?? ''}',
              style: TextStyle(color: context.textFaint, fontSize: 13)),
        ),
        SheetTile(
          icon: verified ? Icons.verified_outlined : Icons.verified_rounded,
          color: VerifiedBadge.color,
          title: verified ? 'إلغاء التوثيق' : 'توثيق الحساب',
          subtitle: 'الشارة الزرقاء بجانب الاسم في كل مكان',
          onTap: () {
            Navigator.pop(ctx);
            _run('admin_set_user_verified', {'p_user': u['id'], 'p_verified': !verified},
                verified ? 'أُلغي التوثيق' : 'تم التوثيق ✓');
          },
        ),
        if (!protected)
          SheetTile(
            icon: banned ? Icons.lock_open_rounded : Icons.block_rounded,
            danger: !banned,
            color: WaslColors.teal,
            title: banned ? 'رفع الحظر' : 'حظر من التطبيق',
            subtitle: banned ? 'يستطيع الدخول من جديد' : 'يُسجَّل خروجه فوراً ولا يستطيع الدخول',
            onTap: () async {
              Navigator.pop(ctx);
              if (!banned) {
                final go = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('حظر $name؟'),
                    content: const Text('سيُسجَّل خروجه من كل أجهزته ولن يستطيع الدخول حتى ترفع الحظر.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                      FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('حظر')),
                    ],
                  ),
                );
                if (go != true) return;
              }
              _run('admin_set_banned', {'p_user': u['id'], 'p_banned': !banned},
                  banned ? 'رُفع الحظر' : 'تم الحظر');
            },
          ),
      ],
    );
  }

  Widget _stat(String label, Object? v, IconData icon, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.withValues(alpha: 0.25)),
          ),
          child: Column(children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 6),
            Text('${v ?? '—'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(fontSize: 12, color: context.textTertiary)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (r) => WaslColors.gradient.createShader(r),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text('لوحة الإدارة', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            Row(children: [
              _stat('مستخدم', _stats?['users'], Icons.people_alt_rounded, WaslColors.indigo),
              _stat('رسالة', _stats?['messages'], Icons.forum_rounded, WaslColors.teal),
              _stat('تنزيل', _stats?['downloads'], Icons.download_rounded, WaslColors.violet),
            ]),
            Row(children: [
              _stat('مجموعة', _stats?['groups'], Icons.groups_rounded, const Color(0xFF0EA5E9)),
              _stat('مجتمع', _stats?['communities'], Icons.diversity_3_rounded, const Color(0xFFF59E0B)),
              _stat('رسالة تواصل', _stats?['contact_new'], Icons.mail_rounded, const Color(0xFFEC4899)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو المعرّف أو البريد',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: context.glass,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            GlassGroup([
              SheetTile(
                icon: Icons.shield_rounded,
                color: Colors.redAccent,
                title: 'بلاغات Wasl Shield',
                subtitle: 'الابتزاز والتهديد والتحرّش — الأدلة والإجراءات وسجل التدقيق',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const ShieldAdminScreen())),
              ),
            ]),
            const SheetSectionLabel('المستخدمون'),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (_users.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                    child: Text('لا يوجد مستخدمون مطابقون',
                        style: TextStyle(color: context.textFaint))),
              )
            else
              GlassGroup([
                for (final u in _users)
                  ListTile(
                    leading: UserAvatar(
                        name: (u['display_name'] ?? u['username'] ?? '?') as String,
                        url: u['avatar_url'] as String?),
                    title: Row(children: [
                      Flexible(
                        child: Text((u['display_name'] ?? u['username'] ?? '') as String,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (u['verified'] == true) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 15),
                      ],
                      if (u['is_admin'] == true) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.shield_rounded, size: 15, color: WaslColors.teal),
                      ],
                      if (u['banned'] == true) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.block_rounded, size: 15, color: Colors.redAccent),
                      ],
                    ]),
                    subtitle: Text('@${u['username'] ?? ''}',
                        style: TextStyle(color: context.textFaint, fontSize: 12.5)),
                    trailing: Icon(Icons.more_horiz_rounded, color: context.textFaint),
                    onTap: () => _userActions(u),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}
