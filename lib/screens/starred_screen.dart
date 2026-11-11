import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// المحادثات التي فيها رسائل مميزة بنجمة. الرسائل تُفك داخل المحادثة نفسها.
class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});

  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  List<(Map<String, dynamic>, int)> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stars = await supabase.from('message_stars').select('conversation_id');
      final counts = <String, int>{};
      for (final r in stars) {
        final c = r['conversation_id'] as String;
        counts[c] = (counts[c] ?? 0) + 1;
      }
      final chats = List<Map<String, dynamic>>.from(await supabase.rpc('my_chats') as List);
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final c in chats)
            if (counts.containsKey(c['conversation_id'])) (c, counts[c['conversation_id']]!),
        ];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل المميزة بنجمة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Text('اضغط مطوّلاً على أي رسالة ثم «تمييز بنجمة»',
                      style: TextStyle(color: Colors.white60)))
              : ListView(children: [
                  for (final (c, n) in _rows)
                    ListTile(
                      leading: UserAvatar(
                        name: (c['title'] ?? '') as String,
                        url: c['avatar_url'] as String?,
                        color: c['is_group'] == true ? WaslColors.teal : WaslColors.indigo,
                        icon: c['is_group'] == true ? Icons.groups_2 : null,
                      ),
                      title: Text((c['title'] ?? '') as String),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('$n'),
                        const SizedBox(width: 4),
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                      ]),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            conversationId: c['conversation_id'] as String,
                            title: (c['title'] ?? '') as String,
                            isGroup: c['is_group'] == true,
                            otherId: c['other_id'] as String?,
                            encrypted: true,
                            starredOnly: true,
                          ),
                        ),
                      ).then((_) => _load()),
                    ),
                ]),
    );
  }
}
