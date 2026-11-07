import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/presence_service.dart';
import '../theme.dart';
import 'ai_screen.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'new_chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
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
      setState(() {
        _chats = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
      default:
        return (c['last_message'] as String?) ?? 'ابدأ المحادثة';
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  void _showNewSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: WaslColors.darkSurface,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحادثات', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
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
        child: FloatingActionButton(
          backgroundColor: WaslColors.indigo,
          onPressed: _showNewSheet,
          child: const Icon(Icons.edit_outlined, color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _chats.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 160),
                      Center(
                          child: Text('لا توجد محادثات بعد.\nاضغط ✏️ لبدء محادثة جديدة',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white60))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: _chats.length,
                      itemBuilder: (context, i) {
                        final c = _chats[i];
                        final name = (c['title'] ?? '') as String;
                        final isGroup = c['is_group'] == true;
                        final unread = (c['unread'] as num?)?.toInt() ?? 0;
                        final otherId = c['other_id'] as String?;
                        return ListTile(
                          leading: Stack(clipBehavior: Clip.none, children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: isGroup ? WaslColors.teal : WaslColors.indigo,
                              child: isGroup
                                  ? const Icon(Icons.groups_2, color: Colors.white)
                                  : Text(name.isNotEmpty ? name.characters.first : '?',
                                      style: const TextStyle(color: Colors.white, fontSize: 20)),
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
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(_preview(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitleTextStyle: unread > 0
                              ? const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)
                              : null,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_time(c['last_at'] as String?),
                                  style: TextStyle(
                                      color: unread > 0 ? WaslColors.teal : Colors.white54,
                                      fontSize: 12)),
                              if (unread > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: WaslColors.gradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(unread > 99 ? '99+' : '$unread',
                                      style: const TextStyle(
                                          color: Colors.white,
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
                          )),
                        );
                      },
                    ),
            ),
    );
  }
}
