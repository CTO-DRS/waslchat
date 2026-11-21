import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../services/block_service.dart';
import '../services/e2e_service.dart';
import '../services/invite_service.dart';
import '../services/l10n.dart';
import '../services/locale_service.dart';
import '../services/username_service.dart';
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
      final exact = UsernameService.parseFromInput(q);
      final data = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url, bio, is_bot')
          .ilike('username', '%${UsernameService.normalize(q)}%')
          .neq('id', supabase.auth.currentUser!.id)
          .limit(20);
      var found = List<Map<String, dynamic>>.from(data)
          .where((u) => !BlockService.isBlocked(u['id'] as String))
          .toList();
      // مطابقة تامة أولاً: كتب @user أو رابط waslchat.app/@user → أعلى النتائج
      if (exact != null) {
        final row = await UsernameService.lookup(exact);
        if (row != null &&
            row['id'] != supabase.auth.currentUser!.id &&
            !BlockService.isBlocked(row['id'] as String)) {
          found = [row, ...found.where((u) => u['id'] != row['id'])];
        }
      }
      if (mounted) setState(() => _results = found);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _open(Map<String, dynamic> user) async {
    final isBot = user['is_bot'] == true;
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
            // محادثات البوتات غير مشفرة — البوت يقرأها عبر واجهته (بصدق)
            isBot: isBot,
            encrypted: !isBot,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text(l10nT('chats_open_failed', LocaleService.lang.value))));
    }
  }

  /// الانضمام إلى مجموعة برمز دعوة أو رابط كامل ملصوق
  Future<void> _joinByInvite() async {
    final ctrl = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10nT('invite_join_title', LocaleService.lang.value)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(c, v),
          decoration: InputDecoration(
            labelText: l10nT('invite_code_label', LocaleService.lang.value),
            hintText: l10nT('invite_code_hint', LocaleService.lang.value),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l10nT('act_cancel', LocaleService.lang.value))),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              child: Text(l10nT('act_join', LocaleService.lang.value))),
        ],
      ),
    );
    ctrl.dispose();
    if (input == null || input.trim().isEmpty) return;
    if (InviteService.normalize(input) == null) {
      _snack(l10nT('invite_invalid', LocaleService.lang.value));
      return;
    }
    _snack(l10nT('invite_joining', LocaleService.lang.value));
    try {
      final convId = await InviteService.join(input);
      // جلب اسم المجموعة لعرضه في الشريط (يُفك إن كان مشفراً — الظرف يصل بعد الانضمام)
      final conv = await supabase
          .from('conversations')
          .select('title')
          .eq('id', convId)
          .maybeSingle();
      final rawTitle = ((conv?['title'] as String?) ?? '').trim();
      final title = await E2eService.groupTitle(convId, rawTitle);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId,
            title: title,
            isGroup: true,
            encrypted: true,
          ),
        ),
      );
    } on FormatException {
      _snack(l10nT('invite_invalid', LocaleService.lang.value));
    } catch (_) {
      // رسالة INVITE_INVALID أو خطأ شبكة/غياب ترحيل 017
      _snack(l10nT('invite_join_failed', LocaleService.lang.value));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(l10nT('chats_new', LocaleService.lang.value),
              style: const TextStyle(fontWeight: FontWeight.w700))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: _search,
            decoration: InputDecoration(
                hintText: l10nT('chats_search_hint', LocaleService.lang.value),
                prefixIcon: const Icon(Icons.search)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: OutlinedButton.icon(
            onPressed: _joinByInvite,
            icon: const Icon(Icons.link_rounded),
            label: Text(l10nT('invite_join_button', LocaleService.lang.value)),
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
