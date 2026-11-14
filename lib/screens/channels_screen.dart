import 'package:flutter/material.dart';

import '../config.dart';
import '../services/channel_bell_service.dart';
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

  /// جرس القناة (0.21.0): حوار الأوضاع الثلاثة — الحفظ عبر RPC والقراءة
  /// من my_channels (العمود الجديد بعد ترحيل 032؛ بلا ترحيل تعذر الحفظ
  /// ويبقى السلوك الحالي كما هو).
  Future<void> _showBellSheet(Map<String, dynamic> c) async {
    final current = ChannelBellService.normalize(c['bell'] as String?);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(title: Text('إشعارات ${c['title'] as String}',
              style: const TextStyle(fontWeight: FontWeight.w800))),
          for (final (v, icon, label) in const [
            ('all', Icons.notifications_active_outlined, 'كل المنشورات'),
            ('pinned', Icons.push_pin_outlined, 'المنشورات المثبتة فقط'),
            ('mute', Icons.notifications_off_outlined, 'صمت — لا إشعارات'),
          ])
            ListTile(
              leading: Icon(icon, color: current == v ? WaslColors.teal : null),
              title: Text(label),
              trailing: current == v
                  ? const Icon(Icons.check_rounded, size: 18, color: WaslColors.teal)
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ChannelBellService.set(c['conversation_id'] as String, v);
                  if (mounted) {
                    _snack(v == 'mute'
                        ? 'صمتت هذه القناة — لن تصلك بياناتها أصلاً'
                        : v == 'pinned'
                            ? 'ستنبّهك المنشورات المثبتة فقط'
                            : 'ستنبهك كل منشورات القناة');
                    await _load();
                  }
                } catch (_) {
                  if (mounted) _snack('تعذّر الحفظ — تأكد من تشغيل الترحيل 032');
                }
              },
            ),
        ]),
      ),
    );
  }

  /// أيقونة الجرس على صف قناة بحالته (تفضيل الإشعار المعروض)
  Widget _bellIcon(String? bell) {
    final b = ChannelBellService.normalize(bell);
    return Icon(
      b == 'mute'
          ? Icons.notifications_off_outlined
          : b == 'pinned'
              ? Icons.push_pin_outlined
              : Icons.notifications_active_outlined,
      size: 18,
      color: b == 'all'
          ? context.textFaint
          : b == 'pinned'
              ? WaslColors.teal
              : context.textFaint,
    );
  }

  /// تبديل سريع للجرس من القائمة الطويلة (صمت/تشغيل) — أما التفاصيل فورقة _showBellSheet
  Future<void> _setBellQuick(Map<String, dynamic> c, String pref) async {
    try {
      await ChannelBellService.set(c['conversation_id'] as String, pref);
      if (mounted) {
        _snack(pref == 'mute' ? 'صمتت القناة' : 'أُشغلت إشعارات القناة');
        await _load();
      }
    } catch (_) {
      if (mounted) _snack('تعذّر الحفظ — تأكد من تشغيل الترحيل 032');
    }
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
          officialVerified: c['verified'] == true,
        ),
      ),
    );
    _load();
  }

  Widget _icon() => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: WaslColors.gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.campaign, color: Colors.white, size: 26),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('القنوات', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
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
                  if (_mine.isNotEmpty) const SectionTitle('قنواتي'),
                  ..._mine.map((c) {
                    final unread = (c['unread'] as num?)?.toInt() ?? 0;
                    final owner = c['role'] == 'owner';
                    final bell = ChannelBellService.normalize(c['bell'] as String?);
                    return ListTile(
                      leading: _icon(),
                      title: Row(children: [
                        Expanded(
                          child: Text(c['title'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (c['verified'] == true) const VerifiedBadge(),
                      ]),
                      subtitle: Text(previewText(c, empty: '${c['subscribers']} متابع'),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            // جرس القناة (0.21.0): حالة الإشعار المعروضة + النقر يبدّلها
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _showBellSheet(c),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: _bellIcon(bell),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(shortTime(c['last_at'] as String?),
                                style: TextStyle(color: context.textFaint, fontSize: 12)),
                          ]),
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
                                  child: Wrap(children: [
                                    ListTile(
                                      leading: Icon(
                                          ChannelBellService.icon(bell) == 'off'
                                              ? Icons.notifications_active_outlined
                                              : Icons.notifications_off_outlined,
                                          color: WaslColors.indigo),
                                      title: Text(ChannelBellService.label(bell) == 'صمت'
                                          ? 'تشغيل إشعارات القناة'
                                          : 'صمت القناة'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _setBellQuick(c, ChannelBellService.label(bell) == 'صمت' ? 'all' : 'mute');
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.logout, color: Colors.redAccent),
                                      title: const Text('إلغاء المتابعة'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _unfollow(c);
                                      },
                                    ),
                                  ]),
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
                        _debounce.run(_load);
                      },
                      decoration: const InputDecoration(
                          hintText: 'ابحث عن قناة', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  if (_discover.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: GlassEmptyState(
                        icon: Icons.campaign_outlined,
                        title: 'لا توجد قنوات مطابقة',
                        subtitle: 'أنشئ قناتك الأولى بزر + وابدأ النشر لكل متابعيك',
                      ),
                    ),
                  ..._discover.map((c) => ListTile(
                        leading: _icon(),
                        title: Row(children: [
                          Expanded(
                            child: Text(c['title'] as String,
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
                                      ? '${c['description']} · ${c['subscribers']} متابع'
                                      : '${c['subscribers']} متابع',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.textTertiary, fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: () => _follow(c),
                          icon: const Icon(Icons.person_add_alt_1, size: 16),
                          label: const Text('متابعة'),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
