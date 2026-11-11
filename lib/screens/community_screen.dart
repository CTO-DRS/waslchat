import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// غرف المجتمع: «الإعلانات» (للمشرفين) + غرف النقاش
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.communityId,
    required this.name,
    required this.role,
  });
  final String communityId;
  final String name;
  final String role;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;

  bool get _isAdmin => widget.role == 'owner' || widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await supabase.rpc('community_rooms', params: {'cid': widget.communityId});
      if (mounted) {
        setState(() {
          _rooms = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRoom() async {
    final res = await askNameAndDescription(context,
        title: 'غرفة جديدة', nameHint: 'اسم الغرفة', withDescription: false);
    if (res == null) return;
    try {
      await supabase.rpc('create_room', params: {'cid': widget.communityId, 'p_title': res.$1});
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر إنشاء الغرفة')));
      }
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final isChannel = r['kind'] == 'channel';
    final role = r['role'] as String? ?? 'member';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: r['conversation_id'] as String,
          title: '${widget.name} · ${r['title']}',
          isGroup: true,
          isChannel: isChannel,
          canPost: !isChannel || role == 'owner' || role == 'admin',
          encrypted: false, // غرف المجتمعات غير مشفّرة في هذه المرحلة (خطة E2EE §6)
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_isAdmin)
            IconButton(
                tooltip: 'غرفة جديدة', onPressed: _addRoom, icon: const Icon(Icons.add_comment_outlined)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _rooms.length,
                itemBuilder: (context, i) {
                  final r = _rooms[i];
                  final isChannel = r['kind'] == 'channel';
                  final unread = (r['unread'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isChannel ? WaslColors.violet : WaslColors.indigo,
                      child: Icon(isChannel ? Icons.campaign : Icons.tag, color: Colors.white),
                    ),
                    title: Text(r['title'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(previewText(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(shortTime(r['last_at'] as String?),
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        UnreadBadge(unread),
                      ],
                    ),
                    onTap: () => _open(r),
                  );
                },
              ),
            ),
    );
  }
}
