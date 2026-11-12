import 'package:flutter/material.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/group_avatar.dart';
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

  /// أسماء المجموعات المفكوكة: الاسم المشفر -> الصريح
  final Map<String, String> _titles = {};

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
      _decryptTitles();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// فك أسماء المجموعات المشفرة في الخلفية (القديم الصريح يمر كما هو)
  void _decryptTitles() {
    for (final (c, _) in _rows) {
      if (c['is_group'] != true) continue;
      final cid = c['conversation_id'] as String;
      final t = (c['title'] ?? '') as String;
      if (_titles.containsKey(t)) continue;
      _titles[t] = E2eService.isEncrypted(t) ? '🔒 مجموعة مشفرة' : t;
      E2eService.groupTitle(cid, t).then((plain) {
        if (mounted) setState(() => _titles[t] = plain);
      });
    }
  }

  /// الاسم المعروض (مفكوكاً إن كان مشفراً)
  String _nameOf(Map<String, dynamic> c) {
    final t = (c['title'] ?? '') as String;
    return _titles[t] ?? (E2eService.isEncrypted(t) ? 'مجموعة' : t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل المميزة بنجمة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(
                  child: Text('اضغط مطوّلاً على أي رسالة ثم «تمييز بنجمة»',
                      style: TextStyle(color: context.textTertiary)))
              : ListView(children: [
                  for (final (c, n) in _rows)
                    Builder(builder: (_) {
                      final isGroup = c['is_group'] == true;
                      final name = _nameOf(c);
                      final groupAvatar = c['avatar_url'] as String?;
                      return ListTile(
                        leading: isGroup && (groupAvatar ?? '').isNotEmpty
                            ? GroupAvatar(
                                conversationId: c['conversation_id'] as String,
                                path: groupAvatar,
                                name: name,
                              )
                            : UserAvatar(
                                name: name,
                                url: isGroup ? null : c['avatar_url'] as String?,
                                color: isGroup ? WaslColors.teal : WaslColors.indigo,
                                icon: isGroup ? Icons.groups_2 : null,
                              ),
                        title: Text(name),
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
                              title: name,
                              isGroup: isGroup,
                              otherId: c['other_id'] as String?,
                              encrypted: true,
                              starredOnly: true,
                            ),
                          ),
                        ).then((_) => _load()),
                      );
                    }),
                ]),
    );
  }
}
