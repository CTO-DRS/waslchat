import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
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
  Timer? _debounce;
  int _seq = 0; // تجاهل استجابات البحث المتأخرة
  Set<String> _blocked = {};

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// من حظرتهم أنا لا يظهروا في نتائج البحث
  Future<void> _loadBlocked() async {
    try {
      final ids = await supabase.rpc('my_blocked_ids');
      if (mounted) setState(() => _blocked = Set<String>.from(ids as List));
    } catch (_) {}
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _doSearch(q.trim()));
  }

  Future<void> _doSearch(String q) async {
    final seq = ++_seq;
    setState(() => _searching = true);
    try {
      final data = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url, bio')
          .ilike('username', '%$q%')
          .neq('id', supabase.auth.currentUser?.id ?? '')
          .limit(20);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = List<Map<String, dynamic>>.from(data)
            .where((u) => !_blocked.contains(u['id']))
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = [];
        _searching = false;
      });
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('blocked')
              ? 'لا يمكن بدء المحادثة: هذا المستخدم حظرك'
              : 'تعذّر بدء المحادثة')));
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
            onChanged: _onQueryChanged,
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
