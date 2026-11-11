import 'package:flutter/material.dart';

import '../config.dart';
import '../services/block_service.dart';
import '../services/invite_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    BlockService.ensureLoaded();
  }

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
    setState(() => _searching = true);
    try {
      final data = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url, bio')
          .ilike('username', '%$q%')
          .neq('id', supabase.auth.currentUser!.id)
          .limit(20);
      if (mounted) {
        setState(() => _results = List<Map<String, dynamic>>.from(data)
            .where((u) => !BlockService.isBlocked(u['id'] as String))
            .toList());
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _open(Map<String, dynamic> user) async {
    try {
      final convId = await supabase.rpc('create_direct_chat', params: {'other_id': user['id']});
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId as String,
            title: (user['display_name'] ?? user['username']) as String,
            otherId: user['id'] as String,
            encrypted: true,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر بدء المحادثة')));
    }
  }

  /// الانضمام إلى مجموعة برمز دعوة أو رابط كامل ملصوق
  Future<void> _joinByInvite() async {
    final ctrl = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('انضمام إلى مجموعة'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(c, v),
          decoration: const InputDecoration(
            labelText: 'رمز الدعوة أو رابطها',
            hintText: 'مثال: abcdefghjk أو الرابط كاملاً',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('انضمام')),
        ],
      ),
    );
    ctrl.dispose();
    if (input == null || input.trim().isEmpty) return;
    if (InviteService.normalize(input) == null) {
      _snack('الرمز غير صالح — تأكد من نسخه كاملاً');
      return;
    }
    _snack('جارٍ الانضمام…');
    try {
      final convId = await InviteService.join(input);
      // جلب اسم المجموعة لعرضه في الشريط
      final conv = await supabase
          .from('conversations')
          .select('title')
          .eq('id', convId)
          .maybeSingle();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId,
            title: ((conv?['title'] as String?) ?? 'مجموعة'),
            isGroup: true,
            encrypted: true,
          ),
        ),
      );
    } on FormatException {
      _snack('الرمز غير صالح — تأكد من نسخه كاملاً');
    } catch (_) {
      // رسالة INVITE_INVALID أو خطأ شبكة/غياب ترحيل 017
      _snack('تعذّر الانضمام: الرمز غير صالح أو منتهٍ (وتأكد من تحديث الخادم)');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('محادثة جديدة')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: _search,
            decoration: const InputDecoration(
                hintText: 'ابحث باسم المستخدم', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: OutlinedButton.icon(
            onPressed: _joinByInvite,
            icon: const Icon(Icons.link_rounded),
            label: const Text('انضمام إلى مجموعة برمز دعوة'),
          ),
        ),
        if (_searching) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final u = _results[i];
              final name = (u['display_name'] ?? u['username']) as String;
              return ListTile(
                leading: UserAvatar(
                    name: name, url: u['avatar_url'] as String?, color: WaslColors.teal, radius: 22),
                title: Text(name),
                subtitle: Text(
                    (u['bio'] as String?)?.isNotEmpty == true
                        ? '@${u['username']} · ${u['bio']}'
                        : '@${u['username']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                onTap: () => _open(u),
              );
            },
          ),
        ),
      ]),
    );
  }
}
