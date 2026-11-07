import 'dart:async';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/ai_service.dart';
import '../services/e2e_service.dart';
import '../services/media_service.dart';
import '../services/presence_service.dart';
import '../theme.dart';
import '../widgets/media_bubbles.dart';
import 'group_info_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.isGroup = false,
    this.otherId,
    this.isChannel = false,
    this.canPost = true,
    this.encrypted = false,
  });
  final String conversationId;
  final String title;
  final bool isGroup;
  final String? otherId;
  final bool isChannel;
  final bool canPost;

  /// تشفير بين الطرفين (خاص + مجموعات خاصة فقط؛ القنوات وغرف المجتمعات لا)
  final bool encrypted;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  final _picker = ImagePicker();
  late final Stream<List<Map<String, dynamic>>> _stream;
  final String _me = supabase.auth.currentUser!.id;

  Map<String, String> _names = {};
  late String _title = widget.title;

  // الرد والتعديل والتفاعلات
  Map<String, dynamic>? _replyTo;
  Map<String, dynamic>? _editing;
  Map<String, Map<String, dynamic>> _byId = {};
  StreamSubscription<List<Map<String, dynamic>>>? _reactSub;
  Map<String, Map<String, String>> _reactions = {}; // msgId -> (userId -> emoji)
  static const _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  bool _recording = false;
  bool _uploading = false;
  DateTime? _recStart;
  Timer? _ticker;

  // التشفير بين الطرفين (المحادثات الخاصة والمجموعات الخاصة)
  // نص فك التشفير لكل نص مشفّر: ciphertext -> النص الصريح (يتغيّر النص المشفّر عند التعديل)
  final Map<String, String> _plain = {};
  bool get _e2e => widget.encrypted && !widget.isChannel;

  /// مفتاح المحادثة: اشتقاق ECDH للخاص، أو مفتاح المجموعة للمجموعة الخاصة
  Future<SecretKey?> _convKey() async {
    if (!widget.isGroup) {
      final other = widget.otherId;
      if (other == null) return null;
      return E2eService.dmKey(widget.conversationId, other);
    }
    return E2eService.groupKey(widget.conversationId);
  }

  /// يفك نصاً مشفّراً واحداً (للمجموعات: يجرّب كل إصدارات المفتاح المعروفة)
  Future<String?> _decrypt(String content) async {
    if (!widget.isGroup) {
      final key = await _convKey();
      return key == null ? null : E2eService.decryptText(key, widget.conversationId, content);
    }
    var plain = await E2eService.decryptGroupText(widget.conversationId, content);
    if (plain == null) {
      // ربما دُوِّر المفتاح أو وصل ظرف جديد: نعيد الجلب مرة
      E2eService.invalidateGroupKey(widget.conversationId);
      plain = await E2eService.decryptGroupText(widget.conversationId, content);
    }
    return plain;
  }

  final Set<String> _decrypting = {};

  Future<void> _decryptInto(String content) async {
    if (!_decrypting.add(content)) return;
    final plain = await _decrypt(content);
    if (mounted && !_plain.containsKey(content)) {
      setState(() => _plain[content] = plain ?? '🔒 تعذّر فك التشفير');
    }
    _decrypting.remove(content);
  }

  /// النص المعروض لرسالة نصية (null إن كانت ما زالت قيد فك التشفير)
  String? _textOf(Map<String, dynamic> m) {
    final raw = m['content'] as String? ?? '';
    return E2eService.isEncrypted(raw) ? _plain[raw] : raw;
  }

  /// يفك تشفير الرسائل النصية المشفّرة الجديدة في الخلفية
  void _scheduleDecrypt(List<Map<String, dynamic>> msgs) {
    if (!_e2e) return;
    for (final m in msgs) {
      if ((m['type'] ?? 'text') != 'text') continue;
      if (m['deleted_at'] != null) continue;
      final content = m['content'] as String? ?? '';
      if (!E2eService.isEncrypted(content) || _plain.containsKey(content)) continue;
      unawaited(_decryptInto(content));
    }
  }

  // يكتب الآن + علامات القراءة
  late final RealtimeChannel _room;
  StreamSubscription<List<Map<String, dynamic>>>? _partsSub;
  final Map<String, DateTime> _typing = {};
  Timer? _typingSweep;
  DateTime _lastTypingSent = DateTime(2000);
  DateTime? _othersReadUpTo;
  String? _lastMarkedId;

  @override
  void initState() {
    super.initState();
    _stream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: true);
    _text.addListener(_onTextChanged);
    if (widget.isGroup) _loadMembers();

    // بث «يكتب الآن» بين أعضاء المحادثة
    _room = supabase.channel('room:${widget.conversationId}');
    _room
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final data = payload['payload'] is Map ? payload['payload'] as Map : payload;
            final uid = data['user_id'];
            if (uid is! String || uid == _me || !mounted) return;
            setState(() => _typing[uid] = DateTime.now());
          },
        )
        .subscribe();
    _typingSweep = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final before = _typing.length;
      _typing.removeWhere((_, t) => now.difference(t).inSeconds >= 4);
      if (_typing.length != before && mounted) setState(() {});
    });

    // متى قرأ الآخرون؟ (لعلامة ✓✓)
    _partsSub = supabase
        .from('conversation_participants')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', widget.conversationId)
        .listen((rows) {
      DateTime? minRead;
      for (final r in rows) {
        if (r['user_id'] == _me || r['last_read_at'] == null) continue;
        final t = DateTime.parse(r['last_read_at'] as String);
        if (minRead == null || t.isBefore(minRead)) minRead = t;
      }
      if (mounted) setState(() => _othersReadUpTo = minRead);
    });

    _reactSub = supabase
        .from('message_reactions')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('conversation_id', widget.conversationId)
        .listen((rows) {
      final map = <String, Map<String, String>>{};
      for (final r in rows) {
        (map[r['message_id'] as String] ??= {})[r['user_id'] as String] = r['emoji'] as String;
      }
      if (mounted) setState(() => _reactions = map);
    }, onError: (_) {});

    PresenceService.online.addListener(_onPresence);
    supabase.rpc('mark_read', params: {'conv': widget.conversationId});
  }

  void _onPresence() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    setState(() {});
    final now = DateTime.now();
    if (_text.text.trim().isNotEmpty &&
        now.difference(_lastTypingSent).inMilliseconds > 2000) {
      _lastTypingSent = now;
      _room.sendBroadcastMessage(event: 'typing', payload: {'user_id': _me});
    }
  }

  /// نعلّم المحادثة مقروءة عند وصول رسالة جديدة من الآخرين
  void _maybeMarkRead(List<Map<String, dynamic>> newestFirst) {
    if (newestFirst.isEmpty) return;
    final last = newestFirst.first;
    final id = last['id'] as String;
    if (id == _lastMarkedId || last['sender_id'] == _me) return;
    _lastMarkedId = id;
    supabase.rpc('mark_read', params: {'conv': widget.conversationId});
  }

  String? _statusLine() {
    if (_typing.isNotEmpty) {
      if (!widget.isGroup) return 'يكتب الآن...';
      final names = _typing.keys.map((id) => _names[id] ?? '').where((n) => n.isNotEmpty);
      return names.isEmpty ? 'أحدهم يكتب...' : '${names.join('، ')} يكتب...';
    }
    if (widget.isGroup) {
      if (_names.isEmpty) return null;
      return widget.isChannel ? '${_names.length} متابع' : '${_names.length} أعضاء';
    }
    return PresenceService.isOnline(widget.otherId) ? 'متصل الآن' : null;
  }

  Widget _ticks(Map<String, dynamic> m) {
    final created = DateTime.parse(m['created_at'] as String);
    final read = _othersReadUpTo != null && !created.isAfter(_othersReadUpTo!);
    return Icon(read ? Icons.done_all_rounded : Icons.done_rounded,
        size: 15, color: read ? const Color(0xFF7DF9FF) : Colors.white70);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _typingSweep?.cancel();
    _partsSub?.cancel();
    _reactSub?.cancel();
    PresenceService.online.removeListener(_onPresence);
    supabase.removeChannel(_room);
    supabase.rpc('mark_read', params: {'conv': widget.conversationId});
    _recorder.dispose();
    _text.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadMembers() async {
    try {
      final rows = await supabase
          .from('conversation_participants')
          .select('user_id, profiles(username, display_name)')
          .eq('conversation_id', widget.conversationId);
      final map = <String, String>{};
      for (final r in rows) {
        final p = r['profiles'] as Map<String, dynamic>?;
        map[r['user_id'] as String] =
            (p?['display_name'] ?? p?['username'] ?? '') as String;
      }
      if (mounted) setState(() => _names = map);
    } catch (_) {}
  }

  String _keyMissingMsg() {
    if (!E2eService.isReady) {
      return 'مفتاح التشفير غير مفعّل على هذا الجهاز: الإعدادات ← مفتاح التشفير';
    }
    if (widget.isGroup) {
      return 'بانتظار عضو في المجموعة يفتحها ليشارك مفتاح التشفير معك';
    }
    return 'التشفير غير جاهز: الطرف الآخر يحتاج تحديث التطبيق وفتحه';
  }

  // ---------- رمز الأمان ----------
  bool get _showSafety => _e2e && !widget.isGroup && widget.otherId != null;

  Future<void> _showSafetyNumber() async {
    final other = widget.otherId!;
    final number = await E2eService.safetyNumber(other);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('رمز الأمان'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'قارن هذا الرمز مع جوال الطرف الآخر وجهاً لوجه أو بمكالمة. إن تطابق فمحادثتكما مشفّرة ولا أحد في المنتصف.',
              style: TextStyle(height: 1.6)),
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(number ?? 'المفاتيح غير جاهزة بعد',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 18, letterSpacing: 1.5, height: 1.7)),
          ),
        ]),
        actions: [
          if (number != null && E2eService.peerKeyChanged(other))
            TextButton(
              onPressed: () {
                E2eService.acknowledgePeerKey(other);
                Navigator.pop(c);
              },
              child: const Text('تحققت، أخفِ التنبيه'),
            ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('تم')),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  /// موافقة صريحة قبل إرسال نص محادثة مشفّرة إلى الذكاء الاصطناعي
  Future<void> _confirmSummarize() async {
    if (_e2e) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تلخيص محادثة مشفّرة'),
          content: const Text(
              'للتلخيص، يفك جوالك آخر 80 رسالة ويرسل نصها إلى خادم وصل ثم إلى Google Gemini. هذا النص لن يكون مشفّراً بين الطرفين أثناء التلخيص. تتابع؟',
              style: TextStyle(height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('لخّص')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _showAiResult('ملخص المحادثة', _summarize());
  }

  // ---------- إرسال ----------
  Future<void> _sendText() async {
    final content = _text.text.trim();
    if (content.isEmpty) return;
    final editing = _editing;
    final replyTo = _replyTo;
    var payload = content;
    if (_e2e) {
      if (!E2eService.withinPlainLimit(content)) {
        _snack('الرسالة طويلة جداً');
        return;
      }
      final key = await _convKey();
      if (key == null) {
        _snack(_keyMissingMsg());
        return;
      }
      try {
        payload = await E2eService.encryptText(key, widget.conversationId, content);
      } catch (_) {
        _snack('تعذّر تشفير الرسالة');
        return;
      }
    }
    _text.clear();
    setState(() {
      _editing = null;
      _replyTo = null;
    });
    if (editing != null) {
      try {
        await supabase
            .rpc('edit_message', params: {'p_id': editing['id'], 'p_content': payload});
      } catch (_) {
        _snack('تعذّر تعديل الرسالة (التعديل متاح خلال 48 ساعة)');
      }
      return;
    }
    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'type': 'text',
        'content': payload,
        if (replyTo != null) 'reply_to': replyTo['id'],
      });
    } catch (_) {
      _snack('تعذّر إرسال الرسالة');
    }
  }

  Future<void> _sendMedia({
    required String type,
    required Uint8List bytes,
    required String ext,
    required String contentType,
    int? durationMs,
  }) async {
    setState(() => _uploading = true);
    try {
      var payload = bytes;
      var upExt = ext;
      var upType = contentType;
      if (_e2e) {
        final key = await _convKey();
        if (key == null) {
          _snack(_keyMissingMsg());
          return;
        }
        payload = await E2eService.encryptBytes(key, widget.conversationId, bytes);
        upExt = 'enc.bin';
        upType = 'application/octet-stream';
      }
      final path = await MediaService.upload(
        conversationId: widget.conversationId,
        bytes: payload,
        ext: upExt,
        contentType: upType,
      );
      final replyTo = _replyTo;
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'type': type,
        'content': '',
        'media_url': path,
        'duration_ms': durationMs,
        if (replyTo != null) 'reply_to': replyTo['id'],
      });
      if (mounted) setState(() => _replyTo = null);
    } catch (_) {
      _snack('تعذّر رفع الملف');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------- الصور ----------
  Future<void> _pickImage(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    var ext = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'jpg';
    if (ext == 'jpg') ext = 'jpeg';
    await _sendMedia(
      type: 'image',
      bytes: bytes,
      ext: ext,
      contentType: 'image/$ext',
    );
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: WaslColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: WaslColors.teal),
            title: const Text('صورة من المعرض'),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: WaslColors.indigo),
              title: const Text('الكاميرا'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
        ]),
      ),
    );
  }

  // ---------- التسجيل الصوتي (اضغط مطولاً) ----------
  Future<void> _startRec() async {
    if (kIsWeb) {
      _snack('التسجيل الصوتي متاح على تطبيق الجوال');
      return;
    }
    if (!await _recorder.hasPermission()) {
      _snack('اسمح للتطبيق باستخدام الميكروفون');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
    });
  }

  Future<void> _stopRec({bool cancel = false}) async {
    if (!_recording) return;
    _ticker?.cancel();
    final path = await _recorder.stop();
    final ms = DateTime.now().difference(_recStart!).inMilliseconds;
    setState(() => _recording = false);
    if (cancel || path == null || ms < 700) return;
    final bytes = await XFile(path).readAsBytes();
    await _sendMedia(
      type: 'voice',
      bytes: bytes,
      ext: 'm4a',
      contentType: 'audio/mp4',
      durationMs: ms,
    );
  }

  String _recLabel() {
    final s = _recStart == null ? 0 : DateTime.now().difference(_recStart!).inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _time(String iso) {
    final d = DateTime.parse(iso).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// تنزيل وسيط وفكّ تشفيره إن كان مشفّراً (null = فشل)
  Future<Uint8List?> _mediaBytes(String path) async {
    try {
      final raw = await MediaService.download(path);
      if (!E2eService.isEncryptedPath(path) || !_e2e) return raw;
      if (!widget.isGroup) {
        final key = await _convKey();
        if (key == null) return null;
        return await E2eService.decryptBytes(key, widget.conversationId, raw);
      }
      var out = await E2eService.decryptGroupBytes(widget.conversationId, raw);
      if (out == null) {
        E2eService.invalidateGroupKey(widget.conversationId);
        out = await E2eService.decryptGroupBytes(widget.conversationId, raw);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Widget _body(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      return const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 16, color: Colors.white60),
        SizedBox(width: 6),
        Text('حُذفت هذه الرسالة',
            style: TextStyle(color: Colors.white60, fontStyle: FontStyle.italic)),
      ]);
    }
    switch (m['type'] as String? ?? 'text') {
      case 'image':
        return ImageBubble(loader: () => _mediaBytes(m['media_url'] as String));
      case 'voice':
        return VoiceBubble(
            loader: () => _mediaBytes(m['media_url'] as String),
            durationMs: m['duration_ms'] as int?);
      default:
        final text = _textOf(m) ?? '🔒 جارٍ فك التشفير…';
        return Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 16));
    }
  }

  // ---------- وصل AI ----------
  /// التلخيص بعد E2E: التطبيق يجلب آخر 80 رسالة، يفك تشفيرها محلياً، ويرسل الأسطر للدالة
  Future<String> _summarize() async {
    final rows = await supabase
        .from('messages')
        .select('id, content, type, deleted_at, profiles(display_name, username)')
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: false)
        .limit(80);
    final msgs = rows.reversed.toList();
    final lines = <String>[];
    for (final item in msgs) {
      final m = item;
      final p = m['profiles'] as Map<String, dynamic>?;
      final who = (p?['display_name'] ?? p?['username'] ?? '؟') as String;
      final type = m['type'] ?? 'text';
      if (m['deleted_at'] != null) continue;
      String what;
      if (type == 'image') {
        what = '[صورة]';
      } else if (type == 'voice') {
        what = '[رسالة صوتية]';
      } else {
        final raw = (m['content'] ?? '') as String;
        if (E2eService.isEncrypted(raw)) {
          if (!_e2e) continue;
          final plain = _plain[raw] ?? await _decrypt(raw);
          if (plain == null) continue;
          what = plain;
        } else {
          what = raw;
        }
      }
      lines.add('$who: $what');
    }
    if (lines.isEmpty) return 'لا توجد رسائل لتلخيصها بعد.';
    return AiService.summarizeLines(lines);
  }

  void _showAiResult(String title, Future<String> job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: WaslColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<String>(
            future: job,
            builder: (ctx, s) {
              final text = s.hasError
                  ? 'تعذّر الوصول للمساعد الآن، حاول بعد قليل.'
                  : s.data;
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, color: WaslColors.violet),
                      const SizedBox(width: 8),
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (text != null)
                        IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: text));
                            Navigator.pop(ctx);
                            _snack('تم النسخ');
                          },
                        ),
                    ]),
                    const SizedBox(height: 12),
                    if (text == null)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: SelectableText(text,
                              style: const TextStyle(fontSize: 16, height: 1.6)),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------- الرد / التعديل / الحذف / التفاعل ----------

  String _previewOf(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return 'حُذفت هذه الرسالة';
    switch (m['type'] as String? ?? 'text') {
      case 'image':
        return '📷 صورة';
      case 'voice':
        return '🎤 رسالة صوتية';
      default:
        final t = _textOf(m) ?? '🔒 رسالة مشفرة';
        return t.length > 120 ? '${t.substring(0, 120)}…' : t;
    }
  }

  String _senderName(String? id) {
    if (id == _me) return 'أنت';
    return _names[id] ?? (widget.isGroup ? '' : _title);
  }

  bool _canEdit(Map<String, dynamic> m) {
    if (m['sender_id'] != _me || m['deleted_at'] != null) return false;
    if ((m['type'] ?? 'text') != 'text') return false;
    final created = DateTime.parse(m['created_at'] as String);
    return DateTime.now().toUtc().difference(created.toUtc()).inHours < 48;
  }

  Future<void> _react(Map<String, dynamic> m, String emoji) async {
    final mine = _reactions[m['id']]?[_me];
    try {
      await supabase.rpc('react_message',
          params: {'p_id': m['id'], 'p_emoji': mine == emoji ? '' : emoji});
    } catch (_) {
      _snack('تعذّر إرسال التفاعل');
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف للجميع؟'),
        content: const Text('ستُحذف الرسالة عند كل أعضاء المحادثة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final media = await supabase.rpc('delete_message', params: {'p_id': m['id']});
      if (media is String && media.isNotEmpty) unawaited(MediaService.remove(media));
      if (_replyTo?['id'] == m['id']) setState(() => _replyTo = null);
    } catch (_) {
      _snack('تعذّر حذف الرسالة');
    }
  }

  void _startEdit(Map<String, dynamic> m) {
    final t = _textOf(m);
    if (t == null) return;
    setState(() {
      _editing = m;
      _replyTo = null;
      _text.text = t;
      _text.selection = TextSelection.collapsed(offset: t.length);
    });
  }

  void _messageActions(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return;
    final isText = (m['type'] ?? 'text') == 'text';
    final text = isText ? _textOf(m) : null;
    if (isText && text == null) {
      _snack('جارٍ فك التشفير… حاول بعد لحظة');
      return;
    }
    final arabic = text != null && RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    final mine = m['sender_id'] == _me;
    final myReaction = _reactions[m['id']]?[_me];
    showModalBottomSheet(
      context: context,
      backgroundColor: WaslColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final e in _quickEmojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.pop(ctx);
                      _react(m, e);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: myReaction == e ? WaslColors.glass : null,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.canPost)
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('رد'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyTo = m;
                  _editing = null;
                });
              },
            ),
          if (text != null)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
                _snack('تم النسخ');
              },
            ),
          if (_canEdit(m))
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _startEdit(m);
              },
            ),
          if (text != null)
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: WaslColors.violet),
              title: Text(arabic ? 'ترجمة إلى الإنجليزية' : 'ترجمة إلى العربية'),
              onTap: () {
                Navigator.pop(ctx);
                _showAiResult('الترجمة', AiService.translate(text, arabic ? 'en' : 'ar'));
              },
            ),
          if (mine)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('حذف للجميع', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(m);
              },
            ),
        ]),
      ),
    );
  }

  /// اقتباس الرسالة المردود عليها داخل الفقاعة
  Widget _quote(String replyId, bool mine) {
    final r = _byId[replyId];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: const BorderDirectional(start: BorderSide(color: WaslColors.teal, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (r != null && _senderName(r['sender_id'] as String?).isNotEmpty)
          Text(_senderName(r['sender_id'] as String?),
              style: const TextStyle(
                  color: WaslColors.teal, fontSize: 12, fontWeight: FontWeight.bold)),
        Text(r == null ? 'رسالة غير متاحة' : _previewOf(r),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  /// شارات التفاعلات تحت الفقاعة
  Widget? _reactionChips(Map<String, dynamic> m) {
    final r = _reactions[m['id']];
    if (r == null || r.isEmpty) return null;
    final counts = <String, int>{};
    for (final e in r.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final mineEmoji = r[_me];
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(spacing: 4, children: [
        for (final e in counts.entries)
          GestureDetector(
            onTap: () => _react(m, e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: mineEmoji == e.key ? WaslColors.teal.withValues(alpha: 0.35) : WaslColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(e.value > 1 ? '${e.key} ${e.value}' : e.key,
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
      ]),
    );
  }

  /// شريط الرد/التعديل فوق حقل الكتابة
  Widget? _composeBanner() {
    final m = _editing ?? _replyTo;
    if (m == null) return null;
    final editing = _editing != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: WaslColors.glass,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(editing ? Icons.edit_outlined : Icons.reply_rounded, color: WaslColors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editing ? 'تعديل الرسالة' : 'رد على ${_senderName(m['sender_id'] as String?)}',
                style: const TextStyle(
                    color: WaslColors.teal, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(_previewOf(m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(() {
            if (editing) _text.clear();
            _editing = null;
            _replyTo = null;
          }),
        ),
      ]),
    );
  }

  // ---------- معلومات المجموعة ----------
  bool get _isPrivateGroup => widget.isGroup && !widget.isChannel && widget.encrypted;

  Future<void> _openGroupInfo() async {
    final r = await Navigator.push<GroupInfoResult>(
      context,
      MaterialPageRoute(
          builder: (_) => GroupInfoScreen(conversationId: widget.conversationId, title: _title)),
    );
    if (!mounted || r == null) return;
    if (r.left) {
      Navigator.pop(context);
      return;
    }
    if (r.title != null && r.title != _title) setState(() => _title = r.title!);
    _loadMembers();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _text.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
         onTap: _isPrivateGroup ? _openGroupInfo : null,
         behavior: HitTestBehavior.opaque,
         child: Row(children: [
          CircleAvatar(
            backgroundColor: widget.isGroup ? WaslColors.teal : WaslColors.indigo,
            child: widget.isGroup
                ? Icon(widget.isChannel ? Icons.campaign : Icons.groups_2, color: Colors.white)
                : Text(_title.isNotEmpty ? _title.characters.first : '?',
                    style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              if (_statusLine() != null)
                Text(_statusLine()!,
                    style: TextStyle(
                        fontSize: 12,
                        color: _typing.isNotEmpty ? WaslColors.teal : Colors.white60)),
            ]),
          ),
         ]),
        ),
        actions: [
          if (_isPrivateGroup)
            IconButton(
              tooltip: 'معلومات المجموعة',
              onPressed: _openGroupInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          if (_showSafety)
            IconButton(
              tooltip: 'رمز الأمان',
              onPressed: _showSafetyNumber,
              icon: Icon(Icons.verified_user_outlined,
                  color: E2eService.peerKeyChanged(widget.otherId!)
                      ? Colors.amber
                      : WaslColors.teal),
            ),
          IconButton(
            tooltip: 'لخّص المحادثة',
            onPressed: _confirmSummarize,
            icon: const Icon(Icons.auto_awesome, color: WaslColors.violet),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSafety && E2eService.peerKeyChanged(widget.otherId!))
            Material(
              color: const Color(0x33FFC107),
              child: InkWell(
                onTap: _showSafetyNumber,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber),
                    SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'تغيّر رمز الأمان لهذا الشخص (ربما غيّر جواله). اضغط للتحقق.')),
                  ]),
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final msgs = snap.data!.reversed.toList();
                _byId = {for (final m in msgs) m['id'] as String: m};
                WidgetsBinding.instance.addPostFrameCallback((_) => _maybeMarkRead(msgs));
                _scheduleDecrypt(msgs);
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final mine = m['sender_id'] == _me;
                    final sender = _names[m['sender_id']];
                    final replyId = m['reply_to'] as String?;
                    final chips = _reactionChips(m);
                    return Align(
                      alignment: mine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: GestureDetector(
                       onLongPress: () => _messageActions(m),
                       child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          gradient: mine ? WaslColors.gradient : null,
                          color: mine ? null : WaslColors.darkSurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isGroup && !mine && sender != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(sender,
                                    style: const TextStyle(
                                        color: WaslColors.teal,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                            if (replyId != null && m['deleted_at'] == null)
                              _quote(replyId, mine),
                            _body(m),
                            if (chips != null) chips,
                            const SizedBox(height: 2),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (m['edited_at'] != null && m['deleted_at'] == null) ...[
                                const Text('معدّلة',
                                    style: TextStyle(color: Colors.white60, fontSize: 11)),
                                const SizedBox(width: 4),
                              ],
                              Text(_time(m['created_at'] as String),
                                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              if (mine) ...[const SizedBox(width: 4), _ticks(m)],
                            ]),
                          ],
                        ),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_uploading) const LinearProgressIndicator(minHeight: 2),
          if (widget.canPost && _composeBanner() != null) _composeBanner()!,
          if (!widget.canPost)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: WaslColors.glass,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text('النشر هنا للمشرفين فقط',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              ),
            )
          else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Row(children: [
                if (!_recording)
                  IconButton(
                    onPressed: _uploading ? null : _showAttachSheet,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                Expanded(
                  child: _recording
                      ? Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: WaslColors.glass,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(children: [
                            const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 8),
                            Text('جارٍ التسجيل ${_recLabel()}'),
                            const Spacer(),
                            const Text('اترك للإرسال', style: TextStyle(color: Colors.white54)),
                          ]),
                        )
                      : TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendText(),
                          decoration: const InputDecoration(hintText: 'اكتب رسالة...'),
                        ),
                ),
                const SizedBox(width: 8),
                hasText
                    ? Container(
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, gradient: WaslColors.gradient),
                        child: IconButton(
                          onPressed: _sendText,
                          icon: const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      )
                    : GestureDetector(
                        onLongPressStart: (_) => _startRec(),
                        onLongPressEnd: (_) => _stopRec(),
                        onTap: () => _snack('اضغط مطولاً للتسجيل'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _recording ? 60 : 48,
                          height: _recording ? 60 : 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _recording ? null : WaslColors.gradient,
                            color: _recording ? Colors.redAccent : null,
                          ),
                          child: const Icon(Icons.mic_rounded, color: Colors.white),
                        ),
                      ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
