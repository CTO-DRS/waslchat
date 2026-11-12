import 'package:flutter/material.dart';

import '../config.dart';
import '../services/block_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/report_dialog.dart';

String disappearLabel(int? s) {
  switch (s) {
    case 86400:
      return '24 ساعة';
    case 604800:
      return '7 أيام';
    case 7776000:
      return '90 يوماً';
    default:
      return 'متوقفة';
  }
}

/// يختار مؤقت الرسائل المختفية ويحفظه. يعيد القيمة الجديدة (0 = متوقفة) أو null عند الإلغاء/الفشل.
Future<int?> pickDisappearing(BuildContext context, String convId, int? current) async {
  final picked = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: context.surfaceAlt,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Wrap(children: [
        const ListTile(
          title: Text('الرسائل المختفية', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              'الرسائل الجديدة تُحذف من الخادم بعد المدة المختارة. الرسائل السابقة لا تتأثر، ويمكن لأي طرف تصوير الشاشة.'),
        ),
        for (final s in const [0, 86400, 604800, 7776000])
          ListTile(
            leading: Icon(
                (current ?? 0) == s ? Icons.radio_button_checked : Icons.radio_button_off,
                color: WaslColors.teal),
            title: Text(disappearLabel(s == 0 ? null : s)),
            onTap: () => Navigator.pop(ctx, s),
          ),
      ]),
    ),
  );
  if (picked == null) return null;
  try {
    await supabase.rpc('set_disappearing', params: {'p_conv': convId, 'p_seconds': picked});
    return picked;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('admins only')
              ? 'المالك أو المشرفون فقط يغيّرون هذا الإعداد'
              : 'تعذّر الحفظ')));
    }
    return null;
  }
}

/// ملف الطرف الآخر في المحادثة الفردية
class ContactScreen extends StatefulWidget {
  const ContactScreen({
    super.key,
    required this.otherId,
    required this.conversationId,
    required this.title,
    this.disappearSeconds,
    this.onSafetyNumber,
    this.onShowStarred,
  });
  final String otherId;
  final String conversationId;
  final String title;
  final int? disappearSeconds;
  final VoidCallback? onSafetyNumber;
  final VoidCallback? onShowStarred;

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  Map<String, dynamic>? _p;
  bool _muted = false;
  int? _disappear;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _disappear = widget.disappearSeconds;
    _load();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    await BlockService.ensureLoaded();
    if (mounted) {
      setState(() => _blocked = BlockService.isBlocked(widget.otherId));
    }
  }

  Future<void> _toggleBlock() async {
    if (_blocked) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('إلغاء الحظر؟'),
          content: const Text('سيستطيع إرسال الرسائل إليك مجدداً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إلغاء الحظر')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await BlockService.unblock(widget.otherId);
        if (mounted) setState(() => _blocked = false);
        if (mounted) Navigator.pop(context, true);
      } catch (_) {
        _snack('تعذّر إلغاء الحظر');
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حظر المستخدم؟'),
        content: const Text(
            'لن يصلك منه رسائل جديدة، ولن يستطيع إرسال رسائل إليك. لن يُبلَّغ بالحظر.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حظر')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BlockService.block(widget.otherId);
      if (mounted) setState(() => _blocked = true);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _snack('تعذّر الحظر');
    }
  }

  Future<void> _report() async {
    final name = (_p?['display_name'] ?? _p?['username'] ?? widget.title) as String?;
    final blocked = await showReportDialog(context,
        targetUser: widget.otherId, targetName: name);
    if (blocked && mounted) {
      setState(() => _blocked = true);
      Navigator.pop(context, true);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        supabase
            .from('profiles')
            .select('username, display_name, bio, avatar_url')
            .eq('id', widget.otherId)
            .single(),
        supabase
            .from('conversation_participants')
            .select('muted_until')
            .eq('conversation_id', widget.conversationId)
            .eq('user_id', supabase.auth.currentUser!.id)
            .single(),
      ]);
      final mu = results[1]['muted_until'] as String?;
      if (!mounted) return;
      setState(() {
        _p = results[0];
        _muted = mu != null &&
            (mu == 'infinity' || (DateTime.tryParse(mu)?.isAfter(DateTime.now()) ?? false));
      });
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    try {
      await supabase.rpc('set_chat_prefs', params: {
        'p_conv': widget.conversationId,
        'p_mute_hours': _muted ? 0 : -1,
      });
      if (mounted) setState(() => _muted = !_muted);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = (_p?['display_name'] ?? _p?['username'] ?? widget.title) as String;
    final bio = _p?['bio'] as String?;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Center(child: UserAvatar(name: name, url: _p?['avatar_url'] as String?, radius: 60)),
          const SizedBox(height: 14),
          Center(
              child: Text(name,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          if (_p != null)
            Center(
                child: Text('@${_p!['username']}',
                    style: TextStyle(color: context.textTertiary))),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: context.glass, borderRadius: BorderRadius.circular(18)),
              child: Text(bio),
            ),
          ],
          const SizedBox(height: 16),
          if (widget.onSafetyNumber != null)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined, color: WaslColors.teal),
              title: const Text('رمز الأمان'),
              subtitle: const Text('قارنه مع صديقك للتأكد أن لا أحد في المنتصف'),
              onTap: widget.onSafetyNumber,
            ),
          ListTile(
            leading: const Icon(Icons.timer_outlined, color: WaslColors.violet),
            title: const Text('الرسائل المختفية'),
            subtitle: Text(disappearLabel(_disappear)),
            onTap: () async {
              final v = await pickDisappearing(context, widget.conversationId, _disappear);
              if (v != null && mounted) setState(() => _disappear = v == 0 ? null : v);
            },
          ),
          if (widget.onShowStarred != null)
            ListTile(
              leading: const Icon(Icons.star_outline_rounded, color: Colors.amber),
              title: const Text('الرسائل المميزة بنجمة'),
              onTap: () {
                Navigator.pop(context);
                widget.onShowStarred!();
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_off_outlined, color: WaslColors.indigo),
            title: const Text('كتم الإشعارات'),
            value: _muted,
            onChanged: (_) => _toggleMute(),
          ),
          const Divider(height: 32),
          ListTile(
            leading: Icon(
                _blocked ? Icons.block_rounded : Icons.block_outlined,
                color: _blocked ? Colors.redAccent : context.iconStd),
            title: Text(
                _blocked ? 'إلغاء حظر هذا الاتصال' : 'حظر هذا الاتصال',
                style: TextStyle(color: _blocked ? Colors.redAccent : null)),
            subtitle: Text(_blocked
                ? 'محدود الآن: لا رسائل جديدة بينكما من أي اتجاه'
                : 'لن يصلك منه رسائل جديدة ولن يُبلَّغ بالحظر'),
            onTap: _toggleBlock,
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
            title: const Text('الإبلاغ عن المستخدم',
                style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('تصل الشكوى إلى إدارة التطبيق فقط'),
            onTap: _report,
          ),
        ],
      ),
    );
  }
}
