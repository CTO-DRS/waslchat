import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/e2e_service.dart';
import '../theme.dart';

/// شاشة سلسلة الردود (المرحلة 3 — 0.5.1): تعرض رسالة الجذر وردود سلسلتها
/// حية بثّاً مباشراً، والرد داخلها نص مشفّر بنفس مفتاح المحادثة (خاضع
/// لسياسة can_send الخادمية كأي رسالة). الرد داخل السلسلة نص فقط في هذا
/// الإصدار — الوسائط داخل السلاسل في إصدار لاحق.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.root,
    required this.myId,
    required this.names,
    this.isGroup = false,
    this.isChannel = false,
    this.encrypted = false,
    this.canPost = true,
    this.otherId,
  });

  final String conversationId;
  final String title;
  final Map<String, dynamic> root;
  final String myId;
  final Map<String, String> names;
  final bool isGroup;
  final bool isChannel;
  final bool encrypted;
  final bool canPost;
  final String? otherId;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream;
  final TextEditingController _text = TextEditingController();
  final Map<String, String> _plain = {};
  final Set<String> _decrypting = {};
  bool _sending = false;

  bool get _e2e => widget.encrypted && !widget.isChannel;

  @override
  void initState() {
    super.initState();
    // رسائل السلسلة فقط: الجذر يُعرض من الرسالة الممرّرة (الشاشة الأم)
    _stream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('thread_root_id', widget.root['id'] as String)
        .order('created_at', ascending: true);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<SecretKey?> _convKey({bool fresh = false}) async {
    if (!widget.isGroup) {
      final other = widget.otherId;
      if (other == null) return null;
      return E2eService.dmKey(widget.conversationId, other);
    }
    return E2eService.groupKey(widget.conversationId, fresh: fresh);
  }

  /// نسخة خفيفة من فك الشاشة الأم: محاولة واحدة، وعند الفشل إبطال الكاش
  /// وإعادة الاشتقاق مرة واحدة (دوران مفتاح المجموعة أو تبديل مفتاح الخاص)
  Future<String?> _decrypt(String content) async {
    if (!_e2e) {
      return E2eService.isEncrypted(content) ? null : content;
    }
    Future<String?> tryOnce() async {
      final key = await _convKey();
      if (key == null) return null;
      return E2eService.decryptText(key, widget.conversationId, content);
    }

    var plain = await tryOnce();
    if (plain == null) {
      if (widget.isGroup) {
        E2eService.invalidateGroupKey(widget.conversationId);
      } else if (widget.otherId != null) {
        E2eService.invalidateDmKey(widget.conversationId, widget.otherId!);
      }
      plain = await tryOnce();
    }
    return plain;
  }

  void _scheduleDecrypt(String content) {
    if (!E2eService.isEncrypted(content)) return;
    if (_plain.containsKey(content)) return;
    if (!_decrypting.add(content)) return;
    () async {
      final plain = await _decrypt(content);
      if (mounted && !_plain.containsKey(content)) {
        setState(() =>
            _plain[content] = plain ?? '🔒 تعذّر فك التشفير');
      }
      _decrypting.remove(content);
    }();
  }

  String? _textOf(Map<String, dynamic> m) {
    final raw = m['content'] as String? ?? '';
    final t = E2eService.isEncrypted(raw) ? _plain[raw] : raw;
    return (t == null || t.isEmpty) ? t : t;
  }

  String _senderName(String? id) {
    if (id == widget.myId) return 'أنت';
    return widget.names[id] ?? (widget.isGroup ? 'عضو' : widget.title);
  }

  String _when(dynamic createdAt) {
    try {
      final d = DateTime.parse(createdAt as String).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · ${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _sendReply() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) return;
    if (!widget.canPost) return;
    setState(() => _sending = true);
    try {
      var payload = content;
      if (_e2e) {
        if (!E2eService.withinPlainLimit(content)) {
          _snack('الرد طويل جداً');
          return;
        }
        final key = await _convKey(fresh: true);
        if (key == null) {
          _snack('مفتاح التشفير غير جاهز');
          return;
        }
        payload = await E2eService.encryptText(
            key, widget.conversationId, content);
      }
      _text.clear();
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': widget.myId,
        'type': 'text',
        'content': payload,
        'thread_root_id': widget.root['id'] as String,
      });
    } catch (_) {
      _snack('تعذّر إرسال الرد (قد يكون النشر مقيداً في الغرفة)');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  /// معاينة الجذر: نوع الوسائط مكشوف بعنوانه، النص يفك محلياً
  String _rootPreview() {
    final m = widget.root;
    switch (m['type'] as String? ?? 'text') {
      case 'image':
        return '📷 صورة';
      case 'voice':
        return '🎤 رسالة صوتية';
      case 'video':
        return '🎬 فيديو';
      case 'file':
        return '📎 ملف';
      case 'sticker':
        return '🩹 ملصق';
      case 'poll':
        return '📊 استطلاع رأي';
      case 'location':
        return '📍 موقع';
      case 'contact':
        return '👤 جهة اتصال';
      default:
        return _textOf(m) ?? '🔒 رسالة مشفرة';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🧵 سلسلة الردود', style: TextStyle(fontSize: 16)),
          Text(widget.title,
              style: TextStyle(
                  fontSize: 12, color: context.wasl.textFaint),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          _rootCard(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                final msgs =
                    (snap.data ?? const []).map(Map<String, dynamic>.from).toList();
                for (final m in msgs) {
                  final raw = m['content'] as String?;
                  if (raw != null) _scheduleDecrypt(raw);
                }
                if (msgs.isEmpty) {
                  return Center(
                    child: Text('لا ردود في السلسلة بعد',
                        style: TextStyle(color: context.wasl.textFaint)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _replyBubble(msgs[i]),
                );
              },
            ),
          ),
          if (widget.canPost) _composer(),
        ]),
      ),
    );
  }

  /// بطاقة الجذر المميزة أعلى الشاشة
  Widget _rootCard() {
    final m = widget.root;
    final mine = m['sender_id'] == widget.myId;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.wasl.glass,
        borderRadius: BorderRadius.circular(14),
        border: BorderDirectional(
          start: BorderSide(
              color: mine ? WaslColors.indigo : WaslColors.teal, width: 3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                '${_senderName(m['sender_id'] as String?)} · ${_when(m['created_at'])}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.wasl.textFaint)),
          ),
          const Text('رسالة الجذر',
              style: TextStyle(fontSize: 11, color: WaslColors.teal)),
        ]),
        const SizedBox(height: 6),
        Text(_rootPreview(),
            style: const TextStyle(fontSize: 15, height: 1.4),
            maxLines: 6,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _replyBubble(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('حُذفت هذا الرد',
              style: TextStyle(fontSize: 12, color: context.wasl.textFaint)),
        ),
      );
    }
    final mine = m['sender_id'] == widget.myId;
    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? WaslColors.indigo : context.wasl.surface,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(mine ? 16 : 4),
            bottomEnd: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine && widget.isGroup)
            Text(_senderName(m['sender_id'] as String?),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: WaslColors.teal)),
          Text(_textOf(m) ?? '🔒 تعذّر فك التشفير',
              style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: mine ? Colors.white : null)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(_when(m['created_at']),
                style: TextStyle(
                    fontSize: 10,
                    color: mine ? Colors.white70 : context.wasl.textFaint)),
          ),
        ]),
      ),
    );
  }

  Widget _composer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.wasl.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.wasl.glass),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendReply(),
            decoration: const InputDecoration(
              hintText: 'ردّ في السلسلة…',
              border: InputBorder.none,
            ),
          ),
        ),
        IconButton(
          onPressed: _sending ? null : _sendReply,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded, color: WaslColors.teal),
        ),
      ]),
    );
  }
}
