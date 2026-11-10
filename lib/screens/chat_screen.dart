import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/ai_service.dart';
import '../services/draft_service.dart';
import '../services/e2e_service.dart';
import '../services/forward_service.dart';
import '../services/image_service.dart';
import '../services/media_cache.dart';
import '../services/media_prefs.dart';
import '../services/media_service.dart';
import '../services/mention_service.dart';
import '../services/poll_service.dart';
import '../services/room_permissions_service.dart';
import '../services/sticker_service.dart';
import '../services/video_service.dart';
import '../services/location_service.dart';
import '../services/contact_card_service.dart';
import '../services/presence_service.dart';
import '../services/privacy_service.dart';
import '../services/secure_flag_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_bubbles.dart';
import '../widgets/poll_bubble.dart';
import '../widgets/poll_composer_sheet.dart';
import '../widgets/location_bubble.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/contact_bubble.dart';
import '../widgets/contact_picker_sheet.dart';
import '../widgets/sticker_panel.dart';
import 'contact_screen.dart';
import 'group_info_screen.dart';
import 'video_screen.dart';

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
    this.starredOnly = false,
  });
  final String conversationId;
  final String title;
  final bool isGroup;
  final String? otherId;
  final bool isChannel;
  final bool canPost;

  /// تشفير بين الطرفين (خاص + مجموعات خاصة فقط؛ القنوات وغرف المجتمعات لا)
  final bool encrypted;

  /// يفتح المحادثة على الرسائل المميزة بنجمة فقط
  final bool starredOnly;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  final _picker = ImagePicker();
  late final Stream<List<Map<String, dynamic>>> _stream;
  final String _me = supabase.auth.currentUser?.id ?? '';

  Map<String, String> _names = {};
  late String _title = widget.title;

  // صلاحيات الغرفة (0.5.0 — المرحلة 3): تُجلب مرة عند الفتح،
  // وتعطّل خيارات الواجهة — والفرض الحقيقي من الخادم على كل رسالة
  RoomPerms? _perms;

  bool get _canMedia => _perms?.canSendMedia ?? true;
  bool get _canVoice => _perms?.canSendVoice ?? true;
  bool get _canPolls => _perms?.canSendPolls ?? true;

  // الرد والتعديل والتفاعلات
  Map<String, dynamic>? _replyTo;
  Map<String, dynamic>? _editing;
  Map<String, Map<String, dynamic>> _byId = {};
  // أصوات الاستطلاعات: poll_id -> صفوف poll_vote (تُبنى في كل build)
  Map<String, List<Map<String, dynamic>>> _votesByPoll = {};
  // الإشارة @ في المجموعات (0.4.5): توكنات حيّة + منتقي أعضاء
  final List<MentionToken> _mentionTokens = [];
  String? _mentionQuery; // استعلام المنتقي الحالي (بعد @)
  int? _mentionStart; // موضع '@' عند آخر تحديث
  bool _mentionInserting = false; // كتم ضبط المدى أثناء الإدراج البرمجي
  String _mentionPrevText = '';
  final FocusNode _inputFocus = FocusNode();
  StreamSubscription<List<Map<String, dynamic>>>? _reactSub;
  Map<String, Map<String, String>> _reactions = {}; // msgId -> (userId -> emoji)
  // الرسائل المختفية والنجوم وصورة الطرف الآخر
  int? _disappear;
  Set<String> _stars = {};
  late bool _starredOnly = widget.starredOnly;
  String? _otherAvatar;

  // البحث داخل المحادثة
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String get _query => _searchCtrl.text.trim().toLowerCase();

  // منع لقطات الشاشة (المرحلة 2)
  bool? _screenshotBlock;
  bool _secureHeld = false;

  // وسائط عرض مرة واحدة (المرحلة 2)
  bool _attachViewOnce = false;
  final Set<String> _onceOpened = {};

  static const _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  bool _recording = false;
  bool _uploading = false;
  bool _compressing = false; // ضغط الفيديو على الجهاز قبل الرفع (0.4.8)
  bool _stickerPanel = false; // لوحة الملصقات (0.4.9)
  // التنزيل التلقائي حسب الشبكة (0.4.8) — قرارات محلية بحتة:
  final Set<String> _cachedMedia = {}; // مسارات التخزين الموجودة في الكاش المحلي
  final Set<String> _autoDownloading = {}; // رسائل تُنزّل الآن
  final Set<String> _autoTried = {}; // مَن حاولنا تنزيله (تفادي التكرار عند إعادة البناء)
  int _autoBudget = 6; // سقف تنزيلات تلقائية لكل فتح شاشة (حِرص على البيانات)
  bool _onWifi = true; // حالة الشبكة الحالية (واي-فاي/إيثرنت)
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  DateTime? _recStart;
  Timer? _ticker;

  /// ملفات الوسائط المفكوكة التشفير المؤقتة — تُحذف عند مغادرة الشاشة
  final List<File> _openedFiles = [];

  // التشفير بين الطرفين (المحادثات الخاصة والمجموعات الخاصة)
  // نص فك التشفير لكل نص مشفّر: ciphertext -> النص الصريح (يتغيّر النص المشفّر عند التعديل)
  final Map<String, String> _plain = {};
  bool get _e2e => widget.encrypted && !widget.isChannel;

  /// مفتاح المحادثة: اشتقاق ECDH للخاص، أو مفتاح المجموعة للمجموعة الخاصة.
  /// fresh = تحقق طازج من حالة مفتاح المجموعة (يُستخدم عند الإرسال — يُغلق نافذة
  /// الـ30 ثانية التي كانت تسمح بالإرسال بمفتاح قديم بعد إزالة عضو).
  Future<SecretKey?> _convKey({bool fresh = false}) async {
    if (!widget.isGroup) {
      final other = widget.otherId;
      if (other == null) return null;
      return E2eService.dmKey(widget.conversationId, other);
    }
    return E2eService.groupKey(widget.conversationId, fresh: fresh);
  }

  /// يفك نصاً مشفّراً واحداً (للمجموعات: يجرّب كل إصدارات المفتاح المعروفة)
  Future<String?> _decrypt(String content) async {
    if (!widget.isGroup) {
      final other = widget.otherId;
      if (other == null) return null;
      var key = await _convKey();
      var plain =
          key == null ? null : await E2eService.decryptText(key, widget.conversationId, content);
      if (plain == null) {
        // ربما بدّل الطرف الآخر مفتاحه: نُبطل الكاش ونعيد الاشتقاق من أحدث مفتاح منشور مرة واحدة
        E2eService.invalidateDmKey(widget.conversationId, other);
        key = await _convKey();
        plain =
            key == null ? null : await E2eService.decryptText(key, widget.conversationId, content);
      }
      return plain;
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

  /// النص المعروض لرسالة نصية (null إن كانت ما زالت قيد فك التشفير).
  /// يفك أيضاً بنية الإشارات @ — الباقي يُعاد كما هو.
  String? _textOf(Map<String, dynamic> m) {
    final raw = m['content'] as String? ?? '';
    final t = E2eService.isEncrypted(raw) ? _plain[raw] : raw;
    if (t == null || t.isEmpty) return t;
    return MentionCodec.displayText(t);
  }

  /// يفك تشفير الرسائل النصية المشفّرة الجديدة في الخلفية
  void _scheduleDecrypt(List<Map<String, dynamic>> msgs) {
    _maybeAutoDownload(msgs); // التنزيل التلقائي للفيديو (0.4.8)
    if (!_e2e) return;
    for (final m in msgs) {
      final t = m['type'] ?? 'text';
      // الاستطلاعات: السؤال والخيارات والأصوات كلها مشفّرة وتُفكّ هنا
      if (t != 'text' &&
          t != 'file' &&
          t != 'video' &&
          t != 'poll' &&
          t != 'poll_vote' &&
          t != 'location' &&
          t != 'contact') {
        continue;
      }
      if (m['deleted_at'] != null) continue;
      final content = m['content'] as String? ?? '';
      if (!E2eService.isEncrypted(content) || _plain.containsKey(content)) continue;
      unawaited(_decryptInto(content));
    }
  }

  /// بيانات ملف/فيديو (الاسم والحجم) من content، بعد فكّها إن كانت مشفّرة
  Map<String, dynamic>? _metaOf(Map<String, dynamic> m) {
    final t = _textOf(m);
    if (t == null || t.isEmpty || !t.startsWith('{')) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(t) as Map);
    } catch (_) {
      return null;
    }
  }

  // ---------- التنزيل التلقائي للفيديو حسب الشبكة (0.4.8) ----------

  Future<void> _initConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      final r = results.isEmpty ? ConnectivityResult.none : results.first;
      setState(() => _onWifi =
          r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
    } catch (_) {}
  }

  /// يُستدعى من بث الرسائل: ينزّل فيديو الآخرين تلقائياً وفق الإعداد
  /// وقاعدة الشبكة. بلا تعليم عند الرفض — تغيّر الشبكة لاحقاً يعيد
  /// المحاولة. «عرض مرة واحدة» ورسالتي لا تدخلان التلقائي أبداً.
  void _maybeAutoDownload(List<Map<String, dynamic>> msgs) {
    final rule = MediaPrefs.autoDownload.value;
    if (rule == AutoDownloadRule.never) return;
    if (!MediaPrefs.allows(rule, onWifi: _onWifi)) return;
    if (_autoBudget <= 0) return; // سقف لكل فتح شاشة — البقية يدوي
    for (final m in msgs) {
      if (m['type'] != 'video') continue;
      if (m['view_once'] == true) continue;
      if ((m['sender_id'] ?? '') == _me) continue;
      final id = m['id'] as String;
      final path = m['media_url'] as String?;
      if (path == null) continue;
      if (_cachedMedia.contains(path)) continue;
      if (_autoTried.contains(id) || _autoDownloading.contains(id)) continue;
      _autoTried.add(id);
      _autoBudget--;
      unawaited(_cacheVideo(path, id));
    }
  }

  /// تنزيل وفك وتخزين نسخة الفيديو محلياً للفتح الفوري
  Future<void> _cacheVideo(String path, String msgId) async {
    setState(() => _autoDownloading.add(msgId));
    try {
      final bytes = await _mediaBytes(path);
      if (bytes != null) {
        final f = await MediaCache.put(path, bytes);
        if (f != null && mounted) setState(() => _cachedMedia.add(path));
      }
    } finally {
      if (mounted) setState(() => _autoDownloading.remove(msgId));
    }
  }

  static String _sizeLabel(int? b) {
    if (b == null) return '';
    if (b < 1024 * 1024) return '${(b / 1024).ceil()} ك.ب';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  // يكتب الآن + علامات القراءة
  late final RealtimeChannel _room;
  StreamSubscription<List<Map<String, dynamic>>>? _partsSub;
  final Map<String, DateTime> _typing = {};
  Timer? _typingSweep;
  DateTime _lastTypingSent = DateTime(2000);
  DateTime? _othersReadUpTo;
  String? _lastMarkedId;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _stream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: true);
    _text.addListener(_onTextChanged);
    _mentionPrevText = _text.text;
    // استرجاع المسودة المحفوظة محلياً لهذه المحادثة (بند المرحلة 1)
    DraftService.load().then((_) {
      if (!mounted) return;
      final d = DraftService.get(widget.conversationId);
      if (d != null && _text.text.isEmpty) _text.text = d;
    });
    if (widget.isGroup) _loadMembers();
    // صلاحيات الغرفة للمجموعات وغرف المجتمعات (القنوات قاعدة نشرها للمشرفين كما هي)
    if (widget.isGroup && !widget.isChannel) {
      RoomPermissionsService.fetch(widget.conversationId).then((p) {
        if (mounted) setState(() => _perms = p);
      });
    }
    _loadMeta();

    // تفضيلات الوسائط وحالة الشبكة (0.4.8 — التنزيل التلقائي للفيديو)
    unawaited(MediaPrefs.load());
    unawaited(_initConnectivity());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final r = results.isEmpty ? ConnectivityResult.none : results.first;
      setState(() =>
          _onWifi = r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
    });

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

    // متى قرأ الآخرون؟ (لعلامة ✓✓) — جدول read_receipts (020):
    // صفوف من أخفى علاماته لا تصل أصلاً بفضل RLS، والإخفاء لدىّ يمنع العرض
    _partsSub = supabase
        .from('read_receipts')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', widget.conversationId)
        .listen((rows) {
      DateTime? minRead;
      for (final r in rows) {
        if (r['user_id'] == _me || r['seen_at'] == null) continue;
        final t = DateTime.parse(r['seen_at'] as String);
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
    // إعادة بناء الشاشة عند تغيير إعدادات الخصوصية (قاعدة المبادلة)
    PrivacyService.hidePresence.addListener(_onPresence);
    PrivacyService.hideReceipts.addListener(_onPresence);
    supabase.rpc('mark_read', params: {'conv': widget.conversationId});
  }

  void _onPresence() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    // ضبط مدى إشارات @ مع أي تغيير (الإدراج البرمجي مكتوم)
    if (!_mentionInserting) {
      MentionTracker.adjust(_mentionTokens, _mentionPrevText, _text.text);
    }
    _mentionPrevText = _text.text;
    _updateMentionQuery();
    setState(() {});
    // حفظ المسودة محلياً بتأجيل بسيط — لا تُرفع للخادم إطلاقاً
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(DraftService.save(widget.conversationId, _text.text));
    });
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

  Future<void> _loadMeta() async {
    try {
      final conv = await supabase
          .from('conversations')
          .select('disappear_seconds, screenshot_block')
          .eq('id', widget.conversationId)
          .maybeSingle();
      final stars = await supabase
          .from('message_stars')
          .select('message_id')
          .eq('conversation_id', widget.conversationId);
      String? avatar;
      if (!widget.isGroup && widget.otherId != null) {
        final p = await supabase
            .from('profiles')
            .select('avatar_url')
            .eq('id', widget.otherId!)
            .maybeSingle();
        avatar = p?['avatar_url'] as String?;
      }
      if (!mounted) return;
      setState(() {
        _disappear = conv?['disappear_seconds'] as int?;
        _screenshotBlock = conv?['screenshot_block'] as bool? ?? false;
        _stars = {for (final r in stars) r['message_id'] as String};
        _otherAvatar = avatar;
      });
      await _applySecureFlag();
    } catch (_) {}
  }

  /// تطبيق/رفع FLAG_SECURE بعدد مراجع (قد تتراكب محادثات محمية فوق بعضها)
  Future<void> _applySecureFlag() async {
    if (!mounted) return;
    if (_screenshotBlock == true && !_secureHeld) {
      _secureHeld = true;
      await SecureFlag.acquire();
    } else if (_screenshotBlock != true && _secureHeld) {
      _secureHeld = false;
      await SecureFlag.release();
    }
  }

  Future<void> _toggleStar(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final starred = _stars.contains(id);
    setState(() => starred ? _stars.remove(id) : _stars.add(id));
    try {
      if (starred) {
        await supabase.from('message_stars').delete().eq('message_id', id).eq('user_id', _me);
      } else {
        await supabase.from('message_stars').insert({
          'message_id': id,
          'conversation_id': widget.conversationId,
        });
      }
    } catch (_) {
      if (mounted) setState(() => starred ? _stars.add(id) : _stars.remove(id));
      _snack('تعذّر الحفظ');
    }
  }

  Future<void> _changeDisappearing() async {
    final v = await pickDisappearing(context, widget.conversationId, _disappear);
    if (v != null && mounted) setState(() => _disappear = v == 0 ? null : v);
  }

  void _openContact() {
    if (widget.otherId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactScreen(
          otherId: widget.otherId!,
          conversationId: widget.conversationId,
          title: _title,
          disappearSeconds: _disappear,
          onSafetyNumber: _showSafety ? _showSafetyNumber : null,
          onShowStarred: () => setState(() => _starredOnly = true),
        ),
      ),
    ).then((_) => _loadMeta());
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
    return PresenceService.canShowPresence && PresenceService.isOnline(widget.otherId)
        ? 'متصل الآن'
        : null;
  }

  Widget _ticks(Map<String, dynamic> m) {
    final created = DateTime.parse(m['created_at'] as String);
    // قاعدة المبادلة: إن أخفيتُ علامات القراءة فلا أرى ✓✓ لغيري
    final read = !PrivacyService.hideReceipts.value &&
        _othersReadUpTo != null &&
        !created.isAfter(_othersReadUpTo!);
    return Icon(read ? Icons.done_all_rounded : Icons.done_rounded,
        size: 15,
        color: read
            ? context.wasl.readReceipt
            : context.wasl.onBubbleMine.withValues(alpha: 0.65));
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // حفظ المسودة الأخيرة قبل المغادرة
    unawaited(DraftService.save(widget.conversationId, _text.text));
    _ticker?.cancel();
    _typingSweep?.cancel();
    _partsSub?.cancel();
    _connectivitySub?.cancel();
    _reactSub?.cancel();
    _inputFocus.dispose();
    PresenceService.online.removeListener(_onPresence);
    PrivacyService.hidePresence.removeListener(_onPresence);
    PrivacyService.hideReceipts.removeListener(_onPresence);
    supabase.removeChannel(_room);
    supabase.rpc('mark_read', params: {'conv': widget.conversationId});
    // رفع منع لقطات الشاشة إن كانت مفعّلة من هذه المحادثة
    if (_secureHeld) {
      _secureHeld = false;
      unawaited(SecureFlag.release());
    }
    // إيقاف أي تسجيل جارٍ ثم تحرير الميكروفون
    unawaited(() async {
      try {
        if (await _recorder.isRecording()) await _recorder.stop();
      } catch (_) {}
      try {
        await _recorder.dispose();
      } catch (_) {}
    }());
    // حذف الوسائط المفكوكة التشفير من القرص
    for (final f in _openedFiles) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    _text.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// رسالة فشل الإرسال: تحويل رفض الخادم لرسالة عربية واضحة،
  /// ومنها رفض صلاحيات الغرفة (0.5.0 — RLS يرفض بصمت)
  String _sendFail(Object e, String fallback) {
    final s = e.toString();
    if (s.contains('blocked')) return 'لا يمكن الإرسال: أحد الطرفين حظر الآخر';
    if (s.contains('row-level') || s.contains('permission denied')) {
      return 'مالك المجموعة قيّد هذا النوع من الرسائل في هذه الغرفة';
    }
    return fallback;
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
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            if (number != null) ...[
              const SizedBox(height: 16),
              // التحقق بمسح QR (المرحلة 2): كل طرف يعرض رمز نفسه، والآخر يقارن بصرياً
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(data: number, size: 120),
              ),
              const SizedBox(height: 8),
              Text('أو قارن الـQR الظاهر عند الطرفين بصرياً',
                  style:
                      TextStyle(fontSize: 12, color: context.wasl.textFaint)),
            ],
          ]),
        ),
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

  // ---------- الإشارة @ في المجموعات (0.4.5 — بند المرحلة 1) ----------

  void _updateMentionQuery() {
    if (!widget.isGroup || _editing != null || !widget.canPost) {
      _mentionQuery = null;
      return;
    }
    final cursor = _text.selection.baseOffset;
    final q =
        cursor > 0 ? MentionTracker.queryAt(_text.text, cursor) : null;
    _mentionQuery = q;
    _mentionStart = q == null ? null : cursor - 1 - q.length;
  }

  /// اختيار عضو من المنتقي: يستبدل «@استعلام» بـ«@اسم » ويسجّل مداه
  void _pickMention(String id, String name) {
    final q = _mentionQuery;
    final start = _mentionStart;
    final base = _text.text;
    if (q == null || start == null || start >= base.length) return;
    final end = start + 1 + q.length;
    if (end > base.length || base.substring(start, end) != '@$q') return;
    final insert = '@$name ';
    final next = base.replaceRange(start, end, insert);
    _mentionInserting = true;
    _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + insert.length));
    _mentionInserting = false;
    _mentionPrevText = next;
    _mentionTokens.add(MentionToken(id, name, start, start + insert.length));
    _mentionQuery = null;
    _mentionStart = null;
    setState(() {});
    FocusScope.of(context).requestFocus(_inputFocus);
  }

  /// شريط أعضاء فوق حقل الكتابة عند كتابة @
  Widget _mentionPicker() {
    final q = _mentionQuery;
    final ql = q?.toLowerCase() ?? '';
    final matches = _names.entries
        .where((e) => e.value.trim().isNotEmpty)
        .where((e) => ql.isEmpty || e.value.toLowerCase().contains(ql))
        .take(6)
        .toList();
    if (q == null || matches.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      decoration: BoxDecoration(
        color: context.wasl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.wasl.border),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, bottom: 4),
              child: Text('أشر إلى عضو — يصله تنبيه في الإشعار',
                  style:
                      TextStyle(color: context.wasl.textFaint, fontSize: 11)),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final e in matches)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ActionChip(
                      avatar: CircleAvatar(
                        radius: 10,
                        backgroundColor: WaslColors.indigo,
                        child: Text(
                            e.value.isEmpty
                                ? '?'
                                : e.value.substring(0, 1),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white)),
                      ),
                      label: Text('@${e.value}',
                          style: TextStyle(
                              fontSize: 13,
                              color: context.wasl.textPrimary)),
                      onPressed: () => _pickMention(e.key, e.value),
                    ),
                  ),
              ]),
            ),
          ]),
    );
  }

  /// نصّ بإشارات ملوّنة — تمييز أقوى إن كنت أنا المُشار إليه
  Widget _mentionText(StructuredText st, bool mine) {
    final spans = <TextSpan>[];
    var cursor = 0;
    final sorted = st.mentions.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final m in sorted) {
      if (m.start < cursor || m.end > st.text.length) continue;
      if (m.start > cursor) {
        spans.add(TextSpan(text: st.text.substring(cursor, m.start)));
      }
      final isMe = m.userId == _me;
      spans.add(TextSpan(
        text: st.text.substring(m.start, m.end),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: mine ? context.wasl.onBubbleMine : context.wasl.accent,
          backgroundColor: mine
              ? context.wasl.onBubbleMine.withValues(alpha: isMe ? 0.35 : 0.18)
              : context.wasl.accent.withValues(alpha: isMe ? 0.28 : 0.12),
        ),
      ));
      cursor = m.end;
    }
    if (cursor < st.text.length) {
      spans.add(TextSpan(text: st.text.substring(cursor)));
    }
    return Text.rich(
        TextSpan(
            style: TextStyle(
                color: _bubbleText(mine), fontSize: 16),
            children: spans),
        textAlign: TextAlign.start);
  }

  // ---------- إرسال ----------
  Future<void> _sendText({DateTime? scheduledAt}) async {
    final raw = _text.text;
    final content = raw.trim();
    if (content.isEmpty) return;
    final editing = _editing;
    final replyTo = _replyTo;
    // الإشارات @ (0.4.5): مدى التوكنات مُنزاح بحذف الفراغات الطرفية قبل الترميز
    final lead = raw.indexOf(content);
    final tokens = [
      for (final t in _mentionTokens)
        if (t.start - lead >= 0 && t.end - lead <= content.length)
          MentionToken(t.userId, t.name, t.start - lead, t.end - lead)
    ];
    var payload = content;
    final mentionIds =
        tokens.isEmpty ? null : tokens.map((t) => t.userId).toSet().toList();
    if (tokens.isNotEmpty) {
      payload = MentionCodec.encode(content, [
        for (final t in tokens) MentionSpan(t.userId, t.start, t.end)
      ]);
    }
    if (_e2e) {
      if (!E2eService.withinPlainLimit(content)) {
        _snack('الرسالة طويلة جداً');
        return;
      }
      final key = await _convKey(fresh: true);
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
      _mentionTokens.clear();
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
        // قائمة المُشار إليهم (بيانات وصفية للتنبيه — ترحيل 023)
        if (mentionIds != null) 'mentions': mentionIds,
        if (replyTo != null) 'reply_to': replyTo['id'],
        // رسالة مجدولة (ترحيل 021): تُشفَّر الآن ويطلقها الخادم في موعدها
        // (تسليم خلال دقيقة من الموعد) — الإلغاء بالحذف قبل الموعد
        if (scheduledAt != null) ...{
          'created_at': scheduledAt.toUtc().toIso8601String(),
          'scheduled': true,
        },
      });
      unawaited(DraftService.clear(widget.conversationId));
      if (scheduledAt != null && mounted) {
        _snack('⏰ ستُرسل الرسالة في ${_fmtWhen(scheduledAt)}');
      }
    } catch (e) {
      _snack(_sendFail(e, 'تعذّر إرسال الرسالة'));
    }
  }

  // ---------- استطلاعات الرأي (0.4.4 — بند المرحلة 1) ----------

  /// إنشاء استطلاع: السؤال والخيارات تُشفَّر قبل الرفع
  Future<void> _newPoll() async {
    final draft = await PollComposerSheet.show(context);
    if (draft == null || !mounted) return;
    var payload = PollService.encodePoll(draft.question, draft.options);
    if (_e2e) {
      final key = await _convKey(fresh: true);
      if (key == null) {
        _snack(_keyMissingMsg());
        return;
      }
      try {
        payload = await E2eService.encryptText(key, widget.conversationId, payload);
      } catch (_) {
        _snack('تعذّر تشفير الاستطلاع');
        return;
      }
    }
    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'type': 'poll',
        'content': payload,
      });
    } catch (e) {
      _snack(_sendFail(e, 'تعذّر إرسال الاستطلاع'));
    }
  }

  /// مشاركة الموقع الحالي (0.4.6 — بند المرحلة 1): الإحداثيات والدقة
  /// تُقرأ على الجهاز ثم تُشفَّر قبل الرفع — الخادم يرى النوع فقط.
  Future<void> _sendLocation() async {
    final loc = await LocationPickerSheet.show(context, encrypted: _e2e);
    if (loc == null || !mounted) return;
    var payload = LocationService.encode(
      lat: loc.lat,
      lng: loc.lng,
      accuracyM: loc.accuracyM,
      label: loc.label,
    );
    if (!LocationService.withinLimit(payload)) {
      _snack('تعذّر تجهيز الموقع');
      return;
    }
    if (_e2e) {
      final key = await _convKey(fresh: true);
      if (key == null) {
        _snack(_keyMissingMsg());
        return;
      }
      try {
        payload = await E2eService.encryptText(key, widget.conversationId, payload);
      } catch (_) {
        _snack('تعذّر تشفير الموقع');
        return;
      }
    }
    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'type': 'location',
        'content': payload,
      });
    } catch (e) {
      _snack(_sendFail(e, 'تعذّر إرسال الموقع'));
    }
  }

  /// مشاركة بطاقة جهة اتصال (0.4.6 — بند المرحلة 1): الاسم والأرقام
  /// والبريد تُقرأ من دفتر الجهاز وتُشفَّر قبل الرفع.
  Future<void> _sendContact() async {
    final card = await ContactPickerSheet.show(context, encrypted: _e2e);
    if (card == null || !mounted) return;
    var payload = ContactCardService.encode(
      name: card.name,
      phones: card.phones,
      emails: card.emails,
    );
    if (!ContactCardService.withinLimit(payload)) {
      _snack('البطاقة كبيرة — قلّل القيم المختارة');
      return;
    }
    if (_e2e) {
      final key = await _convKey(fresh: true);
      if (key == null) {
        _snack(_keyMissingMsg());
        return;
      }
      try {
        payload = await E2eService.encryptText(key, widget.conversationId, payload);
      } catch (_) {
        _snack('تعذّر تشفير البطاقة');
        return;
      }
    }
    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'type': 'contact',
        'content': payload,
      });
    } catch (e) {
      _snack(_sendFail(e, 'تعذّر إرسال البطاقة'));
    }
  }

  /// تصويت (أو تغيير الصوت): اختيار جديد يلغي السابق («الأحدث يفوز»).
  /// صامت عمداً: بلا إشعار ولا عدّاد غير مقروء (ترحيل 022 يستثنيه).
  Future<void> _sendVote(String pollId, int choice) async {
    var payload = PollService.encodeVote(choice);
    if (_e2e) {
      final key = await _convKey(fresh: true);
      if (key == null) {
        _snack(_keyMissingMsg());
        return;
      }
      try {
        payload = await E2eService.encryptText(key, widget.conversationId, payload);
      } catch (_) {
        _snack('تعذّر تسجيل الصوت');
        return;
      }
    }
    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'type': 'poll_vote',
        'poll_id': pollId,
        'content': payload,
      });
    } catch (e) {
      _snack(_sendFail(e, 'تعذّر تسجيل الصوت'));
    }
  }

  /// جلب أوليّ موجّه لأصوات استطلاع (يغطي أصواتاً خارج نافذة الرسائل المحمّلة)
  Future<List<Map<String, dynamic>>> _loadPollVotes(String pollId) =>
      supabase
          .from('messages')
          .select('id, sender_id, content, created_at, deleted_at')
          .eq('poll_id', pollId)
          .order('created_at');

  List<Map<String, dynamic>> _votesFor(String pollId) =>
      _votesByPoll[pollId] ?? const [];

  /// جدولة الرسالة النصية المكتوبة حالياً (بند المرحلة 1: الرسائل المجدولة)
  Future<void> _scheduleText() async {
    if (_text.text.trim().isEmpty) {
      _snack('اكتب الرسالة أولاً ثم اختر جدولة الإرسال');
      return;
    }
    if (_editing != null) {
      _snack('لا يمكن جدولة تعديل — أرسله أو ألغِ التعديل');
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 15))),
    );
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (at.difference(now) < const Duration(minutes: 5)) {
      _snack('اختر وقتاً بعد 5 دقائق على الأقل من الآن');
      return;
    }
    await _sendText(scheduledAt: at);
  }

  String _fmtWhen(DateTime at) {
    final d = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    final now = DateTime.now();
    final today = d.year == now.year && d.month == now.month && d.day == now.day;
    if (today) return 'اليوم $hm';
    return '${d.year}/${two(d.month)}/${two(d.day)} · $hm';
  }

  Future<void> _sendMedia({
    required String type,
    required Uint8List bytes,
    required String ext,
    required String contentType,
    int? durationMs,
    Map<String, dynamic>? meta,
    String? rawContent, // محتوى جاهز مسبقاً (meta الفيديو المُجزّأة بالضغط والمصغّرة — 0.4.8)
    bool viewOnce = false,
  }) async {
    if (!mounted) return; // قد يغادر المستخدم الشاشة أثناء اختيار الملف
    setState(() => _uploading = true);
    try {
      var content = rawContent ?? (meta == null ? '' : jsonEncode(meta));
      var payload = bytes;
      var upExt = ext;
      var upType = contentType;
      if (_e2e) {
        final key = await _convKey(fresh: true);
        if (key == null) {
          _snack(_keyMissingMsg());
          return;
        }
        payload = await E2eService.encryptBytes(key, widget.conversationId, bytes);
        if (content.isNotEmpty) {
          content = await E2eService.encryptText(key, widget.conversationId, content);
        }
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
        'content': content,
        'media_url': path,
        'duration_ms': durationMs,
        if (viewOnce) 'view_once': true,
        if (replyTo != null) 'reply_to': replyTo['id'],
      });
      if (mounted) {
        setState(() {
          _replyTo = null;
          // وضع «عرض مرة واحدة» استخدام واحد ثم يعود عادي
          if (viewOnce) _attachViewOnce = false;
        });
      }
    } catch (e) {
      _snack(_sendFail(e, 'تعذّر رفع الملف'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------- الصور والملصقات (0.4.9) ----------
  // الكاميرا: JPEG دائماً — ضغط المنتقي آمن. المعرض: بلا ضغط من
  // المنتقي إطلاقاً (كود أندرويد لا يتجاوز GIF فتتسطح المتحركة) —
  // الأصل يُرسل كما هو والتصغير الساكن للكبير على الجهاز في ImageService.
  Future<void> _pickImage(ImageSource source) async {
    final compressed = source == ImageSource.camera;
    final x = compressed
        ? await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80)
        : await _picker.pickImage(source: source);
    if (x == null) return;
    var bytes = await x.readAsBytes();
    final kind = ImageService.detectKind(bytes);
    final (reject, downscale) = ImageService.decide(kind, bytes.lengthInBytes);
    if (reject != null) {
      _snack(reject);
      return;
    }
    if (downscale) {
      setState(() => _compressing = true);
      try {
        final small = await ImageService.downscaleAsync(bytes,
            keepPng: kind == ImageKind.png);
        if (small != null) bytes = small; // فشل التصغير يُرسل الأصل كما هو
      } catch (_) {
        // فكّ غير ناجح: الأصل يُرسل كما هو — صادق
      } finally {
        if (mounted) setState(() => _compressing = false);
      }
    }
    if (bytes.lengthInBytes > _maxBytes) {
      _snack('الصورة أكبر من 24 ميغابايت');
      return;
    }
    final animated = ImageService.isAnimated(kind, bytes);
    var ext = switch (kind) {
      ImageKind.jpeg => 'jpeg',
      ImageKind.png => 'png',
      ImageKind.gif => 'gif',
      ImageKind.webp => 'webp',
      _ => (x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'jpg'),
    };
    if (ext == 'jpg') ext = 'jpeg';
    await _sendMedia(
      type: 'image',
      bytes: bytes,
      ext: ext,
      contentType: 'image/$ext',
      // علم الحركة داخل meta المشفّرة — المستقبل يعرضها متحركة أصلاً
      meta: animated ? const {'animated': true} : null,
      viewOnce: _attachViewOnce,
    );
  }

  // ---------- الملصقات (0.4.9) ----------
  Future<void> _sendSticker(String pack, String id) async {
    try {
      final path = StickerService.assetPath(pack, id);
      final data = await rootBundle.load(path);
      final bytes = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes);
      await _sendMedia(
        type: 'sticker',
        bytes: bytes,
        ext: StickerService.extOf(id),
        contentType:
            StickerService.extOf(id) == 'gif' ? 'image/gif' : 'image/webp',
        rawContent: StickerService.metaJson(pack, id),
      );
      await StickerService.remember(pack, id);
    } on ArgumentError {
      _snack('ملصق غير معروف');
    } catch (_) {
      _snack('تعذّر تحميل الملصق');
    }
  }

  static const _maxBytes = 24 * 1024 * 1024;

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (x == null) return;
    File src = File(x.path);
    var size = await src.length();
    final origSize = size;
    // الضغط على الجهاز بمُرمّزات المنصة (0.4.8): أفضل جهد — فشله يُرسل
    // الأصل كما هو، والأصل لا يُحذف أبداً
    if (VideoService.shouldCompress(size)) {
      setState(() => _compressing = true);
      try {
        final out =
            await VideoService.compress(src.path, sizeBytes: size);
        if (out != null) {
          src = out;
          size = await out.length();
        }
      } finally {
        if (mounted) setState(() => _compressing = false);
      }
    }
    if (size > _maxBytes) {
      _snack('الفيديو أكبر من 24 ميغابايت حتى بعد الضغط');
      return;
    }
    // المصغّرة داخل التشفير (0.4.8): إطار JPEG صغير في meta المشفّرة —
    // فشلها يرسل بلا مصغّرة، وتجاوز السقف يعيد المحاولة بلا مصغّرة
    String? thumbB64;
    String meta;
    try {
      final tb = await VideoService.thumbnail(src.path);
      if (tb != null) thumbB64 = base64Encode(tb);
    } catch (_) {}
    final name = x.name.isNotEmpty ? x.name : 'video.mp4';
    final wasCompressed = size != origSize;
    try {
      meta = VideoService.metaJson(
          name: name,
          size: size,
          originalSize: wasCompressed ? origSize : null,
          thumbBase64: thumbB64);
    } on StateError {
      try {
        meta = VideoService.metaJsonWithoutThumb(
            name: name, size: size, originalSize: wasCompressed ? origSize : null);
      } on StateError {
        _snack('تعذّر تجهيز الفيديو');
        return;
      }
    }
    final bytes = await src.readAsBytes();
    final ext = src.path.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    await _sendMedia(
      type: 'video',
      bytes: bytes,
      ext: ext,
      contentType: ext == 'mov' ? 'video/quicktime' : 'video/mp4',
      rawContent: meta,
      viewOnce: _attachViewOnce,
    );
  }

  Future<void> _pickFile() async {
    if (_attachViewOnce) {
      _snack('عرض مرة واحدة للصور والفيديو فقط');
    }
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.single;
    if (f == null) return;
    if (f.size > _maxBytes || f.bytes == null) {
      _snack(f.bytes == null ? 'تعذّر قراءة الملف' : 'الملف أكبر من 24 ميغابايت');
      return;
    }
    final ext = (f.extension ?? 'bin').toLowerCase();
    await _sendMedia(
      type: 'file',
      bytes: f.bytes!,
      ext: ext.length > 8 ? 'bin' : ext,
      contentType: 'application/octet-stream',
      meta: {'name': f.name, 'size': f.size},
    );
  }

  /// يفك الملف ثم يفتحه (الفيديو داخل التطبيق، وغيره بتطبيق مناسب).
  /// الفيديو يمرّ بكاش محلي (0.4.8): تنزيل واحد ثم فتح فوري لاحقاً.
  Future<void> _openMedia(Map<String, dynamic> m) async {
    if (kIsWeb) return;
    final mediaPath = m['media_url'] as String?;
    if (mediaPath == null) return;
    setState(() => _uploading = true);
    try {
      File? file;
      if (m['type'] == 'video' && _cachedMedia.contains(mediaPath)) {
        file = await MediaCache.get(mediaPath);
      }
      if (file == null) {
        final bytes = await _mediaBytes(mediaPath);
        if (bytes == null) {
          _snack('تعذّر تنزيل الملف');
          return;
        }
        if (m['type'] == 'video') {
          // نسخة الفيديو تبقى في الكاش للفتح الفوري لاحقاً —
          // التنظيف عبر «مسح الوسائط المؤقتة» في الإعدادات
          file = await MediaCache.put(mediaPath, bytes);
          if (file != null && mounted) {
            setState(() => _cachedMedia.add(mediaPath));
          }
        }
        if (file == null) {
          final meta = _metaOf(m);
          var name = (meta?['name'] as String?) ??
              (m['type'] == 'video' ? 'video.mp4' : 'file');
          name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final dir =
              Directory('${(await getTemporaryDirectory()).path}/wasl_open');
          await dir.create(recursive: true);
          file = File(
              '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
          await file.writeAsBytes(bytes, flush: true);
          _openedFiles.add(file);
        }
      }
      if (!mounted) return;
      if (m['type'] == 'video') {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => VideoScreen(file: file!)));
        _openedFiles.remove(file);
        if (file.path.contains('wasl_open')) _deleteQuietly(file.path);
      } else {
        final res = await OpenFilex.open(file.path);
        if (res.type != ResultType.done) _snack('لا يوجد تطبيق يفتح هذا الملف');
      }
    } catch (_) {
      _snack('تعذّر فتح الملف');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.wasl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          // وضع «عرض مرة واحدة» (المرحلة 2): الوسيطة التالية صور/فيديو تُعرض مرة واحدة
          StatefulBuilder(
            builder: (ctx, setSheet) => SwitchListTile(
              secondary: Icon(Icons.visibility_off_outlined,
                  color: context.wasl.danger),
              title: const Text('عرض مرة واحدة'),
              subtitle: const Text(
                  'الصورة أو الفيديو التالي لا تُفتح إلا مرة، ثم يُحذف ملفها من الخادم'),
              value: _attachViewOnce,
              onChanged: (v) => setSheet(() => setState(() => _attachViewOnce = v)),
            ),
          ),
          // رسالة مجدولة (المرحلة 1): نص فقط في هذا الإصدار
          ListTile(
            leading: const Icon(Icons.schedule_send_outlined, color: WaslColors.violet),
            title: const Text('رسالة مجدولة'),
            subtitle: const Text(
                'تُشفَّر الآن وتُسلَّم في الوقت الذي تحدده (خلال دقيقة منه)، والإلغاء بالحذف'),
            onTap: () {
              Navigator.pop(ctx);
              _scheduleText();
            },
          ),
          // استطلاع رأي (المرحلة 1 — 0.4.4): مشفّر بالكامل والفرز حيّ
          ListTile(
            leading: const Icon(Icons.poll_rounded, color: WaslColors.indigo),
            title: const Text('استطلاع رأي'),
            subtitle: const Text(
                'سؤال وخيارات مشفّرة — الأصوات حيّة ويمكن تغييرها، ولا تُرسل إشعاراً'),
            enabled: _canPolls,
            onTap: _canPolls
                ? () {
                    Navigator.pop(ctx);
                    _newPoll();
                  }
                : null,
          ),
          // الموقع الحالي (المرحلة 1 — 0.4.6): الإحداثيات داخل التشفير
          ListTile(
            leading: const Icon(Icons.location_on_outlined, color: WaslColors.teal),
            title: const Text('الموقع'),
            subtitle: const Text(
                'موقعك الحالي تُشفَّر إحداثياته — الخادم لا يعرف مكانك'),
            enabled: _canMedia,
            onTap: _canMedia
                ? () {
                    Navigator.pop(ctx);
                    _sendLocation();
                  }
                : null,
          ),
          // بطاقة جهة اتصال (المرحلة 1 — 0.4.6): الاسم والأرقام داخل التشفير
          ListTile(
            leading: const Icon(Icons.person_pin_circle_rounded,
                color: WaslColors.violet),
            title: const Text('جهة اتصال'),
            subtitle: const Text(
                'تُقرأ من دفتر جهازك وتُشفَّر داخل البطاقة — بلا مزامنة'),
            enabled: _canMedia,
            onTap: _canMedia
                ? () {
                    Navigator.pop(ctx);
                    _sendContact();
                  }
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: WaslColors.teal),
            title: const Text('صورة من المعرض'),
            enabled: _canMedia,
            onTap: _canMedia
                ? () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  }
                : null,
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: WaslColors.indigo),
              title: const Text('الكاميرا'),
              enabled: _canMedia,
              onTap: _canMedia
                  ? () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    }
                  : null,
            ),
          ListTile(
            leading: const Icon(Icons.movie_outlined, color: WaslColors.violet),
            title: const Text('فيديو'),
            subtitle: const Text('حتى 24 ميغابايت'),
            enabled: _canMedia,
            onTap: _canMedia
                ? () {
                    Navigator.pop(ctx);
                    _pickVideo();
                  }
                : null,
          ),
          ListTile(
            leading: Icon(Icons.insert_drive_file_outlined,
                color: context.wasl.warning),
            title: const Text('ملف'),
            subtitle: const Text('PDF، مستندات، وغيرها حتى 24 ميغابايت'),
            enabled: _canMedia,
            onTap: _canMedia
                ? () {
                    Navigator.pop(ctx);
                    _pickFile();
                  }
                : null,
          ),
        ]),
      ),
    );
  }

  // ---------- التسجيل الصوتي (اضغط مطولاً) ----------
  Future<void> _startRec() async {
    if (!_canVoice) {
      _snack('مالك المجموعة أوقف الرسائل الصوتية في هذه الغرفة');
      return;
    }
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
    final start = _recStart;
    final ms = start == null ? 0 : DateTime.now().difference(start).inMilliseconds;
    if (mounted) setState(() => _recording = false);
    if (cancel || path == null || ms < 700) {
      _deleteQuietly(path);
      return;
    }
    final bytes = await XFile(path).readAsBytes();
    await _sendMedia(
      type: 'voice',
      bytes: bytes,
      ext: 'm4a',
      contentType: 'audio/mp4',
      durationMs: ms,
    );
    _deleteQuietly(path);
  }

  /// حذف ملف مؤقت بصمت (تسجيل أُلغي أو بُعِث)
  void _deleteQuietly(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
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
        final other = widget.otherId;
        var key = other == null ? null : await _convKey();
        var out = key == null
            ? null
            : await E2eService.decryptBytes(key, widget.conversationId, raw);
        if (out == null && other != null) {
          // ربما بدّل الطرف الآخر مفتاحه: نُبطل الكاش ونعيد الاشتقاق مرة واحدة
          E2eService.invalidateDmKey(widget.conversationId, other);
          key = await _convKey();
          out = key == null
              ? null
              : await E2eService.decryptBytes(key, widget.conversationId, raw);
        }
        return out;
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

  /// لون النص الأساسي داخل الفقاعة: رسائلي أبيض دائماً (onBubbleMine)،
  /// ورسائل الطرف الآخر تتبع اللوحة
  Color _bubbleText(bool mine) =>
      mine ? context.wasl.onBubbleMine : context.wasl.textPrimary;

  /// النص الباهت داخل فقاعتي: أبيض بشفافية، وللطرف الآخر حسب اللوحة
  Color _bubbleFaint(bool mine) => mine
      ? context.wasl.onBubbleMine.withValues(alpha: 0.65)
      : context.wasl.textFaint;

  Color _bubbleSecondary(bool mine) => mine
      ? context.wasl.onBubbleMine.withValues(alpha: 0.65)
      : context.wasl.textSecondary;

  Widget _body(Map<String, dynamic> m, {required bool mine}) {
    if (m['deleted_at'] != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 16, color: _bubbleFaint(mine)),
        const SizedBox(width: 6),
        Text('حُذفت هذه الرسالة',
            style: TextStyle(
                color: _bubbleFaint(mine), fontStyle: FontStyle.italic)),
      ]);
    }
    switch (m['type'] as String? ?? 'text') {
      case 'poll':
        final raw = _textOf(m);
        final poll = raw == null ? null : PollService.decodePoll(raw);
        if (poll == null) {
          return Text(raw == null ? '📊 جارٍ فك التشفير…' : '📊 استطلاع',
              style: TextStyle(color: _bubbleText(mine), fontSize: 16));
        }
        return PollBubble(
          content: poll,
          mine: mine,
          myId: _me,
          votes: _votesFor(m['id'] as String),
          loadVotes: () => _loadPollVotes(m['id'] as String),
          onVote: (i) => _sendVote(m['id'] as String, i),
        );
      case 'poll_vote':
        // الصوت يُعرض داخل فقاعة الاستطلاع نفسها — لا فقاعة مستقلة
        return const SizedBox.shrink();
      case 'location':
        final raw = _textOf(m);
        final loc = raw == null ? null : LocationService.decode(raw);
        if (loc == null) {
          return Text(raw == null ? '📍 جارٍ فك التشفير…' : '📍 موقع',
              style: TextStyle(color: _bubbleText(mine), fontSize: 16));
        }
        return LocationBubble(content: loc, mine: mine);
      case 'contact':
        final raw = _textOf(m);
        final card = raw == null ? null : ContactCardService.decode(raw);
        if (card == null) {
          return Text(raw == null ? '👤 جارٍ فك التشفير…' : '👤 جهة اتصال',
              style: TextStyle(color: _bubbleText(mine), fontSize: 16));
        }
        return ContactBubble(content: card, mine: mine);
      case 'image':
        if (m['view_once'] == true) {
          return _viewOnceBubble(m, isVideo: false, mine: mine);
        }
        return ImageBubble(loader: () => _mediaBytes(m['media_url'] as String));
      case 'sticker':
        final meta = _metaOf(m);
        final ref = StickerService.decodeMeta(meta);
        if (ref == null) {
          return Text('🩹 ملصق',
              style: TextStyle(color: _bubbleText(mine), fontSize: 15));
        }
        return StickerBubble(loader: () => _mediaBytes(m['media_url'] as String));
      case 'voice':
        return VoiceBubble(
            loader: () => _mediaBytes(m['media_url'] as String),
            durationMs: m['duration_ms'] as int?);
      case 'video':
      case 'file':
        final isVideo = m['type'] == 'video';
        if (isVideo && m['view_once'] == true) {
          return _viewOnceBubble(m, isVideo: true, mine: mine);
        }
        if (isVideo) return _videoBubble(m, mine);
        final meta = _metaOf(m);
        final name = (meta?['name'] as String?) ?? 'ملف';
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openMedia(m),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.wasl.glass,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isVideo ? Icons.play_circle_fill : Icons.insert_drive_file_rounded,
                  size: 36, color: _bubbleText(mine)),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _bubbleText(mine),
                          fontWeight: FontWeight.w600)),
                  Text(
                      [
                        isVideo ? 'فيديو' : 'ملف',
                        _sizeLabel((meta?['size'] as num?)?.toInt()),
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style:
                          TextStyle(color: _bubbleSecondary(mine), fontSize: 12)),
                ]),
              ),
            ]),
          ),
        );
      default:
        final text = _textOf(m) ?? '🔒 جارٍ فك التشفير…';
        final st = MentionCodec.decode(text);
        if (st != null) return _mentionText(st, mine);
        return Text(text,
            style: TextStyle(color: _bubbleText(mine), fontSize: 16));
    }
  }

  // ---------- فقاعة الفيديو بالمصغّرة المشفّرة (0.4.8) ----------

  /// فقاعة فيديو: المصغّرة (إطار JPEG) تخرج من meta المشفّرة فلا يرى
  /// الخادم بيكسلاتها، وشارة صادقة للحالة: ✓ جاهز / جارٍ التنزيل /
  /// اضغط للتنزيل. بلا مصغّرة تظهر فقاعة أيقونية كما قبل 0.4.8.
  Widget _videoBubble(Map<String, dynamic> m, bool mine) {
    final meta = _metaOf(m);
    final b64 = meta?['thumb'] as String?;
    Uint8List? thumb;
    if (b64 != null && b64.length <= 40000) {
      try {
        thumb = base64Decode(b64);
      } catch (_) {}
    }
    final path = m['media_url'] as String?;
    final cached = path != null && _cachedMedia.contains(path);
    final downloading = _autoDownloading.contains(m['id'] as String);
    final sizeText = _sizeLabel((meta?['size'] as num?)?.toInt());
    final orig = (meta?['orig'] as num?)?.toInt();
    final subtitle = [
      if (sizeText.isNotEmpty) sizeText,
      if (orig != null) 'مضغوط من ${_sizeLabel(orig)}',
    ].join(' · ');
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openMedia(m),
        child: Container(
          width: 236,
          color: context.wasl.glass,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(children: [
                if (thumb != null)
                  Image.memory(thumb,
                      width: 236,
                      height: 148,
                      fit: BoxFit.cover,
                      gaplessPlayback: true)
                else
                  Container(
                    height: 104,
                    width: 236,
                    color: context.wasl.glassStrong,
                    alignment: Alignment.center,
                    child: Icon(Icons.videocam_outlined,
                        size: 40, color: _bubbleText(mine)),
                  ),
                const Positioned.fill(
                  child: Center(
                    child: Icon(Icons.play_circle_fill,
                        size: 46, color: Colors.white70),
                  ),
                ),
              ]),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      subtitle.isEmpty ? 'فيديو' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _bubbleSecondary(mine), fontSize: 12),
                    ),
                  ),
                  if (downloading)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _bubbleText(mine)),
                    )
                  else
                    Icon(
                      cached
                          ? Icons.check_circle_outline
                          : Icons.download_rounded,
                      size: 16,
                      color: _bubbleSecondary(mine),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- وسائط عرض مرة واحدة (المرحلة 2) ----------

  bool _onceViewed(Map<String, dynamic> m) =>
      m['media_url'] == null || _onceOpened.contains(m['id'] as String);

  Widget _viewOnceBubble(Map<String, dynamic> m,
      {required bool isVideo, required bool mine}) {
    if (_onceViewed(m)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.wasl.glass,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isVideo ? Icons.videocam_off_outlined : Icons.photo_outlined,
              size: 22, color: _bubbleFaint(mine)),
          const SizedBox(width: 8),
          Text('عرض مرة واحدة · تم العرض',
              style: TextStyle(
                  color: _bubbleFaint(mine), fontStyle: FontStyle.italic)),
        ]),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openViewOnce(m, isVideo: isVideo),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.wasl.glass,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.wasl.danger, width: 2),
            ),
            alignment: Alignment.center,
            child: Text('1',
                style: TextStyle(
                    color: context.wasl.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isVideo ? 'فيديو · عرض مرة واحدة' : 'صورة · عرض مرة واحدة',
                style: TextStyle(
                    color: _bubbleText(mine), fontWeight: FontWeight.w600)),
            Text('اضغط للعرض — تُفتح مرة واحدة فقط',
                style: TextStyle(color: _bubbleFaint(mine), fontSize: 12)),
          ]),
        ]),
      ),
    );
  }

  /// فتح وسيط عرض مرة واحدة: صورة بملء الشاشة أو فيديو بالعارض،
  /// وبعد الإغلاق يُستهلك من الخادم (يسجّل viewed_at وينقل الملف إلى سلة الحذف)
  Future<void> _openViewOnce(Map<String, dynamic> m,
      {required bool isVideo}) async {
    final url = m['media_url'] as String?;
    if (url == null || _onceOpened.contains(m['id'] as String)) return;
    if (kIsWeb) {
      _snack('عرض مرة واحدة متاح على تطبيق الجوال');
      return;
    }
    setState(() => _uploading = true);
    try {
      final bytes = await _mediaBytes(url);
      if (bytes == null) {
        _snack('تعذّر تنزيل الملف');
        return;
      }
      if (!mounted) return;
      if (isVideo) {
        final dir = Directory('${(await getTemporaryDirectory()).path}/wasl_once');
        await dir.create(recursive: true);
        final file =
            File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.mp4');
        await file.writeAsBytes(bytes, flush: true);
        _openedFiles.add(file);
        if (!mounted) return;
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => VideoScreen(file: file)));
        // حذف فوري من القرص بعد إغلاق العارض
        _openedFiles.remove(file);
        _deleteQuietly(file.path);
      } else {
        await showDialog<void>(
          context: context,
          barrierColor: context.wasl.barrier,
          builder: (c) => GestureDetector(
            onTap: () => Navigator.pop(c),
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      }
      // المرسِل لا يستهلك رسالته (الخادم يتجاهله) — والمتلقي يستهلكها الآن
      try {
        await supabase.rpc('open_view_once', params: {'p_msg': m['id']});
      } catch (_) {}
      if (m['sender_id'] != _me && mounted) {
        // حماية فورية من إعادة الفتح قبل وصول تحديث البث
        setState(() => _onceOpened.add(m['id'] as String));
      }
    } catch (_) {
      _snack('تعذّر فتح الملف');
    } finally {
      if (mounted) setState(() => _uploading = false);
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
      } else if (type == 'video') {
        what = '[فيديو]';
      } else if (type == 'file') {
        what = '[ملف]';
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
      backgroundColor: context.wasl.surface,
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
      case 'video':
        return '🎬 فيديو';
      case 'file':
        return '📎 ${(_metaOf(m)?['name'] as String?) ?? 'ملف'}';
      case 'sticker':
        return '🩹 ملصق';
      case 'poll':
        final raw = _textOf(m);
        final poll = raw == null ? null : PollService.decodePoll(raw);
        return poll == null ? '📊 استطلاع' : '📊 ${poll.question}';
      case 'poll_vote':
        return '📊 صوت في استطلاع';
      case 'location':
        final raw = _textOf(m);
        final loc = raw == null ? null : LocationService.decode(raw);
        return loc == null
            ? '📍 موقع'
            : '📍 ${loc.label ?? '${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)}'}';
      case 'contact':
        final raw = _textOf(m);
        final card = raw == null ? null : ContactCardService.decode(raw);
        return card == null ? '👤 جهة اتصال' : '👤 ${card.name}';
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
              style: FilledButton.styleFrom(
                  backgroundColor: context.wasl.danger),
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

  Future<void> _forward(Map<String, dynamic> m) async {
    List<Map<String, dynamic>> chats;
    try {
      chats = List<Map<String, dynamic>>.from(await supabase.rpc('my_chats') as List)
          .where((c) => c['conversation_id'] != widget.conversationId)
          .toList();
    } catch (_) {
      _snack('تعذّر تحميل المحادثات');
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.wasl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('إعادة توجيه إلى…',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: chats.isEmpty
                  ? const Center(child: Text('لا توجد محادثات أخرى'))
                  : ListView(children: [
                      for (final c in chats)
                        ListTile(
                          leading: UserAvatar(
                            name: (c['title'] ?? '') as String,
                            url: c['avatar_url'] as String?,
                            radius: 22,
                            color: c['is_group'] == true ? WaslColors.teal : WaslColors.indigo,
                            icon: c['is_group'] == true ? Icons.groups_2 : null,
                          ),
                          title: Text((c['title'] ?? '') as String),
                          onTap: () => Navigator.pop(ctx, c),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
    if (target == null || !mounted) return;
    setState(() => _uploading = true);
    final type = m['type'] as String? ?? 'text';
    bool ok;
    if (type == 'text') {
      ok = await ForwardService.send(target: target, type: 'text', text: _textOf(m));
    } else if (type == 'poll' ||
        type == 'location' ||
        type == 'contact') {
      // رسائل المحتوى-فقط: تُفكّ ثم تُشفَّر بمفتاح الهدف — بلا وسائط
      // (يصلح أيضاً توجيه الاستطلاعات الذي كان يفشل صامتاً)
      ok = await ForwardService.send(target: target, type: type, text: _textOf(m));
    } else {
      final bytes = await _mediaBytes(m['media_url'] as String);
      ok = bytes != null &&
          await ForwardService.send(
              target: target,
              type: type,
              bytes: bytes,
              // ملف/فيديو/ملصق: meta المفكوكة تُشفر بمفتاح الهدف
              text: (type == 'file' || type == 'video' || type == 'sticker')
                  ? _textOf(m)
                  : null,
              durationMs: m['duration_ms'] as int?);
    }
    if (mounted) setState(() => _uploading = false);
    _snack(ok
        ? 'أُرسلت إلى ${target['title']}'
        : 'تعذّرت إعادة التوجيه (قد لا يكون التشفير جاهزاً في المحادثة الأخرى)');
  }

  void _startEdit(Map<String, dynamic> m) {
    final t = _textOf(m);
    if (t == null) return;
    setState(() {
      _editing = m;
      _replyTo = null;
      _mentionTokens.clear();
      _text.text = t;
      _text.selection = TextSelection.collapsed(offset: t.length);
    });
  }

  void _messageActions(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return;
    final type = m['type'] ?? 'text';
    final isText = type == 'text';
    final text = isText ? _textOf(m) : null;
    if (isText && text == null) {
      _snack('جارٍ فك التشفير… حاول بعد لحظة');
      return;
    }
    // النسخ يمتد للموقع (رابط geo) والبطاقة (الاسم والأرقام) — 0.4.6
    String? copyable = text;
    if (type == 'location') {
      final raw = _textOf(m);
      final loc = raw == null ? null : LocationService.decode(raw);
      copyable = loc?.geoUri;
    } else if (type == 'contact') {
      final raw = _textOf(m);
      final card = raw == null ? null : ContactCardService.decode(raw);
      copyable = card == null ? null : ContactCardService.copyText(card);
    }
    final arabic = text != null && RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    final mine = m['sender_id'] == _me;
    final myReaction = _reactions[m['id']]?[_me];
    showModalBottomSheet(
      context: context,
      backgroundColor: context.wasl.surface,
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
                        color: myReaction == e ? context.wasl.glass : null,
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
          if (copyable != null)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(type == 'location' ? 'نسخ الإحداثيات' : type == 'contact' ? 'نسخ البطاقة' : 'نسخ'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: copyable!));
                Navigator.pop(ctx);
                _snack('تم النسخ');
              },
            ),
          if (m['deleted_at'] == null)
            ListTile(
              leading: Icon(
                  _stars.contains(m['id']) ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: context.wasl.warning),
              title: Text(_stars.contains(m['id']) ? 'إزالة النجمة' : 'تمييز بنجمة'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleStar(m);
              },
            ),
          if (_e2e && !widget.isChannel)
            ListTile(
              leading: const Icon(Icons.shortcut_rounded),
              title: const Text('إعادة توجيه'),
              onTap: () {
                Navigator.pop(ctx);
                _forward(m);
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
              leading: Icon(Icons.delete_outline, color: context.wasl.danger),
              title: Text('حذف للجميع',
                  style: TextStyle(color: context.wasl.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(m);
              },
            ),
          if (!mine)
            ListTile(
              leading: Icon(Icons.flag_outlined, color: context.wasl.warning),
              title: Text('إبلاغ عن الرسالة',
                  style: TextStyle(color: context.wasl.warning)),
              onTap: () {
                Navigator.pop(ctx);
                _report(m);
              },
            ),
        ]),
      ),
    );
  }

  /// إبلاغ عن رسالة (مطلوب لمتاجر التطبيقات) — يُسجَّل للمراجعة اليدوية فقط
  Future<void> _report(Map<String, dynamic> m) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('لماذا تُبلّغ عن هذه الرسالة؟'),
        children: [
          for (final (v, label) in const [
            ('spam', 'محتوى مزعج أو إعلانات'),
            ('inappropriate', 'محتوى غير لائق'),
            ('harassment', 'تنمر أو مضايقة'),
            ('fraud', 'احتيال أو انتحال'),
            ('other', 'سبب آخر'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, v),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await supabase.from('abuse_reports').insert({
        'target_user_id': m['sender_id'],
        'target_message_id': m['id'],
        'conversation_id': m['conversation_id'],
        'reason': reason,
      });
      _snack('تم إرسال البلاغ. شكراً لك');
    } catch (_) {
      _snack('تعذّر إرسال البلاغ');
    }
  }

  /// اقتباس الرسالة المردود عليها داخل الفقاعة
  Widget _quote(String replyId, bool mine) {
    final r = _byId[replyId];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: context.wasl.glass,
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
            style: TextStyle(color: _bubbleSecondary(mine), fontSize: 13)),
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
                color: mineEmoji == e.key
                    ? WaslColors.teal.withValues(alpha: 0.35)
                    : context.wasl.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.wasl.border),
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
        color: context.wasl.glass,
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
                style:
                    TextStyle(color: context.wasl.textSecondary, fontSize: 13)),
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
      appBar: _searching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _searching = false;
                  _searchCtrl.clear();
                }),
              ),
              title: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    hintText: 'ابحث في المحادثة…', border: InputBorder.none, filled: false),
              ),
            )
          : AppBar(
        titleSpacing: 0,
        title: GestureDetector(
         onTap: _isPrivateGroup
             ? _openGroupInfo
             : (!widget.isGroup && widget.otherId != null ? _openContact : null),
         behavior: HitTestBehavior.opaque,
         child: Row(children: [
          UserAvatar(
            name: _title,
            url: _otherAvatar,
            radius: 20,
            color: widget.isGroup ? WaslColors.teal : WaslColors.indigo,
            icon: widget.isGroup ? (widget.isChannel ? Icons.campaign : Icons.groups_2) : null,
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
                        color: _typing.isNotEmpty
                            ? WaslColors.teal
                            : context.wasl.textFaint)),
            ]),
          ),
         ]),
        ),
        actions: [
          IconButton(
            tooltip: 'بحث',
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Icons.search_rounded),
          ),
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
                      ? context.wasl.warning
                      : WaslColors.teal),
            ),
          IconButton(
            tooltip: 'لخّص المحادثة',
            onPressed: _confirmSummarize,
            icon: const Icon(Icons.auto_awesome, color: WaslColors.violet),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'disappear') _changeDisappearing();
              if (v == 'starred') setState(() => _starredOnly = !_starredOnly);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'starred',
                child: Text(_starredOnly ? 'كل الرسائل' : 'الرسائل المميزة بنجمة'),
              ),
              if (!widget.isChannel)
                PopupMenuItem(
                  value: 'disappear',
                  child: Text('الرسائل المختفية: ${disappearLabel(_disappear)}'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_disappear != null || _starredOnly)
            Material(
              color: context.wasl.glass,
              child: InkWell(
                onTap: _starredOnly
                    ? () => setState(() => _starredOnly = false)
                    : _changeDisappearing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Icon(_starredOnly ? Icons.star_rounded : Icons.timer_outlined,
                        size: 18,
                        color: _starredOnly
                            ? context.wasl.warning
                            : WaslColors.violet),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          _starredOnly
                              ? 'تعرض الرسائل المميزة بنجمة فقط. اضغط لعرض الكل.'
                              : 'الرسائل الجديدة تختفي بعد ${disappearLabel(_disappear)}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ]),
                ),
              ),
            ),
          if (_showSafety && E2eService.peerKeyChanged(widget.otherId!))
            Material(
              color: context.wasl.warningSoft,
              child: InkWell(
                onTap: _showSafetyNumber,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: context.wasl.warning),
                    const SizedBox(width: 10),
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
                final now = DateTime.now();
                final all = snap.data!.reversed.where((m) {
                  final e = m['expires_at'] as String?;
                  return e == null || DateTime.parse(e).isAfter(now);
                }).toList();
                _byId = {for (final m in all) m['id'] as String: m};
                // أصوات الاستطلاعات تُجمع من البث الحي ثم تُحجب عن قائمة الرسائل
                _votesByPoll = {};
                for (final m in all) {
                  if ((m['type'] ?? '') == 'poll_vote') {
                    final pid = m['poll_id'] as String?;
                    if (pid != null) (_votesByPoll[pid] ??= []).add(m);
                  }
                }
                final q = _query;
                final base = _starredOnly
                    ? all.where((m) => _stars.contains(m['id'])).toList()
                    : all;
                if (_starredOnly && base.isEmpty) {
                  _scheduleDecrypt(all);
                  return Center(
                      child: Text('لا رسائل مميزة بنجمة هنا',
                          style: TextStyle(color: context.wasl.textFaint)));
                }
                final msgs = q.isEmpty
                    ? base.where((m) => (m['type'] ?? '') != 'poll_vote').toList()
                    : base.where((m) {
                        if (m['deleted_at'] != null) return false;
                        final t = m['type'] ?? 'text';
                        // البحث يشمل اسم ورقم بطاقة الاتصال ووصف الموقع — 0.4.6
                        if (t == 'contact') {
                          final raw = _textOf(m);
                          final card =
                              raw == null ? null : ContactCardService.decode(raw);
                          if (card == null) return false;
                          return (card.name + card.phones.join())
                              .toLowerCase()
                              .contains(q);
                        }
                        if (t == 'location') {
                          final raw = _textOf(m);
                          final loc =
                              raw == null ? null : LocationService.decode(raw);
                          if (loc == null) return false;
                          return (loc.label ?? '').toLowerCase().contains(q) ||
                              loc.geoUri.contains(q);
                        }
                        if (t != 'text') return false;
                        return (_textOf(m) ?? '').toLowerCase().contains(q);
                      }).toList();
                if (q.isNotEmpty && msgs.isEmpty) {
                  _scheduleDecrypt(all);
                  return Center(
                      child: Text('لا نتائج',
                          style: TextStyle(color: context.wasl.textFaint)));
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _maybeMarkRead(all));
                _scheduleDecrypt(all);
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
                    // الملصق السليم بلا فقاعة: الشفاف نفسه بلا خلفية (0.4.9)
                    final stickerish =
                        m['type'] == 'sticker' && m['deleted_at'] == null;
                    return Align(
                      alignment: mine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: GestureDetector(
                       onLongPress: () => _messageActions(m),
                       child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: stickerish
                            ? const EdgeInsets.symmetric(horizontal: 6)
                            : const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: stickerish
                            ? null
                            : BoxDecoration(
                          gradient: mine ? WaslColors.gradient : null,
                          color: mine ? null : context.wasl.bubbleOther,
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
                            _body(m, mine: mine),
                            if (chips != null) chips,
                            const SizedBox(height: 2),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_stars.contains(m['id'])) ...[
                                Icon(Icons.star_rounded,
                                    size: 13, color: context.wasl.warning),
                                const SizedBox(width: 3),
                              ],
                              if (m['expires_at'] != null) ...[
                                Icon(Icons.timer_outlined,
                                    size: 12, color: _bubbleFaint(mine)),
                                const SizedBox(width: 3),
                              ],
                              if (m['scheduled'] == true) ...[
                                Icon(Icons.schedule_rounded,
                                    size: 12, color: _bubbleFaint(mine)),
                                const SizedBox(width: 3),
                              ],
                              if (m['edited_at'] != null && m['deleted_at'] == null) ...[
                                Text('معدّلة',
                                    style: TextStyle(
                                        color: _bubbleFaint(mine), fontSize: 11)),
                                const SizedBox(width: 4),
                              ],
                              Text(_time(m['created_at'] as String),
                                  style: TextStyle(
                                      color: _bubbleSecondary(mine), fontSize: 11)),
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
          if (_compressing || _uploading)
            const LinearProgressIndicator(minHeight: 2),
          // منتقي الإشارة @ (0.4.5) — شريط أعضاء فوق حقل الكتابة
          if (widget.canPost && !_recording && _mentionQuery != null)
            _mentionPicker(),
          // لوحة الملصقات (0.4.9) — فوق حقل الكتابة، تبقى مفتوحة للإرسال المتتابع
          if (widget.canPost && !_recording && _stickerPanel)
            SafeArea(
              top: false,
              child: StickerPanel(
                onPick: _sendSticker,
                onClose: () => setState(() => _stickerPanel = false),
              ),
            ),
          if (widget.canPost && _composeBanner() != null) _composeBanner()!,
          if (!widget.canPost)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.wasl.glass,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text('النشر هنا للمشرفين فقط',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.wasl.textFaint)),
              ),
            )
          else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Row(children: [
                if (!_recording) ...[
                  IconButton(
                    onPressed: _uploading
                        ? null
                        : () => setState(() => _stickerPanel = !_stickerPanel),
                    // المبتسم يفتح لوحة الملصقات (0.4.9) — وأيقونة لوحة
                    // المفاتيح تعيده للحقل
                    icon: Icon(_stickerPanel
                        ? Icons.keyboard_alt_outlined
                        : Icons.face_outlined),
                    tooltip: 'ملصقات',
                  ),
                  IconButton(
                    onPressed: _uploading ? null : _showAttachSheet,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                ],
                Expanded(
                  child: _recording
                      ? Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: context.wasl.glass,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(children: [
                            Icon(Icons.fiber_manual_record,
                                color: context.wasl.danger, size: 14),
                            const SizedBox(width: 8),
                            Text('جارٍ التسجيل ${_recLabel()}'),
                            const Spacer(),
                            Text('اترك للإرسال',
                                style: TextStyle(color: context.wasl.textFaint)),
                          ]),
                        )
                      : TextField(
                          controller: _text,
                          focusNode: _inputFocus,
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
                          // ضغط مطول = جدولة الإرسال (بند المرحلة 1)
                          onLongPress: _scheduleText,
                          tooltip: 'إرسال · ضغط مطول للجدولة',
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
                            color: _recording ? context.wasl.danger : null,
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
