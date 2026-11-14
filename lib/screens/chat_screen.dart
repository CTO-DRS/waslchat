import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/ai_service.dart';
import '../services/album_service.dart';
import '../services/app_lock_service.dart';
import '../services/block_service.dart';
import '../services/call_logic.dart';
import '../services/call_service.dart';
import '../services/channel_bell_service.dart';
import '../services/channel_stats_service.dart';
import '../services/e2e_service.dart';
import '../services/export_service.dart';
import '../services/forward_service.dart';
import '../services/image_edit_service.dart';
import '../services/link_preview_service.dart';
import '../services/daily_summary_service.dart';
import '../services/local_ai_service.dart';
import '../services/saved_service.dart';
import '../services/smart_search_service.dart';
import '../services/voice_read_service.dart';
import '../services/webio/web_files.dart';
import '../services/media_service.dart';
import '../services/moderation_service.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/group_avatar.dart';
import '../widgets/link_preview_card.dart';
import '../widgets/media_bubbles.dart';
import '../widgets/motion.dart';
import '../widgets/report_dialog.dart';
import 'album_preview_screen.dart';
import 'call_screen.dart';
import 'contact_screen.dart';
import 'group_info_screen.dart';
import 'image_editor_screen.dart';
import 'media_gallery_screen.dart';
import 'video_screen.dart';
import 'verify_qr_screen.dart';
import 'voice_room_screen.dart';

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
    this.isSaved = false,
    this.isBot = false,
    this.officialVerified = false,
    this.focusMessageId,
  });
  final String conversationId;
  final String title;
  final bool isGroup;
  final String? otherId;
  final bool isChannel;
  final bool canPost;

  /// تشفير بين الطرفين (خاص + مجموعات خاصة + المحفوظة فقط؛ القنوات وغرف
  /// المجتمعات ومحادثات البوتات لا)
  final bool encrypted;

  /// يفتح المحادثة على الرسائل المميزة بنجمة فقط
  final bool starredOnly;

  /// شارة التوثيق الرسمية (0.14.0): تُمرَّر للقنوات المستقلة الموثّقة وغرف
  /// المجتمعات الموثّقة — تظهر بجانب العنوان في رأس الشاشة فقط.
  final bool officialVerified;

  /// «رسائلي المحفوظة»: سحابة شخصية — لا معلومات مجموعة ولا مشاركون
  final bool isSaved;

  /// الطرف الآخر بوت (محادثة مباشرة غير مشفرة بالتصميم — البوت يقرأها)
  final bool isBot;

  /// القفز إلى رسالة محددة عند الفتح (معرض الوسائط — 0.21.0):
  /// يمرر القائمة على موضع الرسالة ويبرزها لحظة
  final String? focusMessageId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with RouteAware {
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

  /// الإيموجي المفكوك: النص المشفر ← الإيموجي الصريح (القديم الصريح يمر فوراً)
  final Map<String, String> _emojiPlain = {};
  // الرسائل المختفية والنجوم وصورة الطرف الآخر
  int? _disappear;
  Set<String> _stars = {};
  late bool _starredOnly = widget.starredOnly;
  String? _otherAvatar;

  /// مسار صورة المجموعة المشفرة (conversations.avatar_url)
  String? _groupAvatarPath;

  // البحث داخل المحادثة
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String get _query => _searchCtrl.text.trim().toLowerCase();

  // الحظر: أنا حظرتُ الطرف الآخر في محادثة فردية؟
  bool _iBlockedPeer = false;

  // هل الطرف الآخر موثّق بمسح QR على هذا الجهاز؟ (للمحادثات الفردية المشفّرة)
  bool _verified = false;

  // منع لقطات الشاشة لهذه المحادثة (أندرويد: FLAG_SECURE)
  bool _noScreenshots = false;

  // الكتم في غرف المجتمعات (ترحيل 023): نهاية الكتم إن كنت مكتوماً هنا
  DateTime? _mutedUntil;
  bool get _isMuted => _mutedUntil != null && _mutedUntil!.isAfter(DateTime.now());

  static const _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  bool _recording = false;
  bool _uploading = false;

  /// مسح المحادثة الشخصي (0.20.0 — ترحيل 031): الرسائل قبله مخفية عني حصراً
  DateTime? _clearedAt;

  /// آخر نسخة كاملة من الرسائل (للتصدير النصي من قائمة ⋮)
  List<Map<String, dynamic>> _allMsgs = const [];

  // القفز والإبراز (0.21.0): معرض الوسائط يفتح المحادثة على وسيط محدد
  final _itemScroll = ItemScrollController();
  bool _jumpDone = false;
  String? _highlightId;

  // جرس القنوات (0.21.0): حالة هذه القناة تُحمّل مرة وتحدّث من الحوار
  String _bell = 'all';
  bool _bellLoaded = false;

  // القراءة الصوتية (0.21.0)
  bool _ttsBusy = false;

  /// مفتاح «عرض مرة واحدة» في ورقة المرفقات — يسري على الصورة/الفيديو التالي
  bool _viewOnce = false;
  DateTime? _recStart;
  Timer? _ticker;

  // ---------- المرحلة 5: وصل AI المحلي والبحث الذكي والترجمة الفورية ----------
  /// ذاكرة «فُتح عنصر مسبقاً» حتى لا تُعاد حركة الدخول عند كل إعادة بناء
  final Set<String> _motionSeen = {};

  /// الترجمة الفورية لهذه المحادثة (مفتاح لكل محادثة — تراه أنت وحدك)
  bool _autoTranslate = false;
  static const _autoTranslateKeyPrefix = 'autotranslate_';
  bool _translateConfirming = false; // حوار موافقة مفتوح لا يُستدعى مرتين

  /// الترجمات المفكوك ذاكرةً: معرف الرسالة ← الترجمة (جلسة واحدة)
  final Map<String, String> _translations = {};
  final Set<String> _translating = {};

  /// تفريغ الصوتيات ذاكرةً: معرف الرسالة ← التفريغ (جلسة واحدة)
  final Map<String, String> _transcripts = {};
  final Set<String> _transcribing = {};

  /// الردود الذكية المحلية (محسوبة من آخر رسالة وردت)
  List<String> _smartReplies = const [];
  String? _repliesFor;

  /// الملخص اليومي المحلي (المرحلة 9 أ — 0.22.0): يُبنى عند أول فتح في اليوم
  /// ويُخزن في المخزن الآمن على الجهاز حصراً — بلا أي شبكة
  final DailySummaryStore _dailyStore = DailySummaryStore();
  bool _dailyTried = false;

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

  /// يفك نصاً مشفّراً واحداً (للمحادثات الخاصة: جلسة متدرجة v2 أو ثابت v1،
  /// وللمجموعات: يجرّب كل إصدارات المفتاح المعروفة)
  Future<String?> _decrypt(String content) async {
    if (!widget.isGroup) {
      final other = widget.otherId;
      if (other == null) return null;
      return E2eService.decryptDmText(widget.conversationId, other, content);
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

  /// فك إيموجي التفاعلات الواردة (المشفرة v1.) في الخلفية — القديم الصريح لا يحتاج
  void _decryptReactions(Map<String, Map<String, String>> map) {
    if (!_e2e) return;
    final raws = <String>{for (final r in map.values) ...r.values};
    for (final raw in raws) {
      if (_emojiPlain.containsKey(raw) || !E2eService.isEncrypted(raw)) continue;
      unawaited(_decryptEmoji(raw));
    }
  }

  Future<void> _decryptEmoji(String raw) async {
    String? p;
    if (!widget.isGroup) {
      final other = widget.otherId;
      if (other != null) p = await E2eService.decryptDmText(widget.conversationId, other, raw);
    } else {
      p = await E2eService.decryptGroupText(widget.conversationId, raw);
      if (p == null) {
        // ربما دُوِّر المفتاح: إعادة جلب مرة واحدة (كما في فك الرسائل)
        E2eService.invalidateGroupKey(widget.conversationId);
        p = await E2eService.decryptGroupText(widget.conversationId, raw);
      }
    }
    if (!mounted || _emojiPlain.containsKey(raw)) return;
    setState(() => _emojiPlain[raw] = p ?? '❔');
  }

  /// الإيموجي الصريح لقيمة مخزنة: المفكوك، أو القديم الصريح فوراً،
  /// أو '' لحين اكتمال الفك (تُحجب الشارة لحظة بدل إظهار نص مشفر)
  String _emojiOf(String raw) {
    final hit = _emojiPlain[raw];
    if (hit != null) return hit;
    if (!E2eService.isEncrypted(raw)) return raw;
    return '';
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
      final t = m['type'] ?? 'text';
      if (t != 'text' && t != 'file' && t != 'video') continue;
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

  static String _sizeLabel(int? b) {
    if (b == null) return '';
    if (b < 1024 * 1024) return '${(b / 1024).ceil()} ك.ب';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  // مشاهدات القنوات الكبيرة (المرحلة 4): معرّف الرسالة ← عدد المشاهدات
  final Map<String, int> _views = {};
  final Set<String> _viewTracked = {};
  bool _viewsBusy = false;

  /// مشاهدات القنوات (المرحلة 4): نسجّل مشاهدتي للمنشورات الجديدة
  /// ونحدّث العدّادات المعروضة تحت كل منشور
  void _trackChannelViews(List<Map<String, dynamic>> msgs) {
    if (!widget.isChannel || _viewsBusy) return;
    final fresh = [
      for (final m in msgs)
        if (m['deleted_at'] == null && !_viewTracked.contains(m['id'])) m['id'] as String
    ];
    if (fresh.isEmpty && _views.isNotEmpty) return;
    final allIds = [
      for (final m in msgs)
        if (m['deleted_at'] == null) m['id'] as String
    ];
    _viewsBusy = true;
    () async {
      try {
        if (fresh.isNotEmpty) {
          _viewTracked.addAll(fresh);
          await ChannelStatsService.trackViews(fresh);
        }
        final counts = await ChannelStatsService.counts(allIds);
        if (!mounted) return;
        setState(() {
          _views
            ..clear()
            ..addAll(counts);
        });
      } catch (_) {
        // بلا ترحيل 025 أو خطأ شبكة: العدّادات تختفي ولا يتعطل شيء
      } finally {
        _viewsBusy = false;
      }
    }();
  }

  /// هل أنا مكتوم في مجتمع هذه الغرفة؟ (للافتة داخل المحادثة)
  Future<void> _loadMuteState() async {
    try {
      final v = await supabase.rpc('my_mute_in_conversation',
          params: {'conv': widget.conversationId});
      if (!mounted || v == null) return;
      final until = DateTime.tryParse(v as String);
      if (until != null && until.isAfter(DateTime.now())) {
        setState(() => _mutedUntil = until.toLocal());
      }
    } catch (_) {}
  }

  /// طابع مسح المحادثة الشخصي (ترحيل 031): الرسائل قبله تُخفى عني حصراً
  Future<void> _loadClearedAt() async {
    try {
      final row = await supabase
          .from('conversation_participants')
          .select('cleared_at')
          .eq('conversation_id', widget.conversationId)
          .eq('user_id', _me)
          .maybeSingle();
      if (!mounted || row == null) return;
      final v = row['cleared_at'];
      if (v is String) setState(() => _clearedAt = DateTime.parse(v));
    } catch (_) {}
  }

  /// مسح المحادثة بتأكيد مزدوج — المسح يخفي الرسائل عنك حصراً
  /// (صفوف الرسائل المشتركة لا تُحذف أبداً)، ويحدّث معاينة القائمة
  /// وعدّاد غير المقروء عبر my_chats المحدثة.
  Future<void> _clearConversation() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('مسح المحادثة؟'),
        content: const Text(
            'ستُخفى كل رسائل هذه المحادثة عنك أنت فقط، ولا تُحذف عن أي عضو آخر، '
            'ولا تُحذف من الخادم إطلاقاً. ولا يمكن التراجع عن المسح.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('متابعة')),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد أخير'),
        content: Text('مسح «$_title» عنك أنت فقط نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('مسح نهائياً')),
        ],
      ),
    );
    if (second != true || !mounted) return;
    try {
      await supabase.rpc('clear_chat', params: {'p_conv': widget.conversationId});
      // إخفاء فوري محلي ثم تحديث من الخادم
      setState(() => _clearedAt = DateTime.now().toUtc());
    } catch (_) {
      _snack('تعذّر المسح — تأكد من تشغيل ترحيل 031 على الخادم');
    }
  }

  /// ---------- المرحلة 8 ب (0.21.0): القفز والإبراز والقراءة الصوتية والجرس ----------

  /// القفز إلى الرسالة المطلوبة عند الفتح (من معرض الوسائط): يمرر القائمة
  /// على موضع الرسالة (فهرس مجموعتها في القائمة) ويبرزها 4 ثوانٍ —
  /// مرة واحدة حصراً: التحديثات اللاحقة لا تعيد القفزة.
  void _maybeJumpToFocus(List<List<Map<String, dynamic>>> items) {
    if (_jumpDone) return;
    final target = widget.focusMessageId;
    if (target == null) {
      _jumpDone = true;
      return;
    }
    final idx = items.indexWhere((g) => g.any((m) => m['id'] == target));
    if (idx < 0) {
      _jumpDone = true; // الرسالة محذوفة أو قبل المسح الشخصي — بلا قفزة
      return;
    }
    _jumpDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _itemScroll.scrollTo(
            index: idx, duration: const Duration(milliseconds: 350), alignment: 0.35);
      } catch (_) {
        return; // فشل القفز: يبقى السلوك الافتراضي (آخر الرسائل)
      }
      if (mounted) {
        setState(() => _highlightId = target);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted && _highlightId == target) {
            setState(() => _highlightId = null);
          }
        });
      }
    });
  }

  /// فتح معرض وسائط المحادثة — يمرر معاملات التشفير نفسها للمطابقة
  void _openMediaGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaGalleryScreen(
          conversationId: widget.conversationId,
          title: _title,
          isGroup: widget.isGroup,
          isChannel: widget.isChannel,
          encrypted: widget.encrypted,
          otherId: widget.otherId,
          isSaved: widget.isSaved,
          isBot: widget.isBot,
        ),
      ),
    );
  }

  /// القراءة الصوتية لآخر رسائل المحادثة (TTS عربي على الجهاز حصراً):
  /// زر واحد — تشغيل يقرأ آخر 10 رسائل مفكوكة، نقر مجدد يوقف.
  Future<void> _toggleSpeak() async {
    if (VoiceReadService.speaking.value) {
      await VoiceReadService.stop();
      setState(() => _ttsBusy = false);
      return;
    }
    // آخر 10 رسائل مفكوكة بالترتيب الزمني التصاعدي (الأقدم يُقرأ أولاً)
    final spoken = <(String, String)>[];
    for (final m in _allMsgs.reversed) {
      if (m['deleted_at'] != null) continue;
      final t = _textOf(m);
      if (t == null || t.isEmpty || t == '🔒 تعذّر فك التشفير' || E2eService.isEncrypted(t)) {
        continue;
      }
      spoken.insert(0, (_senderName(m['sender_id'] as String? ?? ''), t));
      if (spoken.length >= 10) break;
    }
    if (spoken.isEmpty) {
      _snack('لا رسائل نصية مفكوكة للقراءة بعد');
      return;
    }
    final text = VoiceReadService.buildSpokenText(spoken, isGroup: widget.isGroup && !widget.isChannel);
    setState(() => _ttsBusy = true);
    final ok = await VoiceReadService.speak(text);
    if (!mounted) return;
    setState(() => _ttsBusy = false);
    if (!ok) _snack('القراءة غير مدعومة على هذا الجهاز — أو لا يوجد محرك عربي');
  }

  /// حالة جرس القناة — تُحمّل مرة (وهبوط للافتراضي بلا ترحيل 032)
  Future<void> _loadBell() async {
    if (_bellLoaded || !widget.isChannel) return;
    _bellLoaded = true;
    try {
      final rows = await supabase
          .from('conversation_participants')
          .select('bell')
          .eq('conversation_id', widget.conversationId)
          .eq('user_id', _me)
          .limit(1);
      if (mounted && rows.isNotEmpty) {
        setState(() => _bell = ChannelBellService.normalize(
            (rows.first as Map)['bell'] as String?));
      }
    } catch (_) {
      // عمود bell غير موجود بعد (الترحيل 032 لم يُشغّل) — الافتراضي all
    }
  }

  /// حوار اختيار جرس القناة: كل المنشورات / المثبتة فقط / صمت
  Future<void> _showBellDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          const ListTile(title: Text('إشعارات هذه القناة',
              style: TextStyle(fontWeight: FontWeight.w800))),
          for (final (v, icon, label) in const [
            ('all', Icons.notifications_active_outlined, 'كل المنشورات'),
            ('pinned', Icons.push_pin_outlined, 'المنشورات المثبتة فقط'),
            ('mute', Icons.notifications_off_outlined, 'صمت — لا إشعارات'),
          ])
            ListTile(
              leading: Icon(icon,
                  color: _bell == v ? WaslColors.teal : null),
              title: Text(label),
              trailing: _bell == v
                  ? const Icon(Icons.check_rounded,
                      size: 18, color: WaslColors.teal)
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                final old = _bell;
                setState(() => _bell = v);
                try {
                  await ChannelBellService.set(widget.conversationId, v);
                  if (mounted) {
                    _snack(v == 'mute'
                        ? 'صمتت هذه القناة — لن تصلك بياناتها أصلاً'
                        : v == 'pinned'
                            ? 'ستنبّهك المنشورات المثبتة فقط'
                            : 'ستنبهك كل منشورات القناة');
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() => _bell = old);
                    _snack('تعذّر الحفظ — تأكد من تشغيل الترحيل 032 والاتصال');
                  }
                }
              },
            ),
        ]),
      ),
    );
  }

  /// تصدير المحادثة نصاً — كل النصوص من المفكوك على جهازك، والملف لا يغادر
  /// جهازك إلا بمشاركتك أنت (تقرير الشفافية: مسار محلي صريح)
  Future<void> _exportConversation() async {
    final msgs = _allMsgs;
    if (msgs.isEmpty) {
      _snack('لا رسائل لتصديرها');
      return;
    }
    // انتظار فك النصوص المشفرة المعلقة (أقصى انتظار معقول)
    for (var i = 0; i < 20 && _plain.length < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final now = DateTime.now();
    final text = ExportService.buildText(
      title: _title,
      msgs: msgs,
      senderOf: (id) => _senderName(id),
      textOf: (m) => _textOf(m),
      myId: _me,
      now: now,
      appVersion: AppConfig.appVersion,
    );
    final name = ExportService.fileName(_title, now);
    try {
      if (kIsWeb) {
        webDownload(Uint8List.fromList(utf8.encode(text)), name, 'text/plain; charset=utf-8');
        return;
      }
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsString(text, flush: true);
      await SharePlus.instance.share(ShareParams(
          files: [XFile(f.path, mimeType: 'text/plain')],
          subject: 'تصدير محادثة وصل شات'));
    } catch (_) {
      _snack('تعذّر تصدير المحادثة');
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
    _loadMeta();
    _refreshBlockState();
    unawaited(_refreshVerified());
    unawaited(_loadMuteState());
    unawaited(_loadAutoTranslatePref());
    unawaited(_loadClearedAt());
    unawaited(_loadBell()); // جرس القنوات (0.21.0)
    PushService.visibleConversation = widget.conversationId;
    ScreenshotService.flagOf(widget.conversationId).then((v) {
      if (!mounted || !v) return;
      setState(() => _noScreenshots = true);
      ScreenshotService.setSecure(true);
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
      _decryptReactions(map);
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

  Future<void> _loadMeta() async {
    try {
      final conv = await supabase
          .from('conversations')
          .select('disappear_seconds, avatar_url')
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
        _stars = {for (final r in stars) r['message_id'] as String};
        _otherAvatar = avatar;
        _groupAvatarPath = conv?['avatar_url'] as String?;
      });
    } catch (_) {}
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
    ).then((changed) {
      if (changed == true) {
        _refreshBlockState();
      } else {
        _loadMeta();
      }
    });
  }

  Future<void> _refreshBlockState() async {
    final other = widget.otherId;
    if (widget.isGroup || other == null) return;
    await BlockService.ensureLoaded();
    if (mounted) setState(() => _iBlockedPeer = BlockService.isBlocked(other));
  }

  Future<void> _unblockPeer() async {
    final other = widget.otherId;
    if (other == null) return;
    try {
      await BlockService.unblock(other);
      if (mounted) setState(() => _iBlockedPeer = false);
    } catch (_) {
      _snack('تعذّر إلغاء الحظر');
    }
  }

  Widget _blockedBanner() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.block_rounded, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Text('أنت تحظر هذا الاتصال',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('لن تصل رسائله الجديدة إليك، ولا يمكن الإرسال إليه.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textTertiary, fontSize: 12)),
          TextButton(
            onPressed: _unblockPeer,
            child: const Text('إلغاء الحظر'),
          ),
        ]),
      ),
    );
  }

  /// لافتة الكتم في غرف المجتمعات: تُحل محل شريط الإدخال كلياً
  Widget _mutedBanner() {
    final until = ModerationService.formatUntil(_mutedUntil!, DateTime.now());
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Icon(Icons.mic_off_outlined, size: 18, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('أنت مكتوم في هذا المجتمع حتى $until',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
          ),
        ]),
      ),
    );
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    ScreenshotService.routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    // عدنا من شاشة أعلى: أعد تطبيق منع اللقطات الخاص بهذه المحادثة
    ScreenshotService.setSecure(_noScreenshots);
  }

  Future<void> _toggleNoScreenshots() async {
    final v = !_noScreenshots;
    await ScreenshotService.setSecure(v);
    await ScreenshotService.setFlag(widget.conversationId, v);
    if (mounted) {
      setState(() => _noScreenshots = v);
      _snack(v ? 'مُنع التقاط الشاشة في هذه المحادثة' : 'أُسمح بلقطات الشاشة مجدداً');
    }
  }

  @override
  void dispose() {
    ScreenshotService.routeObserver.unsubscribe(this);
    ScreenshotService.setSecure(false);
    if (PushService.visibleConversation == widget.conversationId) {
      PushService.visibleConversation = null;
    }
    // القراءة الصوتية تتوقف عند مغادرة المحادثة (0.21.0)
    VoiceReadService.stop();
    _ticker?.cancel();
    _typingSweep?.cancel();
    _partsSub?.cancel();
    _reactSub?.cancel();
    PresenceService.online.removeListener(_onPresence);
    supabase.removeChannel(_room);
    supabase.rpc('mark_read', params: {'conv': widget.conversationId});
    _recorder.dispose();
    _text.dispose();
    _searchCtrl.dispose();
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
  bool get _showSafety =>
      _e2e && !widget.isGroup && widget.otherId != null && !widget.isBot;

  Future<void> _refreshVerified() async {
    if (!_showSafety) return;
    final v = await E2eService.isVerified(widget.otherId!);
    if (mounted) setState(() => _verified = v);
  }

  Future<void> _openVerifyQr() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VerifyQrScreen(otherUserId: widget.otherId!)));
    if (mounted) {
      setState(() {});
      unawaited(_refreshVerified());
    }
  }

  /// بدء مكالمة من المحادثة (0.17.0): طابور واحد — مكالمة واحدة في كل مرة
  Future<void> _startCall(CallKind kind) async {
    final s = await CallService.start(
      conversationId: widget.conversationId,
      peerId: widget.otherId!,
      peerName: _title,
      peerAvatar: _otherAvatar,
      kind: kind,
    );
    if (!mounted) return;
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا يمكن بدء المكالمة الآن — مكالمة جارية أو المحادثة لا تدعمها')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(session: s)));
  }

  /// فتح غرفة الصوت الجماعية (0.18.0): للمجموعات الخاصة المشفّرة فقط
  Future<void> _openVoiceRoom() async {
    if (_isPrivateGroup) {
      await showVoiceRoomIntro(
          context, conversationId: widget.conversationId, title: _title);
    }
  }

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
          if (number != null)
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                _openVerifyQr();
              },
              child: const Text('تحقق بمسح رمز QR'),
            ),
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
    if (mounted) {
      setState(() {});
      unawaited(_refreshVerified());
    }
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
    if (_isMuted) {
      _snack('أنت مكتوم في هذا المجتمع — لا يمكنك الإرسال');
      return;
    }
    final editing = _editing;
    final replyTo = _replyTo;
    var payload = content;
    if (_e2e) {
      final isDm = !widget.isGroup && widget.otherId != null;
      if (isDm) {
        // حد المحادثة الخاصة يتقلص بزيادة الأجهزة المرتبطة (v3)
        final lim = await E2eService.dmPlainLimit(widget.otherId!);
        if (utf8.encode(content).length > lim) {
          _snack('الرسالة طويلة جداً');
          return;
        }
      } else if (!E2eService.withinPlainLimit(content)) {
        _snack('الرسالة طويلة جداً');
        return;
      }
      if (isDm) {
        // المحادثات الخاصة: جلسة متدرجة v2 (سرية أمامية) أو رجوع v1
        try {
          final p = await E2eService.encryptDmText(
              widget.conversationId, widget.otherId!, content);
          if (p == null) {
            _snack(_keyMissingMsg());
            return;
          }
          payload = p;
        } catch (_) {
          _snack('تعذّر تشفير الرسالة');
          return;
        }
      } else {
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
      } catch (e) {
        _snack(ModerationService.sendErrorHint(e) ??
            'تعذّر تعديل الرسالة (التعديل متاح خلال 48 ساعة)');
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
    } catch (e) {
      _snack(ModerationService.sendErrorHint(e) ??
          (BlockService.isBlockedError(e)
              ? 'لا يمكن الإرسال — الحظر مفعّل بينكما'
              : 'تعذّر إرسال الرسالة'));
    }
  }

  Future<void> _sendMedia({
    required String type,
    required Uint8List bytes,
    required String ext,
    required String contentType,
    int? durationMs,
    Map<String, dynamic>? meta,
    bool viewOnce = false,
    String? groupId,
  }) async {
    setState(() => _uploading = true);
    try {
      var content = meta == null ? '' : jsonEncode(meta);
      var payload = bytes;
      var upExt = ext;
      var upType = contentType;
      if (_e2e) {
        // بايتات الوسيط تبقى على مفتاح المحادثة الثابت في هذا الإصدار،
        // وبيانات الوصف/التسمية تمر عبر الجلسة المتدرجة في الخاص
        final key = await _convKey();
        if (key == null) {
          _snack(_keyMissingMsg());
          return;
        }
        payload = await E2eService.encryptBytes(key, widget.conversationId, bytes);
        if (content.isNotEmpty) {
          if (!widget.isGroup && widget.otherId != null) {
            final p = await E2eService.encryptDmText(
                widget.conversationId, widget.otherId!, content);
            if (p == null) {
              _snack(_keyMissingMsg());
              return;
            }
            content = p;
          } else {
            content = await E2eService.encryptText(key, widget.conversationId, content);
          }
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
        if (groupId != null) 'media_group_id': groupId,
        if (replyTo != null) 'reply_to': replyTo['id'],
      });
      if (mounted) setState(() {
        _replyTo = null;
        _viewOnce = false;
      });
    } catch (e) {
      _snack(ModerationService.sendErrorHint(e) ??
          (BlockService.isBlockedError(e)
              ? 'لا يمكن الإرسال — الحظر مفعّل بينكما'
              : 'تعذّر رفع الملف'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------- الصور ----------

  /// صورة واحدة (معرض أو كاميرا): تمر عبر محرر الصورة المحلي قبل الإرسال —
  /// «تخطي» في المحرر يعيد نفس البايتات الأصلية.
  Future<void> _pickImage(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (x == null) return;
    var bytes = await x.readAsBytes();
    final edited = await ImageEditorScreen.open(context, bytes, fileName: x.name);
    if (edited == null) return; // المستخدم رفض الإرسال من المحرر
    bytes = edited;
    final (ext, mime) = ImageEditService.contentTypeOf(bytes);
    await _sendMedia(
      type: 'image',
      bytes: bytes,
      ext: ext,
      contentType: mime,
      viewOnce: _viewOnce,
    );
  }

  /// الألبوم المتعدد (0.20.0): حتى 10 صور بمعاينة متسلسلة ثم إرسال
  /// مشفر قطعة قطعة بمعرّف مجموعة واحد يجمّع العرض عند الجميع
  Future<void> _pickAlbum() async {
    final picked = await _picker.pickMultiImage(
        limit: AlbumService.maxItems, maxWidth: 1600, imageQuality: 80);
    if (picked.isEmpty) return;
    final chosen = await AlbumPreviewScreen.open(context, picked);
    if (chosen == null || chosen.isEmpty || !mounted) return;
    if (_isMuted) {
      _snack('أنت مكتوم في هذا المجتمع — لا يمكنك الإرسال');
      return;
    }
    final gid = AlbumService.newGroupId();
    setState(() => _uploading = true);
    try {
      for (final f in chosen) {
        if (!mounted) return;
        try {
          final bytes = await f.readAsBytes();
          await _sendMedia(
            type: 'image',
            bytes: bytes,
            ext: 'jpeg',
            contentType: 'image/jpeg',
            groupId: gid,
          );
        } catch (_) {
          // قطعة فاشلة لا تكسر البقية
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static const _maxBytes = 24 * 1024 * 1024;

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (x == null) return;
    final size = await x.length();
    if (size > _maxBytes) {
      _snack('الفيديو أكبر من 24 ميغابايت');
      return;
    }
    final bytes = await x.readAsBytes();
    final ext = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'mp4';
    await _sendMedia(
      type: 'video',
      bytes: bytes,
      ext: ext,
      contentType: ext == 'mov' ? 'video/quicktime' : 'video/mp4',
      meta: {'name': x.name, 'size': size},
      viewOnce: _viewOnce,
    );
  }

  Future<void> _pickFile() async {
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

  /// يفك الملف إلى مجلد مؤقت ثم يفتحه (الفيديو داخل التطبيق، وغيره بتطبيق مناسب)
  Future<void> _openMedia(Map<String, dynamic> m) async {
    if (kIsWeb) return _openMediaWeb(m);
    setState(() => _uploading = true);
    try {
      final bytes = await _mediaBytes(m['media_url'] as String);
      if (bytes == null) {
        _snack('تعذّر تنزيل الملف');
        return;
      }
      final meta = _metaOf(m);
      var name = (meta?['name'] as String?) ?? (m['type'] == 'video' ? 'video.mp4' : 'file');
      name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dir = Directory('${(await getTemporaryDirectory()).path}/wasl_open');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      if (m['type'] == 'video') {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => VideoScreen(file: file)));
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

  /// الويب: الفيديو يُشغَّل من رابط blob، والملفات تُنزَّل عبر المتصفح
  Future<void> _openMediaWeb(Map<String, dynamic> m) async {
    setState(() => _uploading = true);
    try {
      final bytes = await _mediaBytes(m['media_url'] as String);
      if (bytes == null) {
        _snack('تعذّر تنزيل الملف');
        return;
      }
      final meta = _metaOf(m);
      var name = (meta?['name'] as String?) ?? (m['type'] == 'video' ? 'video.mp4' : 'file');
      name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (!mounted) return;
      if (m['type'] == 'video') {
        final mime = name.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
        final url = webBlobUrl(bytes, mime);
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => VideoScreen(url: url)));
      } else {
        webDownload(bytes, name, 'application/octet-stream');
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
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          SwitchListTile(
            secondary: const Icon(Icons.looks_one_rounded, color: Colors.redAccent),
            title: const Text('عرض مرة واحدة',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'الصورة أو الفيديو التاليان تُحذف من الخادم بعد مشاهدتها'),
            value: _viewOnce,
            onChanged: (v) => setState(() => _viewOnce = v),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: WaslColors.teal),
            title: Text(
                _viewOnce ? 'صورة (عرض مرة واحدة)' : 'صورة من المعرض'),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_album_outlined, color: WaslColors.indigo),
            title: const Text('ألبوم صور'),
            subtitle: const Text('حتى 10 صور برسالة واحدة — معاينة متسلسلة'),
            onTap: () {
              Navigator.pop(ctx);
              _pickAlbum();
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
          ListTile(
            leading: const Icon(Icons.movie_outlined, color: WaslColors.violet),
            title: const Text('فيديو'),
            subtitle: const Text('حتى 24 ميغابايت'),
            onTap: () {
              Navigator.pop(ctx);
              _pickVideo();
            },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined, color: Colors.amber),
            title: const Text('ملف'),
            subtitle: const Text('PDF، مستندات، وغيرها حتى 24 ميغابايت'),
            onTap: () {
              Navigator.pop(ctx);
              _pickFile();
            },
          ),
        ]),
      ),
    );
  }

  // ---------- التسجيل الصوتي (اضغط مطولاً) ----------
  Future<void> _startRec() async {
    if (!await _recorder.hasPermission()) {
      _snack('اسمح للتطبيق باستخدام الميكروفون');
      return;
    }
    if (kIsWeb) {
      // المتصفح يسجّل Opus داخل WebM، والمسار يُتجاهل
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.opus), path: '');
    } else {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    }
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
      ext: kIsWeb ? 'webm' : 'm4a',
      contentType: kIsWeb ? 'audio/webm' : 'audio/mp4',
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

  // ---------- عرض مرة واحدة ----------

  Widget _viewOnceBody(Map<String, dynamic> m) {
    final mine = m['sender_id'] == _me;
    final viewed = m['viewed_at'] != null;
    // المرسل يفتح نسخته حتى أول مشاهدة؛ المستلم مرة واحدة فقط
    final canOpen = !viewed;
    return ViewOnceCard(
      mine: mine,
      viewed: viewed,
      mediaType: m['type'] as String? ?? 'image',
      onTap: canOpen ? () => _openViewOnce(m) : null,
    );
  }

  /// فتح وسيط «عرض مرة واحدة»: تنزيل وفك أولاً، ثم تسجيل المشاهدة (RPC)،
  /// ثم عرض بمنع لقطات الشاشة — والوسيط يحذفه الخادم عند اكتمال المشاهدات.
  Future<void> _openViewOnce(Map<String, dynamic> m) async {
    setState(() => _uploading = true);
    final wasSecure = await ScreenshotService.flagOf(widget.conversationId);
    var secured = false;
    try {
      final bytes = await _mediaBytes(m['media_url'] as String);
      if (bytes == null) {
        _snack('انتهى هذا الوسيط أو تعذّر فك تشفيره');
        return;
      }
      // سجّل المشاهدة قبل العرض (قد يحذف الخادم الملف فوراً) — بصمت عند فشل مؤقت
      if (m['sender_id'] != _me) {
        try {
          await supabase.rpc('open_view_once', params: {'p_id': m['id']});
        } catch (_) {}
      }
      if (!kIsWeb && !wasSecure) {
        await ScreenshotService.setSecure(true);
        secured = true;
      }
      if (!mounted) return;
      if (m['type'] == 'video') {
        if (kIsWeb) {
          final url = webBlobUrl(bytes, 'video/mp4');
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => VideoScreen(url: url)));
        } else {
          final dir = await getTemporaryDirectory();
          final f = File(
              '${dir.path}/view_once_${DateTime.now().millisecondsSinceEpoch}.mp4');
          await f.writeAsBytes(bytes, flush: true);
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => VideoScreen(file: f)));
        }
      } else {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => ViewOnceImageScreen(bytes: bytes)));
      }
    } catch (_) {
      _snack('تعذّر فتح الوسيط');
    } finally {
      if (secured) await ScreenshotService.setSecure(wasSecure);
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// فقاعة الألبوم المتعدد (0.20.0): شبكة صور متتالية بمربع واحد،
  /// اسم المرسل فوقها والوقت تحتها — الضغط على أي صورة يفتحها بملء الشاشة
  /// والضغط المطول يفتح إجراءات أول قطعة.
  Widget _albumTile(List<Map<String, dynamic>> item) {
    final first = item.first;
    final mine = first['sender_id'] == _me;
    final sender = _names[first['sender_id']];
    final width = MediaQuery.of(context).size.width * 0.75;
    final tile = (width - 6) / 3;
    final firstTime = _motionSeen.add('album_${first['id']}');
    Widget bubble = GestureDetector(
      onLongPress: () => _messageActions(first),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: width),
        decoration: BoxDecoration(
          gradient: mine ? WaslColors.gradient : null,
          color: mine ? null : context.bubbleOther,
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
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final m in item)
                  SizedBox(
                    width: tile,
                    height: tile,
                    child: ImageBubble(
                        loader: () => _mediaBytes(m['media_url'] as String),
                        width: tile),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${item.length} وسائط',
                  style: TextStyle(
                      color: mine ? Colors.white60 : context.textTertiary,
                      fontSize: 11)),
              const SizedBox(width: 6),
              Text(_time(first['created_at'] as String),
                  style: TextStyle(
                      color: mine ? Colors.white70 : context.textSecondary,
                      fontSize: 11)),
              if (mine) ...[const SizedBox(width: 4), _ticks(item.last)],
            ]),
          ],
        ),
      ),
    );
    if (firstTime) {
      bubble = MotionBubble(child: bubble, mine: mine);
    }
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: bubble,
    );
  }

  Widget _body(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      final mine = m['sender_id'] == _me;
      final c = mine ? Colors.white60 : context.textTertiary;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 16, color: c),
        const SizedBox(width: 6),
        Text('حُذفت هذه الرسالة',
            style: TextStyle(color: c, fontStyle: FontStyle.italic)),
      ]);
    }
    if (m['view_once'] == true &&
        (m['type'] == 'image' || m['type'] == 'video')) {
      return _viewOnceBody(m);
    }
    switch (m['type'] as String? ?? 'text') {
      case 'image':
        return ImageBubble(loader: () => _mediaBytes(m['media_url'] as String));
      case 'voice':
        return VoiceBubble(
            loader: () => _mediaBytes(m['media_url'] as String),
            durationMs: m['duration_ms'] as int?);
      case 'video':
      case 'file':
        final isVideo = m['type'] == 'video';
        final meta = _metaOf(m);
        final name = (meta?['name'] as String?) ?? (isVideo ? 'فيديو' : 'ملف');
        final mine = m['sender_id'] == _me;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openMedia(m),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: mine
                  ? Colors.black.withValues(alpha: 0.18)
                  : context.glass,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isVideo ? Icons.play_circle_fill : Icons.insert_drive_file_rounded,
                  size: 36, color: mine ? Colors.white : context.iconStd),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: mine ? Colors.white : context.textPrimary,
                          fontWeight: FontWeight.w600)),
                  Text(
                      [
                        isVideo ? 'فيديو' : 'ملف',
                        _sizeLabel((meta?['size'] as num?)?.toInt()),
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: TextStyle(
                          color: mine ? Colors.white70 : context.textSecondary,
                          fontSize: 12)),
                ]),
              ),
            ]),
          ),
        );
      default:
        final text = _textOf(m);
        final mine = m['sender_id'] == _me;
        final shown = text ?? '🔒 جارٍ فك التشفير…';
        // معاينة الروابط (0.21.0): بطاقة تحت النص إن كان يضم رابطاً عاماً —
        // بلا رابط أو ميزة معطلة أو فشل جلب: لا بطاقة إطلاقاً (هبوط صامت)
        final hasUrl = text != null &&
            text.isNotEmpty &&
            !text.startsWith('{') &&
            !E2eService.isEncrypted(text) &&
            LinkPreviewService.enabled.value &&
            LinkPreviewService.extractFirstUrl(text) != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(shown,
                style: TextStyle(
                    color: mine ? Colors.white : context.textPrimary, fontSize: 16)),
            if (hasUrl && m['deleted_at'] == null)
              LinkPreviewCard(text: text, mine: mine),
          ],
        );
    }
  }

  /// سطر الترجمة الفورية تحت رسالة واردة — أو مؤشر «جارٍ الترجمة»
  Widget _translationLine(Map<String, dynamic> m) {
    final id = m['id'] as String;
    final t = _translations[id];
    if (t == null) {
      if (_translating.contains(id)) {
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('جارٍ الترجمة…',
              style: TextStyle(
                  color: mineColor(m), fontSize: 12, fontStyle: FontStyle.italic)),
        );
      }
      return const SizedBox.shrink(); // لم تصل ترجمتها بعد — تظهر عند جهوزها
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t,
            style: TextStyle(
                color: mineColor(m),
                fontSize: 13.5,
                height: 1.4,
                fontStyle: FontStyle.italic)),
      ),
    );
  }

  /// لون نص الترجمة حسب صاحب الفقاعة
  Color mineColor(Map<String, dynamic> m) =>
      m['sender_id'] == _me ? Colors.white70 : context.textSecondary;

  // ---------- المرحلة 5: الترجمة الفورية والردود الذكية والتفريغ ----------
  static const _secure = FlutterSecureStorage();

  Future<void> _loadAutoTranslatePref() async {
    try {
      final v = await _secure.read(
          key: '$_autoTranslateKeyPrefix${widget.conversationId}');
      if (!mounted || v == null) return;
      setState(() => _autoTranslate = v == '1');
    } catch (_) {}
  }

  Future<void> _toggleAutoTranslate() async {
    if (!_autoTranslate && !_translateConfirming) {
      // موافقة صريحة مرة واحدة: الترجمة ترسل نص الرسائل إلى Gemini
      _translateConfirming = true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تشغيل الترجمة الفورية'),
          content: const Text(
              'ستُترجم الرسائل النصية الواردة تلقائياً ويظهر المترجم تحت الأصل. '
              'للترجمة، يُرسل نص الرسائل الواردة إلى خادم وصل ثم إلى Google Gemini. '
              'هذا النص لن يكون مشفّراً بين الطرفين أثناء الترجمة، والترجمة تُحفظ في جهازك لهذه الجلسة فقط. تتابع؟',
              style: TextStyle(height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تشغيل')),
          ],
        ),
      );
      _translateConfirming = false;
      if (ok != true || !mounted) return;
    }
    final next = !_autoTranslate;
    setState(() => _autoTranslate = next);
    try {
      await _secure.write(
          key: '$_autoTranslateKeyPrefix${widget.conversationId}',
          value: next ? '1' : '0');
    } catch (_) {}
    if (next) _snack('الترجمة الفورية تعمل — ستظهر الترجمة تحت الرسائل الواردة');
  }

  /// يترجم رسالة واردة في الخلفية (بعد فك تشفيرها محلياً)
  Future<void> _translateIncoming(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    if (_translating.contains(id) || _translations.containsKey(id)) return;
    final plain = _textOf(m);
    if (plain == null || plain.trim().isEmpty) return; // لم يُفك بعد
    if (E2eService.isEncrypted(plain)) return;
    _translating.add(id);
    final target = LocalAiService.isMostlyArabic(plain) ? 'en' : 'ar';
    try {
      final t = await AiService.translate(plain, target);
      if (mounted && t.trim().isNotEmpty) {
        setState(() => _translations[id] = t);
      }
    } catch (_) {
      // بلا شبكة: تظهر الرسالة الأصلية وحدها
    } finally {
      _translating.remove(id);
    }
  }

  /// جدولة ترجمة الرسائل الواردة الجديدة (تُستدعى بعد بناء القائمة)
  void _scheduleTranslate(List<Map<String, dynamic>> msgs) {
    if (!_autoTranslate) return;
    for (final m in msgs) {
      if (m['deleted_at'] != null) continue;
      if ((m['type'] ?? 'text') != 'text') continue;
      if (m['sender_id'] == _me) continue;
      final id = m['id'] as String;
      if (_translations.containsKey(id) || _translating.contains(id)) continue;
      unawaited(_translateIncoming(m));
    }
  }

  // ---------- الملخص اليومي المحلي (المرحلة 9 أ — 0.22.0) ----------
  /// يُستدعى بعد بناء القائمة مرة واحدة في الفتح: يقرأ ملخص اليوم من المخزن
  /// الآمن، وإن لم يوجد يبنى من رسائل اليوم المفكوكة ويُخزن — صمت تام عند أي فشل.
  Future<void> _ensureDailySummary(List<Map<String, dynamic>> all) async {
    if (_dailyTried || widget.isSaved || all.isEmpty) return;
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    // لا يُخزَّن ملخص ناقص: ننتظر اكتمال فك نصوص اليوم (تُعاد المحاولة بالبناء التالي)
    for (final m in all.reversed) {
      final created =
          DateTime.tryParse((m['created_at'] ?? '') as String)?.toLocal();
      if (created == null || created.isBefore(dayStart)) continue;
      if (m['deleted_at'] != null) continue;
      if ((m['type'] ?? 'text') != 'text') continue;
      final raw = (m['content'] ?? '') as String;
      if (E2eService.isEncrypted(raw) && !_plain.containsKey(raw)) return;
    }
    _dailyTried = true;
    try {
      if (await _dailyStore.load(widget.conversationId, now) != null) return;
      final text = _buildDailySummaryFrom(all);
      if (text != null) await _dailyStore.save(widget.conversationId, text, now);
    } catch (_) {
      // الفشل يهبط: القائمة تعمل والملخص الفوري في قائمة وصل AI يعمل على أي حال
    }
  }

  /// بناء ملخص اليوم من رسائل اليوم المفكوكة — null إن لم توجد رسائل اليوم
  String? _buildDailySummaryFrom(List<Map<String, dynamic>> all) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final lines = <DailyLine>[];
    for (final m in all.reversed) {
      final created =
          DateTime.tryParse((m['created_at'] ?? '') as String)?.toLocal();
      if (created == null || created.isBefore(dayStart)) continue;
      if (m['deleted_at'] != null) continue;
      final who = m['sender_id'] == _me ? 'أنت' : (_names[m['sender_id']] ?? 'عضو');
      final type = (m['type'] ?? 'text') as String;
      if (type == 'image' || type == 'voice' || type == 'video' || type == 'file') {
        lines.add(DailyLine(who: who, text: '[وسائط]', isMedia: true));
        continue;
      }
      final plain = _textOf(m);
      if (plain == null || plain.trim().isEmpty) continue;
      lines.add(DailyLine(who: who, text: plain));
    }
    return DailySummaryService.build(lines, now);
  }

  /// ملخص اليوم للعرض من قائمة وصل AI: المخزن أولاً ثم البناء فوراً
  Future<String> _dailySummary() async {
    final now = DateTime.now();
    final stored = await _dailyStore.load(widget.conversationId, now);
    if (stored != null) return stored;
    final text = _buildDailySummaryFrom(_allMsgs);
    if (text != null) {
      unawaited(_dailyStore.save(widget.conversationId, text, now));
      return text;
    }
    return 'لا توجد رسائل اليوم بعد — الملخص يُبنى تلقائياً مع أول رسالة.';
  }

  /// تفريغ رسالة صوتية نصاً: موافقة صريحة ثم إرسال الصوت لـGemini عبر خادم وصل
  Future<void> _transcribeVoice(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final cached = _transcripts[id];
    if (cached != null) {
      _showAiResult('تفريغ الرسالة الصوتية', Future.value(cached));
      return;
    }
    if (_transcribing.contains(id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تفريغ الرسالة الصوتية نصاً'),
        content: const Text(
            'سيُرسل الصوت إلى خادم وصل ثم إلى Google Gemini لتفريغه نصياً. '
            'الصوت لن يُخزَّن ولا يُسجَّل، والتفريغ يظهر لك وحدك. تتابع؟',
            style: TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('فرّغ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _transcribing.add(id);
    _showAiResult('تفريغ الرسالة الصوتية', () async {
      try {
        final bytes = await _mediaBytes(m['media_url'] as String);
        if (bytes == null) throw Exception('no audio');
        final t = await AiService.transcribe(
          bytes,
          mime: kIsWeb ? 'audio/webm' : 'audio/mp4',
        );
        _transcripts[id] = t;
        return t;
      } finally {
        _transcribing.remove(id);
      }
    }());
  }

  /// ورقة «وصل AI» لهذه المحادثة: ملخص محلي فوري أو ملخص سحابي بالموافقة
  void _showAiMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.surfaceAlt,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.calendar_today_rounded, color: WaslColors.indigo),
              title: const Text('ملخص اليوم'),
              subtitle: const Text(
                  'يُبنى عند أول فتح في اليوم ويُخزن على جهازك — بلا أي شبكة'),
              onTap: () {
                Navigator.pop(ctx);
                _showAiResult('ملخص اليوم — على جهازك', _dailySummary());
              },
            ),
            ListTile(
              leading: const Icon(Icons.bolt_rounded, color: WaslColors.teal),
              title: const Text('ملخص محلي فوري'),
              subtitle: const Text('على جهازك — لا يغادر أي شيء، بلا موافقة ولا شبكة'),
              onTap: () {
                Navigator.pop(ctx);
                _showAiResult('ملخص محلي (على جهازك)', _localSummary());
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: WaslColors.violet),
              title: const Text('ملخص سحابي أعمق'),
              subtitle: const Text('بموافقة صريحة — يمر عبر خادم وصل إلى Gemini'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmSummarize();
              },
            ),
          ]),
        ),
      ),
    );
  }

  /// الملخص المحلي: يجلب آخر 80 رسالة، يفك تشفيرها على الجهاز، ويلخّص محلياً
  Future<String> _localSummary() async {
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
    return LocalAiService.summarizeLines(lines);
  }

  /// تحديث الردود الذكية من آخر رسالة وردت نصاً (تُستدعى بعد بناء القائمة)
  void _refreshSmartReplies(List<Map<String, dynamic>> newestFirst) {
    if (!widget.canPost || widget.isSaved || widget.isChannel) {
      if (_smartReplies.isNotEmpty || _repliesFor != null) {
        _smartReplies = const [];
        _repliesFor = null;
        if (mounted) setState(() {});
      }
      return;
    }
    Map<String, dynamic>? last;
    for (final m in newestFirst) {
      if (m['deleted_at'] != null) continue;
      if ((m['type'] ?? 'text') != 'text') continue;
      last = m;
      break;
    }
    if (last == null || last['sender_id'] == _me) {
      if (_smartReplies.isNotEmpty || _repliesFor != null) {
        _smartReplies = const [];
        _repliesFor = null;
        if (mounted) setState(() {});
      }
      return;
    }
    final id = last['id'] as String;
    if (_repliesFor == id) return; // محسوبة من الرسالة نفسها
    final text = _textOf(last);
    if (text == null || E2eService.isEncrypted(text)) return; // لم يُفك بعد
    _repliesFor = id;
    final replies = LocalAiService.smartReplies(text);
    if (mounted) setState(() => _smartReplies = replies);
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
      backgroundColor: context.surfaceAlt,
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
    final once = m['view_once'] == true ? ' (عرض مرة واحدة)' : '';
    switch (m['type'] as String? ?? 'text') {
      case 'image':
        return '📷 صورة$once';
      case 'voice':
        return '🎤 رسالة صوتية';
      case 'video':
        return '🎬 فيديو$once';
      case 'file':
        return '📎 ${(_metaOf(m)?['name'] as String?) ?? 'ملف'}';
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
    final raw = _reactions[m['id']]?[_me];
    final mine = raw == null ? null : _emojiOf(raw);
    try {
      // الإزالة: نص فارغ. الإضافة: في المحادثات المشفرة يُشفَّر الإيموجي بمفتاح المحادثة
      String out = '';
      if (mine != emoji) {
        if (_e2e) {
          final key = await _convKey();
          if (key == null) {
            _snack('انتظر جاهزية مفاتيح التشفير ثم أعد المحاولة');
            return;
          }
          out = await E2eService.encryptText(key, widget.conversationId, emoji);
          _emojiPlain[out] = emoji; // عرض فوري وتبديل صحيح قبل وصول البث
        } else {
          out = emoji;
        }
      }
      await supabase.rpc('react_message', params: {'p_id': m['id'], 'p_emoji': out});
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

  /// ورقة إحصاءات القناة (المشرفون): المتابعون والإجمالي والمتوسط
  /// وآخر 30 منشوراً بعدّادات مشاهدتها
  Future<void> _showChannelStats() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await ChannelStatsService.stats(widget.conversationId);
    } catch (e) {
      _snack(e.toString().contains('admins only')
          ? 'إحصاءات القناة لمشرفيها فقط'
          : 'تعذّر تحميل الإحصاءات (تأكد من تشغيل ترحيل 025)');
      return;
    }
    if (!mounted || rows.isEmpty) return;
    final subs = (rows.first['subscribers'] as num?)?.toInt() ?? 0;
    final total = (rows.first['total_views'] as num?)?.toInt() ?? 0;
    final avg = (rows.first['avg_views'] as num?) ?? 0;
    final posts = rows.where((r) => r['post_id'] != null).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('إحصاءات ${widget.title}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _statTile(ctx, Icons.people_outline,
                      ChannelStatsService.formatCount(subs), 'متابع'),
                  _statTile(ctx, Icons.remove_red_eye_outlined,
                      ChannelStatsService.formatCount(total), 'إجمالي المشاهدات'),
                  _statTile(ctx, Icons.insights_outlined,
                      ChannelStatsService.formatCount(avg), 'متوسط المنشور'),
                ]),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: posts.isEmpty
                  ? Center(
                      child: Text('لا منشورات بعد',
                          style: TextStyle(color: ctx.textTertiary)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: posts.length,
                      itemBuilder: (_, i) {
                        final p = posts[i];
                        final v = (p['views'] as num?)?.toInt() ?? 0;
                        final type = p['post_type'] as String? ?? 'text';
                        var text = switch (type) {
                          'image' => '📷 صورة',
                          'voice' => '🎤 رسالة صوتية',
                          'video' => '🎬 فيديو',
                          'file' => '📎 ملف',
                          _ => (p['post_content'] as String?) ?? '',
                        };
                        if (text.length > 90) text = '${text.substring(0, 90)}…';
                        return ListTile(
                          dense: true,
                          title: Text(text,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(shortTime(p['post_created_at'] as String?),
                              style: TextStyle(
                                  color: ctx.textFaint, fontSize: 11)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.remove_red_eye_outlined,
                                size: 15, color: ctx.textTertiary),
                            const SizedBox(width: 4),
                            Text(ChannelStatsService.formatCount(v),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statTile(BuildContext ctx, IconData icon, String value, String label) =>
      Column(children: [
        Icon(icon, size: 20, color: WaslColors.teal),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label, style: TextStyle(fontSize: 11.5, color: ctx.textTertiary)),
      ]);

  Future<void> _forward(Map<String, dynamic> m) async {
    List<Map<String, dynamic>> chats;
    try {
      chats = List<Map<String, dynamic>>.from(await supabase.rpc('my_chats') as List)
          .where((c) => c['conversation_id'] != widget.conversationId)
          .toList();
      // هدف «رسائلي المحفوظة» أعلى القائمة دائماً (المرحلة 4)
      try {
        final savedId = await SavedService.id();
        if (savedId != widget.conversationId) {
          final last = await SavedService.lastMessage();
          chats = [
            {
              'conversation_id': savedId,
              'is_group': true,
              'title': SavedService.title,
              'avatar_url': null,
              'last_type': last?['type'],
            },
            ...chats,
          ];
        }
      } catch (_) {
        // بلا ترحيل 025: التوجيه للمحفوظة غير متاح والبقية تعمل
      }
    } catch (_) {
      _snack('تعذّر تحميل المحادثات');
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceAlt,
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
    } else {
      final bytes = await _mediaBytes(m['media_url'] as String);
      ok = bytes != null &&
          await ForwardService.send(
              target: target,
              type: type,
              bytes: bytes,
              text: (type == 'file' || type == 'video') ? _textOf(m) : null,
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
      _text.text = t;
      _text.selection = TextSelection.collapsed(offset: t.length);
    });
  }

  void _messageActions(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return;
    final isText = (m['type'] ?? 'text') == 'text';
    final isVoice = (m['type'] ?? '') == 'voice';
    final text = isText ? _textOf(m) : null;
    if (isText && text == null) {
      _snack('جارٍ فك التشفير… حاول بعد لحظة');
      return;
    }
    final arabic = text != null && RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    final mine = m['sender_id'] == _me;
    final myReaction = _emojiOf(_reactions[m['id']]?[_me] ?? '');
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceAlt,
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
                        color: myReaction == e ? context.glass : null,
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
          if (m['deleted_at'] == null)
            ListTile(
              leading: Icon(
                  _stars.contains(m['id']) ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: Colors.amber),
              title: Text(_stars.contains(m['id']) ? 'إزالة النجمة' : 'تمييز بنجمة'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleStar(m);
              },
            ),
          if (_e2e && !widget.isChannel && m['view_once'] != true)
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
          if (isVoice)
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded, color: WaslColors.teal),
              title: Text(_transcripts.containsKey(m['id'])
                  ? 'عرض التفريغ النصي'
                  : 'تفريغ نصي (تجريبي)'),
              subtitle: const Text('يُرسل الصوت بعد موافقتك الصريحة إلى Gemini'),
              onTap: () {
                Navigator.pop(ctx);
                _transcribeVoice(m);
              },
            ),
          if (isVoice && _transcripts[m['id']]?.isNotEmpty == true)
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: WaslColors.violet),
              title: const Text('ترجمة التفريغ'),
              onTap: () {
                Navigator.pop(ctx);
                final t = _transcripts[m['id']]!;
                final isAr = RegExp(r'[\u0600-\u06FF]').hasMatch(t);
                _showAiResult('ترجمة التفريغ', AiService.translate(t, isAr ? 'en' : 'ar'));
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
          if (!mine)
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
              title: const Text('الإبلاغ عن الرسالة',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                showReportDialog(context,
                    targetUser: m['sender_id'] as String?,
                    messageId: m['id'] as String?,
                    targetName: _senderName(m['sender_id'] as String?));
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
        color: mine ? Colors.black.withValues(alpha: 0.18) : context.glass,
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
            style: TextStyle(
                color: mine ? Colors.white70 : context.textSecondary, fontSize: 13)),
      ]),
    );
  }

  /// شارات التفاعلات تحت الفقاعة
  Widget? _reactionChips(Map<String, dynamic> m) {
    final r = _reactions[m['id']];
    if (r == null || r.isEmpty) return null;
    final counts = <String, int>{};
    for (final raw in r.values) {
      final e = _emojiOf(raw);
      if (e.isEmpty) continue; // لم يُفك بعد
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final mineEmoji = _emojiOf(r[_me] ?? '');
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
                    : context.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.hairline),
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
        color: context.glass,
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
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
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
  bool get _isPrivateGroup =>
      widget.isGroup && !widget.isChannel && widget.encrypted && !widget.isSaved;

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
    _loadMeta(); // اسم/صورة المجموعة قد تكون تغيّرت
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
          if (widget.isGroup && !widget.isChannel && (_groupAvatarPath ?? '').isNotEmpty)
            GroupAvatar(
              conversationId: widget.conversationId,
              path: _groupAvatarPath,
              name: _title,
              radius: 20,
            )
          else
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
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(_title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
                if (widget.isGroup && widget.officialVerified) ...[
                  const SizedBox(width: 4),
                  const VerifiedBadge(size: 15),
                ],
              ]),
              if (_statusLine() != null)
                Text(_statusLine()!,
                    style: TextStyle(
                        fontSize: 12,
                        color: _typing.isNotEmpty ? WaslColors.teal : context.textTertiary)),
            ]),
          ),
         ]),
        ),
        actions: [
          // غرفة الصوت الجماعية (0.18.0): للمجموعات الخاصة المشفّرة فقط —
          // لا قنوات ولا المحفوظة ولا المكالمات الفردية
          if (_isPrivateGroup)
            IconButton(
              tooltip: 'غرفة صوت',
              onPressed: _openVoiceRoom,
              icon: const Icon(Icons.spatial_audio_off_rounded),
            ),
          // أزرار المكالمة (0.17.0): المحادثات الخاصة الحقيقية فقط —
          // لا قنوات ولا مجموعات ولا بوتات (لا ترد المكالمة) ولا المحفوظة
          if (!widget.isGroup && widget.otherId != null && !widget.isBot) ...[
            IconButton(
              tooltip: 'مكالمة صوتية',
              onPressed: () => _startCall(CallKind.voice),
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              tooltip: 'مكالمة مرئية',
              onPressed: () => _startCall(CallKind.video),
              icon: const Icon(Icons.videocam_outlined),
            ),
          ],
          if (widget.isChannel && widget.canPost)
            IconButton(
              tooltip: 'إحصاءات القناة',
              onPressed: _showChannelStats,
              icon: const Icon(Icons.query_stats_rounded),
            ),
          // جرس القنوات (0.21.0): تفضيل الإشعار لهذه القناة حصراً
          if (widget.isChannel)
            IconButton(
              tooltip: 'إشعارات القناة: ${ChannelBellService.label(_bell)}',
              onPressed: _showBellDialog,
              icon: Icon(
                _bell == 'mute'
                    ? Icons.notifications_off_outlined
                    : _bell == 'pinned'
                        ? Icons.push_pin_outlined
                        : Icons.notifications_active_outlined,
                color: _bell == 'all'
                    ? null
                    : _bell == 'pinned'
                        ? WaslColors.teal
                        : context.textFaint,
              ),
            ),
          // القراءة الصوتية (0.21.0): TTS عربي على الجهاز حصراً
          IconButton(
            tooltip: _ttsBusy || VoiceReadService.speaking.value
                ? 'إيقاف القراءة'
                : 'اقرأ آخر الرسائل',
            onPressed: _toggleSpeak,
            icon: Icon(
              _ttsBusy || VoiceReadService.speaking.value
                  ? Icons.stop_circle_outlined
                  : Icons.volume_up_outlined,
              color: _ttsBusy || VoiceReadService.speaking.value
                  ? WaslColors.teal
                  : null,
            ),
          ),
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
              tooltip: _verified ? 'رمز الأمان — موثّق' : 'رمز الأمان',
              onPressed: _showSafetyNumber,
              icon: Icon(Icons.verified_user_outlined,
                  color: E2eService.peerKeyChanged(widget.otherId!)
                      ? Colors.amber
                      : _verified
                          ? const Color(0xFF2FBE63)
                          : WaslColors.teal),
            ),
          IconButton(
            tooltip: 'وصل AI للملخص',
            onPressed: _showAiMenu,
            icon: const Icon(Icons.auto_awesome, color: WaslColors.violet),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'disappear') _changeDisappearing();
              if (v == 'starred') setState(() => _starredOnly = !_starredOnly);
              if (v == 'screenshots') _toggleNoScreenshots();
              if (v == 'autotranslate') _toggleAutoTranslate();
              if (v == 'media') _openMediaGallery();
              if (v == 'export') _exportConversation();
              if (v == 'clear') _clearConversation();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'starred',
                child: Text(_starredOnly ? 'كل الرسائل' : 'الرسائل المميزة بنجمة'),
              ),
              const PopupMenuItem(
                value: 'media',
                child: Row(children: [
                  Icon(Icons.photo_library_outlined, size: 20, color: WaslColors.teal),
                  SizedBox(width: 12),
                  Text('معرض الوسائط'),
                ]),
              ),
              if (!widget.isChannel)
                PopupMenuItem(
                  value: 'disappear',
                  child: Text('الرسائل المختفية: ${disappearLabel(_disappear)}'),
                ),
              if (!widget.isChannel)
                PopupMenuItem(
                  value: 'autotranslate',
                  child: Row(children: [
                    Icon(
                      Icons.translate_rounded,
                      size: 20,
                      color: _autoTranslate ? WaslColors.teal : null,
                    ),
                    const SizedBox(width: 12),
                    Text(_autoTranslate ? 'إيقاف الترجمة الفورية' : 'الترجمة الفورية'),
                    if (_autoTranslate) ...[
                      const Spacer(),
                      const Icon(Icons.check_rounded,
                          size: 18, color: WaslColors.teal),
                    ],
                  ]),
                ),
              const PopupMenuItem(
                value: 'screenshots',
                child: Text('منع/السماح بلقطات الشاشة'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('تصدير المحادثة نصاً'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('مسح المحادثة عندي'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.isBot)
            Material(
              color: context.glass,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.smart_toy_outlined, size: 16, color: WaslColors.violet),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'محادثة مع بوت — غير مشفرة طرف-لطرف، والبوت يقرأها عبر واجهته',
                        style:
                            TextStyle(fontSize: 12, color: context.textTertiary)),
                  ),
                ]),
              ),
            ),
          if (_disappear != null || _starredOnly)
            Material(
              color: context.glass,
              child: InkWell(
                onTap: _starredOnly
                    ? () => setState(() => _starredOnly = false)
                    : _changeDisappearing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Icon(_starredOnly ? Icons.star_rounded : Icons.timer_outlined,
                        size: 18, color: _starredOnly ? Colors.amber : WaslColors.violet),
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
            // خلفية المحادثة المختارة (الإعدادات ← المظهر ← خلفية المحادثة)
            child: ValueListenableBuilder<int>(
              valueListenable: WallpaperService.index,
              builder: (context, _wp, _) => CustomPaint(
                painter: WallpaperPainter(WallpaperService.current,
                    dark: Theme.of(context).brightness == Brightness.dark),
                child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final now = DateTime.now();
                final all = snap.data!.reversed.where((m) {
                  final e = m['expires_at'] as String?;
                  if (e != null && !DateTime.parse(e).isAfter(now)) return false;
                  // المسح الشخصي (0.20.0): الرسائل قبله مخفية عني حصراً
                  final c = _clearedAt;
                  if (c != null) {
                    final t = DateTime.tryParse(m['created_at'] as String? ?? '');
                    if (t != null && !t.isAfter(c)) return false;
                  }
                  return true;
                }).toList();
                _byId = {for (final m in all) m['id'] as String: m};
                final q = _query;
                final base = _starredOnly
                    ? all.where((m) => _stars.contains(m['id'])).toList()
                    : all;
                if (_starredOnly && base.isEmpty) {
                  _scheduleDecrypt(all);
                  return Center(
                      child: Text('لا رسائل مميزة بنجمة هنا',
                          style: TextStyle(color: context.textTertiary)));
                }
                final msgs = q.isEmpty
                    ? base
                    : base.where((m) {
                        if (m['deleted_at'] != null || (m['type'] ?? 'text') != 'text') {
                          return false;
                        }
                        // البحث الذكي (المرحلة 5): تطبيع عربي + تسامح أخطاء + مرادفات
                        return SmartSearchService.matches(_textOf(m) ?? '', q);
                      }).toList();
                if (q.isNotEmpty && msgs.isEmpty) {
                  _scheduleDecrypt(all);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('لا نتائج', style: TextStyle(color: context.textTertiary)),
                        const SizedBox(height: 8),
                        Text(SmartSearchService.capabilityHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.textFaint, fontSize: 12)),
                      ]),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _maybeMarkRead(all));
                _trackChannelViews(all);
                _scheduleDecrypt(all);
                _scheduleTranslate(all);
                _refreshSmartReplies(all);
                unawaited(_ensureDailySummary(all));
                // الألبوم المتعدد (0.20.0): القطع المتتالية بمعرّف واحد فقاعة واحدة
                final items = AlbumService.group(msgs);
                _allMsgs = all;
                _maybeJumpToFocus(items);
                return ScrollablePositionedList.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemScrollController: _itemScroll,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item.length > 1) return _albumTile(item);
                    final m = item.first;
                    final mine = m['sender_id'] == _me;
                    final sender = _names[m['sender_id']];
                    final replyId = m['reply_to'] as String?;
                    final chips = _reactionChips(m);
                    // حركة الدخول مرة واحدة لكل رسالة (المرحلة 5)
                    final firstTime = _motionSeen.add(m['id'] as String);
                    Widget bubble = GestureDetector(
                       onLongPress: () => _messageActions(m),
                       child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          gradient: mine ? WaslColors.gradient : null,
                          color: mine ? null : context.bubbleOther,
                          borderRadius: BorderRadius.circular(20),
                          // الإبراز عند القفز (معرض الوسائط): إطار فاتح يذوب
                          border: _highlightId == m['id']
                              ? Border.all(color: Colors.tealAccent, width: 2.5)
                              : null,
                          boxShadow: _highlightId == m['id']
                              ? [BoxShadow(color: Colors.tealAccent.withValues(alpha: 0.35), blurRadius: 18)]
                              : null,
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
                            // الترجمة الفورية تحت الرسالة الواردة (المرحلة 5)
                            if (_autoTranslate &&
                                !mine &&
                                m['deleted_at'] == null &&
                                (m['type'] ?? 'text') == 'text')
                              _translationLine(m),
                            if (chips != null) chips,
                            const SizedBox(height: 2),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_stars.contains(m['id'])) ...[
                                const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                                const SizedBox(width: 3),
                              ],
                              if (widget.isChannel) ...[
                                Icon(Icons.remove_red_eye_outlined,
                                    size: 12,
                                    color: mine ? Colors.white60 : context.textTertiary),
                                const SizedBox(width: 3),
                                Text(ChannelStatsService.formatCount(_views[m['id']] ?? 0),
                                    style: TextStyle(
                                        color: mine ? Colors.white70 : context.textSecondary,
                                        fontSize: 11)),
                                const SizedBox(width: 4),
                              ],
                              if (m['expires_at'] != null) ...[
                                Icon(Icons.timer_outlined,
                                    size: 12,
                                    color: mine ? Colors.white60 : context.textTertiary),
                                const SizedBox(width: 3),
                              ],
                              if (m['edited_at'] != null && m['deleted_at'] == null) ...[
                                Text('معدّلة',
                                    style: TextStyle(
                                        color: mine ? Colors.white60 : context.textTertiary,
                                        fontSize: 11)),
                                const SizedBox(width: 4),
                              ],
                              Text(_time(m['created_at'] as String),
                                  style: TextStyle(
                                      color: mine ? Colors.white70 : context.textSecondary,
                                      fontSize: 11)),
                              if (mine) ...[const SizedBox(width: 4), _ticks(m)],
                            ]),
                          ],
                        ),
                      ),
                      );
                    if (firstTime) {
                      bubble = MotionBubble(child: bubble, mine: mine);
                    }
                    return Align(
                      alignment: mine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: bubble,
                    );
                  },
                );
              },
            ),
              ),
            ),
          ),
          if (_uploading) const LinearProgressIndicator(minHeight: 2),
          if (widget.canPost && _composeBanner() != null) _composeBanner()!,
          if (_iBlockedPeer)
            _blockedBanner()
          else if (_isMuted)
            _mutedBanner()
          else if (!widget.canPost)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.glass,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text('النشر هنا للمشرفين فقط',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textTertiary)),
              ),
            )
          else
          SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // الردود الذكية المحلية (المرحلة 5): شريحة ردود جاهزة على آخر رسالة وردت
              if (_smartReplies.isNotEmpty && !_recording)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: [
                      for (final r in _smartReplies)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: MotionScaleIn(
                            child: ActionChip(
                              avatar: const Icon(Icons.bolt_rounded,
                                  size: 15, color: WaslColors.teal),
                              label: Text(r,
                                  style: const TextStyle(
                                      fontSize: 12.5, fontWeight: FontWeight.w600)),
                              backgroundColor: context.glass,
                              side: BorderSide(color: context.hairline),
                              onPressed: () {
                                setState(() {
                                  _text.text = r;
                                  _text.selection = TextSelection.fromPosition(
                                      TextPosition(offset: r.length));
                                });
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
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
                            color: context.glass,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(children: [
                            const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 8),
                            Text('جارٍ التسجيل ${_recLabel()}'),
                            const Spacer(),
                            Text('اترك للإرسال', style: TextStyle(color: context.textFaint)),
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
            ]),
          ),
        ],
      ),
    );
  }
}
