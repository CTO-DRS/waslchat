import 'package:flutter/material.dart';

import '../config.dart';
import '../services/moderation_service.dart';
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
  // تهدئة البحث: تنفيذ الطلب بعد توقف الكتابة بدل ضرب الخادم بكل حرف
  final _debounce = Debouncer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
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
    } catch (e) {
      _snack(ModerationService.joinErrorHint(e) ?? 'تعذّر الانضمام');
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
          verified: c['verified'] == true,
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
        child: WaslFab(onPressed: _create, icon: Icons.add),
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
                        title: Row(children: [
                          Expanded(
                            child: Text(c['name'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          if (c['verified'] == true) const VerifiedBadge(),
                        ]),
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
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: GlassEmptyState(
                        icon: Icons.diversity_3_outlined,
                        title: 'لا توجد مجتمعات مطابقة',
                        subtitle: 'أنشئ أول مجتمع بزر + واجمع أعضاءك في مكان واحد',
                      ),
                    ),
                  ..._discover.map((c) => ListTile(
                        leading: _avatar(c['name'] as String),
                        title: Row(children: [
                          Expanded(
                            child: Text(c['name'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          if (c['verified'] == true) const VerifiedBadge(),
                        ]),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(Icons.people_outline,
                                  size: 14, color: context.textFaint),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  (c['description'] as String?)?.isNotEmpty == true
                                      ? '${c['description']} · ${c['members']} عضو'
                                      : '${c['members']} عضو',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.textTertiary, fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: () => _join(c),
                          icon: const Icon(Icons.group_add_outlined, size: 16),
                          label: const Text('انضمام'),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
