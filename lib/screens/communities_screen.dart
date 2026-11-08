import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'community_screen.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
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
        supabase.rpc('my_communities'),
        supabase.rpc('discover_communities', params: {'q': _q}),
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
    final res = await askNameAndDescription(context,
        title: 'مجتمع جديد', nameHint: 'اسم المجتمع');
    if (res == null) return;
    try {
      final id = await supabase.rpc('create_community',
          params: {'p_name': res.$1, 'p_description': res.$2});
      await _load();
      if (!mounted) return;
      _open({'id': id, 'name': res.$1, 'role': 'owner'});
    } catch (_) {
      _snack('تعذّر إنشاء المجتمع');
    }
  }

  Future<void> _join(Map<String, dynamic> c) async {
    try {
      await supabase.rpc('join_community', params: {'cid': c['id']});
      await _load();
      if (!mounted) return;
      _snack('انضممت إلى ${c['name']}');
    } catch (_) {
      _snack('تعذّر الانضمام');
    }
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityScreen(
          communityId: c['id'] as String,
          name: c['name'] as String,
          role: (c['role'] as String?) ?? 'member',
        ),
      ),
    );
    _load();
  }

  Widget _avatar(String name) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: WaslColors.gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(name.isNotEmpty ? name.characters.first : '?',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المجتمعات', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton(
          backgroundColor: WaslColors.teal,
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
                  if (_mine.isNotEmpty) const SectionTitle('مجتمعاتي'),
                  ..._mine.map((c) => ListTile(
                        leading: _avatar(c['name'] as String),
                        title: Text(c['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${c['members']} عضو'
                            '${c['role'] == 'owner' ? ' · أنت المالك' : ''}'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => _open(c),
                      )),
                  const SectionTitle('اكتشف مجتمعات'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      onChanged: (v) {
                        _q = v.trim();
                        _load();
                      },
                      decoration: const InputDecoration(
                          hintText: 'ابحث عن مجتمع', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  if (_discover.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: Text('لا توجد مجتمعات جديدة. أنشئ أول مجتمع بزر +',
                              style: TextStyle(color: context.wasl.textFaint))),
                    ),
                  ..._discover.map((c) => ListTile(
                        leading: _avatar(c['name'] as String),
                        title: Text(c['name'] as String),
                        subtitle: Text(
                          (c['description'] as String?) ?? '${c['members']} عضو',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _join(c),
                          child: const Text('انضمام'),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
