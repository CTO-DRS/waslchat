import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _discover = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        supabase.rpc('my_channels'),
        supabase.rpc('discover_channels', params: {'q': _q}),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = List<Map<String, dynamic>>.from(r[0] as List);
        _discover = List<Map<String, dynamic>>.from(r[1] as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final res = await askNameAndDescription(context, title: 'قناة جديدة', nameHint: 'اسم القناة');
    if (res == null) return;
    try {
      final id = await supabase.rpc('create_channel',
          params: {'p_title': res.$1, 'p_description': res.$2, 'p_public': true});
      await _load();
      if (!mounted) return;
      _open({'conversation_id': id, 'title': res.$1, 'role': 'owner'});
    } catch (_) {
      _snack('تعذّر إنشاء القناة');
    }
  }

  Future<void> _follow(Map<String, dynamic> c) async {
    try {
      await supabase.rpc('join_channel', params: {'conv': c['conversation_id']});
      await _load();
      _snack('تابعت ${c['title']}');
    } catch (_) {
      _snack('تعذّرت المتابعة');
    }
  }

  Future<void> _unfollow(Map<String, dynamic> c) async {
    await supabase.rpc('leave_channel', params: {'conv': c['conversation_id']});
    _load();
  }

  Future<void> _open(Map<String, dynamic> c) async {
    final role = c['role'] as String? ?? 'member';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: c['conversation_id'] as String,
          title: c['title'] as String,
          isGroup: true,
          isChannel: true,
          canPost: role == 'owner' || role == 'admin',
          encrypted: false,
        ),
      ),
    );
    _load();
  }

  Widget _icon() => const CircleAvatar(
        radius: 26,
        backgroundColor: WaslColors.violet,
        child: Icon(Icons.campaign, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('القنوات', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton(
          backgroundColor: WaslColors.violet,
          onPressed: _create,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 140),
                children: [
                  if (_mine.isNotEmpty) const SectionTitle('قنواتي'),
                  ..._mine.map((c) {
                    final unread = (c['unread'] as num?)?.toInt() ?? 0;
                    final owner = c['role'] == 'owner';
                    return ListTile(
                      leading: _icon(),
                      title: Text(c['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(previewText(c, empty: '${c['subscribers']} متابع'),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(shortTime(c['last_at'] as String?),
                              style: TextStyle(color: context.textFaint, fontSize: 12)),
                          const SizedBox(height: 4),
                          UnreadBadge(unread),
                        ],
                      ),
                      onTap: () => _open(c),
                      onLongPress: owner
                          ? null
                          : () => showModalBottomSheet(
                                context: context,
                                backgroundColor: context.surfaceAlt,
                                builder: (ctx) => SafeArea(
                                  child: ListTile(
                                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                                    title: const Text('إلغاء المتابعة'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _unfollow(c);
                                    },
                                  ),
                                ),
                              ),
                    );
                  }),
                  const SectionTitle('اكتشف قنوات'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      onChanged: (v) {
                        _q = v.trim();
                        _load();
                      },
                      decoration: const InputDecoration(
                          hintText: 'ابحث عن قناة', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  if (_discover.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: Text('لا توجد قنوات جديدة. أنشئ قناتك بزر +',
                              style: TextStyle(color: context.textTertiary))),
                    ),
                  ..._discover.map((c) => ListTile(
                        leading: _icon(),
                        title: Text(c['title'] as String),
                        subtitle: Text(
                          (c['description'] as String?) ?? '${c['subscribers']} متابع',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _follow(c),
                          child: const Text('متابعة'),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
