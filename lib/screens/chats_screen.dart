import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../services/presence_service.dart';
import '../services/saved_service.dart';
import '../theme.dart';
import '../services/status_service.dart';
import '../widgets/common.dart';
import '../widgets/group_avatar.dart';
import 'ai_screen.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'new_chat_screen.dart';
import 'statuses_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  RealtimeChannel? _channel;
  // فك تشفير سطر المعاينة (المحادثات الخاصة): النص المشفّر -> الصريح
  final Map<String, String> _previews = {};

  /// أسماء المجموعات المفكوكة: الاسم المشفر -> الصريح
  final Map<String, String> _titles = {};
  bool _showArchived = false;
  // الحالات/القصص: مجمّعة حسب صاحبها (حالتي أولاً)
  List<Map<String, dynamic>> _statusGroups = [];

  // «رسائلي المحفوظة»: صف مثبّت أعلى القائمة (المرحلة 4)
  String? _savedId;
  String _savedPreview = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadStatuses();
    _loadSaved();
    // تحديث القائمة فور وصول أي رسالة جديدة
    _channel = supabase
        .channel('chat-list')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await supabase.rpc('my_chats');
      if (!mounted) return;
      final chats = List<Map<String, dynamic>>.from(data as List);
      setState(() {
        _chats = chats;
        _loading = false;
      });
      // إجمالي غير المقروء (المؤرشفة والمكتومة لا تحسب) لشارة تبويب المحادثات
      UnreadHub.total.value = chats
          .where((c) => c['archived'] != true && c['muted'] != true)
          .fold<int>(0, (s, c) => s + ((c['unread'] as num?)?.toInt() ?? 0));
      _decryptPreviews(chats);
      _decryptTitles(chats);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// فك أسماء المجموعات المشفرة في الخلفية (القديم الصريح يمر كما هو)
  void _decryptTitles(List<Map<String, dynamic>> chats) {
    for (final c in chats) {
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

  /// الاسم المعروض لصف المحادثة (مفكوكاً إن كان مشفراً)
  String _nameOf(Map<String, dynamic> c) {
    final t = (c['title'] ?? '') as String;
    return _titles[t] ?? (E2eService.isEncrypted(t) ? 'مجموعة' : t);
  }

  /// جلب الحالات النشطة وتجميعها (صامت عند الفشل — الشريط اختياري)
  Future<void> _loadStatuses() async {
    try {
      final rows = await StatusService.feed();
      if (!mounted) return;
      setState(() {
        _statusGroups = StatusService.groupByAuthor(
            rows, supabase.auth.currentUser!.id);
      });
    } catch (_) {}
  }

  /// يفك تشفير المعاينات المشفّرة في الخلفية (المحادثات الخاصة والمجموعات الخاصة)
  void _decryptPreviews(List<Map<String, dynamic>> chats) {
    for (final c in chats) {
      final lm = c['last_message'] as String?;
      if (lm == null || !E2eService.isEncrypted(lm) || _previews.containsKey(lm)) {
        continue;
      }
      _previews[lm] = '🔒 رسالة مشفرة';
      final cid = c['conversation_id'] as String;
      final Future<String> job = c['is_group'] == true
          ? E2eService.previewGroup(conversationId: cid, content: lm)
          : E2eService.preview(
              conversationId: cid,
              otherId: c['other_id'] as String?,
              content: lm,
            );
      job.then((plain) {
        if (mounted) setState(() => _previews[lm] = plain);
      });
    }
  }

  String _time(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _preview(Map<String, dynamic> c) {
    switch (c['last_type']) {
      case 'image':
        return '📷 صورة';
      case 'voice':
        return '🎤 رسالة صوتية';
      case 'video':
        return '🎬 فيديو';
      case 'file':
        return '📎 ملف';
      default:
        final raw = (c['last_message'] as String?) ?? 'ابدأ المحادثة';
        if (E2eService.isEncrypted(raw)) {
          return _previews[raw] ?? '🔒 رسالة مشفرة';
        }
        return raw;
    }
  }

  /// جلب صف المحفوظة (يُنشأ عند أول استخدام) وسطر معاينتها المفكوك
  Future<void> _loadSaved() async {
    try {
      final id = await SavedService.id();
      final last = await SavedService.lastMessage();
      final line = await SavedService.previewLine(last);
      if (!mounted) return;
      setState(() {
        _savedId = id;
        _savedPreview = line;
      });
    } catch (_) {
      // بلا ترحيل 025: لا صف محفوظة وبقية القائمة تعمل
    }
  }

  Widget _savedRow() {
    return ListTile(
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: context.glass,
        child: const Icon(Icons.bookmark_rounded, color: WaslColors.teal),
      ),
      title: const Text(SavedService.title,
          style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
          _savedPreview.isEmpty ? 'احفظ رسائلك وملفاتك هنا' : _savedPreview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      onTap: () => _open(ChatScreen(
        conversationId: _savedId!,
        title: SavedService.title,
        isGroup: true,
        encrypted: true,
        isSaved: true,
      )),
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
    _loadSaved();
  }

  /// حالتي: فتح العارض إن وُجدت حالات، وإلا ورقة النشر
  Future<void> _openMine() async {
    final me = _statusGroups.indexWhere((g) => g['is_me'] == true);
    if (me >= 0) {
      final changed = await openStatusViewer(context, _statusGroups, me);
      if (changed) _loadStatuses();
    } else {
      await showStatusComposer(context);
      _loadStatuses();
    }
  }

  /// فتح حالات صاحب معين من الشريط
  Future<void> _openAuthor(int groupIndex) async {
    final changed = await openStatusViewer(context, _statusGroups, groupIndex);
    if (changed) _loadStatuses();
  }

  void _showNewSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined, color: WaslColors.indigo),
            title: const Text('محادثة جديدة'),
            onTap: () {
              Navigator.pop(ctx);
              _open(const NewChatScreen());
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined, color: WaslColors.teal),
            title: const Text('مجموعة جديدة'),
            onTap: () {
              Navigator.pop(ctx);
              _open(const CreateGroupScreen());
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _setPrefs(Map<String, dynamic> c,
      {bool? pinned, int? muteHours, bool? archived}) async {
    try {
      await supabase.rpc('set_chat_prefs', params: {
        'p_conv': c['conversation_id'],
        'p_pinned': pinned,
        'p_mute_hours': muteHours,
        'p_archived': archived,
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('pin limit')
          ? 'يمكن تثبيت 5 محادثات فقط'
          : 'تعذّر الحفظ';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _chatMenu(Map<String, dynamic> c) {
    final pinned = c['pinned'] == true;
    final muted = c['muted'] == true;
    final archived = c['archived'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            title: Text(_nameOf(c), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          ListTile(
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin, color: WaslColors.teal),
            title: Text(pinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى'),
            onTap: () {
              Navigator.pop(ctx);
              _setPrefs(c, pinned: !pinned);
            },
          ),
          if (muted)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined, color: WaslColors.indigo),
              title: const Text('إلغاء الكتم'),
              onTap: () {
                Navigator.pop(ctx);
                _setPrefs(c, muteHours: 0);
              },
            )
          else ...[
            for (final o in const [(8, 'كتم 8 ساعات'), (168, 'كتم أسبوعاً'), (-1, 'كتم دائماً')])
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined, color: WaslColors.indigo),
                title: Text(o.$2),
                onTap: () {
                  Navigator.pop(ctx);
                  _setPrefs(c, muteHours: o.$1);
                },
              ),
          ],
          ListTile(
            leading: Icon(archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                color: WaslColors.violet),
            title: Text(archived ? 'إخراج من الأرشيف' : 'أرشفة'),
            onTap: () {
              Navigator.pop(ctx);
              _setPrefs(c, archived: !archived);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archivedCount = _chats.where((c) => c['archived'] == true).length;
    final visible =
        _chats.where((c) => (c['archived'] == true) == _showArchived).toList();
    return PopScope(
      canPop: !_showArchived,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _showArchived = false);
      },
      child: Scaffold(
      appBar: AppBar(
        leading: _showArchived
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showArchived = false))
            : null,
        title: Text(_showArchived ? 'المؤرشفة' : 'المحادثات',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ActionChip(
              avatar: const Icon(Icons.auto_awesome, size: 18, color: WaslColors.violet),
              label: const Text('وصل AI'),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AiScreen())),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: WaslFab(onPressed: _showNewSheet, icon: Icons.edit_outlined),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await Future.wait([_load(), _loadStatuses(), _loadSaved()]);
              },
              child: visible.isEmpty && archivedCount == 0 && _savedId == null
                  ? ListView(children: const [
                      SizedBox(height: 60),
                      GlassEmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'لا توجد محادثات بعد',
                        subtitle: 'اضغط زر القلم لبدء محادثتك الأولى،\nوكل رسائلك مشفّرة طرف-لطرف',
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: visible.length +
                          (!_showArchived && _savedId != null ? 1 : 0) +
                          (!_showArchived && archivedCount > 0 ? 1 : 0) +
                          (!_showArchived && _statusGroups.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (!_showArchived && _statusGroups.isNotEmpty) {
                          if (i == 0) {
                            return StatusStrip(
                              groups: _statusGroups,
                              onTapMe: _openMine,
                              onTapAuthor: _openAuthor,
                            );
                          }
                          i -= 1;
                        }
                        if (!_showArchived && _savedId != null) {
                          if (i == 0) return _savedRow();
                          i -= 1;
                        }
                        if (!_showArchived && archivedCount > 0) {
                          if (i == 0) {
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 26,
                                backgroundColor: context.glass,
                                child: const Icon(Icons.archive_outlined, color: WaslColors.violet),
                              ),
                              title: const Text('المؤرشفة',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                              trailing: Text('$archivedCount',
                                  style: TextStyle(color: context.textTertiary)),
                              onTap: () => setState(() => _showArchived = true),
                            );
                          }
                          i -= 1;
                        }
                        final c = visible[i];
                        final pinned = c['pinned'] == true;
                        final muted = c['muted'] == true;
                        final name = _nameOf(c);
                        final isGroup = c['is_group'] == true;
                        final isBot = !isGroup && c['is_bot'] == true;
                        final unread = (c['unread'] as num?)?.toInt() ?? 0;
                        final otherId = c['other_id'] as String?;
                        final groupAvatar = c['avatar_url'] as String?;
                        return ListTile(
                          leading: Stack(clipBehavior: Clip.none, children: [
                            if (isGroup && (groupAvatar ?? '').isNotEmpty)
                              GroupAvatar(
                                conversationId: c['conversation_id'] as String,
                                path: groupAvatar,
                                name: name,
                              )
                            else
                              UserAvatar(
                                name: name,
                                url: isGroup ? null : c['avatar_url'] as String?,
                                color: isGroup ? WaslColors.teal : WaslColors.indigo,
                                icon: isGroup ? Icons.groups_2 : null,
                              ),
                            if (!isGroup)
                              ValueListenableBuilder<Set<String>>(
                                valueListenable: PresenceService.online,
                                builder: (context, online, _) => online.contains(otherId)
                                    ? PositionedDirectional(
                                        bottom: 0,
                                        end: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.shade400,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Theme.of(context).scaffoldBackgroundColor,
                                                width: 2),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                          ]),
                          title: Row(children: [
                            Flexible(
                              child: Text(name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            if (isBot) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.smart_toy_outlined,
                                  size: 15, color: WaslColors.violet),
                            ],
                            if (muted) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.notifications_off_outlined,
                                  size: 16, color: context.textFaint),
                            ],
                            if (pinned) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.push_pin, size: 15, color: context.textFaint),
                            ],
                          ]),
                          onLongPress: () => _chatMenu(c),
                          subtitle: Text(_preview(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitleTextStyle: unread > 0
                              ? TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600)
                              : null,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_time(c['last_at'] as String?),
                                  style: TextStyle(
                                      color: unread > 0 ? WaslColors.teal : context.textFaint,
                                      fontSize: 12)),
                              if (unread > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: muted ? null : WaslColors.gradient,
                                    color: muted ? context.hairline : null,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(unread > 99 ? '99+' : '$unread',
                                      style: TextStyle(
                                          color: muted ? context.textPrimary : Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          onTap: () => _open(ChatScreen(
                            conversationId: c['conversation_id'] as String,
                            title: name,
                            isGroup: isGroup,
                            otherId: otherId,
                            isBot: isBot,
                            encrypted: isGroup || !isBot,
                          )),
                        );
                      },
                    ),
            ),
    ),
    );
  }
}
