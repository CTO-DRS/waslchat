import 'package:flutter/material.dart';

import '../config.dart';
import '../services/block_service.dart';
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
