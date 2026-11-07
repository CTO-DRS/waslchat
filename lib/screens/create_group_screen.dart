import 'package:flutter/material.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../theme.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _title = TextEditingController();
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  final Map<String, String> _selected = {}; // id -> name
  bool _creating = false;

  @override
  void dispose() {
    _title.dispose();
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
          .neq('id', supabase.auth.currentUser?.id ?? '')
          .limit(20);
      if (mounted) setState(() => _results = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتب اسم المجموعة واختر عضواً واحداً على الأقل')));
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await supabase.rpc('create_group_chat', params: {
        'p_title': title,
        'p_members': _selected.keys.toList(),
      });
      // تثبيت مبكر لمفتاح المجموعة وتغليفه للأعضاء (في الخلفية — لا يعطّل التنقل)
      final convId = id as String;
      E2eService.initGroupKey(convId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
              conversationId: convId, title: title, isGroup: true, encrypted: true),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر إنشاء المجموعة')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مجموعة جديدة'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: const Text('إنشاء', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _title,
            decoration: const InputDecoration(
                hintText: 'اسم المجموعة', prefixIcon: Icon(Icons.groups_2_outlined)),
          ),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _selected.entries
                  .map((e) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: Chip(
                          label: Text(e.value),
                          onDeleted: () => setState(() => _selected.remove(e.key)),
                        ),
                      ))
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: TextField(
            controller: _query,
            onChanged: _search,
            decoration: const InputDecoration(
                hintText: 'أضف أعضاء باسم المستخدم', prefixIcon: Icon(Icons.search)),
          ),
        ),
        if (_creating) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final u = _results[i];
              final id = u['id'] as String;
              final name = (u['display_name'] ?? u['username']) as String;
              final checked = _selected.containsKey(id);
              return CheckboxListTile(
                value: checked,
                activeColor: WaslColors.teal,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected[id] = name;
                  } else {
                    _selected.remove(id);
                  }
                }),
                secondary: CircleAvatar(
                  backgroundColor: WaslColors.indigo,
                  child: Text(name.characters.first, style: const TextStyle(color: Colors.white)),
                ),
                title: Text(name),
                subtitle: Text('@${u['username']}'),
              );
            },
          ),
        ),
      ]),
    );
  }
}
