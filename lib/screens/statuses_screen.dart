import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/status_service.dart';
import '../services/webio/web_files.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// الحالات/القصص المشفّرة: شريط الحلقات في أعلى المحادثات + العارض الكامل + النشر
///
/// - الشريط: «حالتي» أولاً ثم أصحاب الحالات (حلقة متدرجة = بادج غير مقروء).
/// - العارض: صفحة كاملة بشرائط تقدم، تنقّل بالنقر يميناً/يساراً وتقدّم تلقائي،
///   تسجيل المشاهدة، قائمة المشاهدين وحذف الحالة لصاحبها.
/// - كل المحتوى يُفكّ على الجهاز فقط (StatusService)؛ 🔒 عند تعذر الفك.

/// شريط الحلقات الأفقي (يوضع أعلى قائمة المحادثات)
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.groups,
    required this.onTapMe,
    required this.onTapAuthor,
  });

  final List<Map<String, dynamic>> groups;
  final VoidCallback onTapMe;
  final ValueChanged<int> onTapAuthor; // فهرس المجموعة

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          final isMe = g['is_me'] == true;
          final count = (g['statuses'] as List).length;
          final seen = g['all_viewed'] == true;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: isMe ? onTapMe : () => onTapAuthor(i),
              child: SizedBox(
                width: 72,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: (isMe || !seen) ? WaslColors.gradient : null,
                        color: seen && !isMe ? context.hairline : null,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).scaffoldBackgroundColor,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(
                              name: (g['author_name'] ?? '') as String,
                              url: g['author_avatar'] as String?,
                              radius: 24,
                              color: isMe ? WaslColors.indigo : WaslColors.teal,
                            ),
                            if (isMe && count == 0)
                              PositionedDirectional(
                                bottom: -2,
                                end: -2,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: WaslColors.teal,
                                  ),
                                  child: const Icon(Icons.add,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isMe ? 'حالتي' : (g['author_name'] ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isMe || !seen ? FontWeight.w700 : FontWeight.w400,
                        color: isMe || !seen ? null : context.textFaint,
                      ),
                    ),
                    if (!isMe && count > 1)
                      Text('$count حالات',
                          style: TextStyle(fontSize: 9, color: context.textFaint)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ورقة نشر حالة (نص أو صورة أو فيديو — أو رد بحالة على حالة أخرى)
Future<void> showStatusComposer(BuildContext context,
    {String? replyTo, String? replyAuthor}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surfaceAlt,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _StatusComposer(replyTo: replyTo, replyAuthor: replyAuthor),
  );
}

class _StatusComposer extends StatefulWidget {
  const _StatusComposer({this.replyTo, this.replyAuthor});
  final String? replyTo;
  final String? replyAuthor;

  @override
  State<_StatusComposer> createState() => _StatusComposerState();
}

class _StatusComposerState extends State<_StatusComposer> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _image;
  // فيديو الحالة (0.27.0): بايتات ومدة مقاسة وقيمة قابلة للإزالة
  Uint8List? _videoBytes;
  int? _videoSeconds;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _image = bytes;
      _videoBytes = null;
      _videoSeconds = null;
      _error = null;
    });
  }

  /// اختيار فيديو حالة (0.27.0): البايتات حارس صارم والمدة تُقاس محلياً
  /// بالمشغّل نفسه — قياس مفقود لا يمنع النشر ولا يُخمَّن (حد البايتات يحمي).
  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: StatusService.maxVideoSeconds));
    if (x == null) return;
    final bytes = await x.readAsBytes();
    var err = StatusService.validateVideo(bytes: bytes.length);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    // قياس المدة محلياً: ملف مؤقت على الجوال أو رابط blob على الويب
    String? blobUrl;
    try {
      VideoPlayerController c;
      if (kIsWeb) {
        blobUrl = webBlobUrl(bytes, 'video/mp4');
        c = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } else {
        c = VideoPlayerController.file(File(x.path));
      }
      await c.initialize();
      final secs = c.value.duration.inSeconds;
      await c.dispose();
      err = StatusService.validateVideo(
          bytes: bytes.length, durationSeconds: secs);
      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      setState(() {
        _videoBytes = bytes;
        _videoSeconds = secs;
        _image = null;
      });
    } catch (_) {
      if (!mounted) return;
      // تعذر القياس — نقبل النشر بحد البايتات ونعلن ذلك بصدق
      setState(() {
        _videoBytes = bytes;
        _videoSeconds = null;
        _image = null;
        _error = 'لم نتمكن من قياس مدة الفيديو — الحد المطبق 12 م.ب حصراً';
      });
    } finally {
      if (blobUrl != null) webRevoke(blobUrl);
    }
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_videoBytes != null) {
        await StatusService.publishVideo(_videoBytes!,
            durationSeconds: _videoSeconds, replyTo: widget.replyTo);
      } else if (_image != null) {
        await StatusService.publishImage(_image!, replyTo: widget.replyTo);
      } else {
        await StatusService.publishText(_controller.text,
            replyTo: widget.replyTo);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is Exception && e.toString().contains('bad status')
              ? 'تعذّر نشر الحالة — تحقق من المحتوى'
              : 'تعذّر نشر الحالة — تأكد من الاتصال وحاول مجدداً';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(widget.replyTo != null ? 'رد بحالة' : 'حالة جديدة',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: 'صورة من المعرض',
                icon: const Icon(Icons.image_outlined, color: WaslColors.teal),
                onPressed: _busy ? null : _pickImage,
              ),
              // فيديو الحالة (0.27.0): حتى 15 ثانية و12 م.ب — الحدود معلنة هنا
              IconButton(
                tooltip: 'فيديو من المعرض (حتى 15 ثانية)',
                icon: const Icon(Icons.videocam_outlined, color: WaslColors.teal),
                onPressed: _busy ? null : _pickVideo,
              ),
              if (_image != null)
                IconButton(
                  tooltip: 'إزالة الصورة',
                  icon: Icon(Icons.close, color: context.textFaint),
                  onPressed: _busy ? null : () => setState(() => _image = null),
                ),
              if (_videoBytes != null)
                IconButton(
                  tooltip: 'إزالة الفيديو',
                  icon: Icon(Icons.close, color: context.textFaint),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _videoBytes = null;
                            _videoSeconds = null;
                          }),
                ),
            ]),
            if (widget.replyTo != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: WaslColors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    StatusService.replyHeaderText(widget.replyAuthor),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: WaslColors.teal),
                  ),
                ),
              ),
            ],
            if (_videoBytes != null)
              // معاينة صادقة: صندوق فيديو بمدته المقاسة إن وُجدت
              Container(
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.movie_outlined,
                        color: Colors.white54, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      _videoSeconds != null
                          ? '${_videoSeconds} ث · ${(_videoBytes!.length / 1024 / 1024).toStringAsFixed(1)} م.ب'
                          : '${(_videoBytes!.length / 1024 / 1024).toStringAsFixed(1)} م.ب · المدة غير مقاسة',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ]),
                ),
              )
            else if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Image.memory(_image!, fit: BoxFit.cover),
                ),
              )
            else
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                maxLength: StatusService.maxTextChars,
                decoration:
                    const InputDecoration(hintText: 'بماذا تفكر اليوم؟'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: WaslColors.indigo),
              onPressed: _busy ||
                      (_image == null &&
                          _videoBytes == null &&
                          _controller.text.trim().isEmpty)
                  ? null
                  : _publish,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
              label: Text(widget.replyTo != null ? 'نشر الرد' : 'نشر الحالة'),
            ),
            const SizedBox(height: 6),
            Text(
                'مشفّرة بين الطرفين — تظهر لشركاء محادثاتك الفردية 24 ساعة'
                '${widget.replyTo != null ? ' · الرد حيّة ما دامت حالتك حية' : ''}'
                ' · فيديو حتى 15 ثانية و12 م.ب',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.textFaint)),
          ],
        ),
      ),
    );
  }
}

/// العارض الكامل: مجموعة (قائمة الحالات) تبدأ من فهرس معين
Future<bool> openStatusViewer(
    BuildContext context, List<Map<String, dynamic>> groups, int initialIndex) async {
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => StatusViewerScreen(groups: groups, initial: initialIndex)),
  );
  return r == true;
}

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({super.key, required this.groups, required this.initial});

  final List<Map<String, dynamic>> groups;
  final int initial;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late final List<_FlatStatus> _flat;
  late final PageController _page;
  int _i = 0;
  bool _changed = false;
  Timer? _timer;

  /// تقدم فيديو الحالة الحالي 0..1 — يدفعه المشغّل نفسه (0.27.0)
  final _videoProgress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _flat = [
      for (var g = 0; g < widget.groups.length; g++)
        for (var s = 0; s < (widget.groups[g]['statuses'] as List).length; s++)
          _FlatStatus(group: g, index: s),
    ];
    _i = _flat.indexWhere((f) => f.group == widget.initial);
    if (_i < 0) _i = 0;
    _page = PageController(initialPage: _i);
    _onShown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoProgress.dispose();
    _page.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _group => widget.groups[_flat[_i].group];
  Map<String, dynamic> get _status =>
      (_group['statuses'] as List)[_flat[_i].index] as Map<String, dynamic>;
  bool get _isMine => _group['is_me'] == true;

  /// عند عرض حالة غيري غير المشهودة: تسجيل مشاهدة + تحديث محلي.
  /// فيديو الحالة (0.27.0) بلا مؤقت ثابت — مشغّله هو من ينادي التالي
  /// عند اكتماله، والتقدم يقرأ من مشغّله حصراً لا تخمين.
  void _onShown() {
    _timer?.cancel();
    _videoProgress.value = 0;
    if (_status['kind'] != 'video') {
      _timer = Timer(_status['kind'] == 'image' ? _imgDur : _txtDur, _next);
    }
    if (!_isMine && _status['viewed'] != true) {
      final sid = _status['status_id'] as String;
      _status['viewed'] = true;
      StatusService.markViewed(sid);
      final g = _group;
      g['all_viewed'] = (g['statuses'] as List).every((s) => s['viewed'] == true);
      _changed = true;
    }
  }

  static const _txtDur = Duration(seconds: 6);
  static const _imgDur = Duration(seconds: 8);

  void _go(int i) {
    if (i < 0 || i >= _flat.length) {
      Navigator.pop(context, _changed);
      return;
    }
    setState(() {
      _i = i;
      _page.jumpToPage(i);
    });
    _onShown();
  }

  void _next() => _go(_i + 1);
  void _prev() => _go(_i - 1);

  Future<void> _deleteMine() async {
    final sid = _status['status_id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceAlt,
        title: const Text('حذف الحالة؟'),
        content: const Text('ستُحذف من جميع من يشاهدها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StatusService.delete(sid);
      _changed = true;
      if (!mounted) return;
      setState(() => widget.groups[_flat[_i].group]['statuses'].removeAt(_flat[_i].index));
      final sts = widget.groups[_flat[_i].group]['statuses'] as List;
      if (sts.isEmpty) {
        if (widget.groups.length == 1) {
          Navigator.pop(context, true);
        } else {
          setState(() => widget.groups.removeAt(_flat[_i].group));
          _rebuildFlat();
        }
      } else {
        _rebuildFlat();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر الحذف')));
      }
    }
  }

  void _rebuildFlat() {
    final newFlat = [
      for (var g = 0; g < widget.groups.length; g++)
        for (var s = 0; s < (widget.groups[g]['statuses'] as List).length; s++)
          _FlatStatus(group: g, index: s),
    ];
    if (newFlat.isEmpty) {
      Navigator.pop(context, true);
      return;
    }
    final g = _flat[_i].group.clamp(0, widget.groups.length - 1);
    final s = _flat[_i].index;
    var target = newFlat.indexWhere((f) => f.group == g && f.index == s);
    if (target < 0) target = newFlat.indexWhere((f) => f.group == g);
    if (target < 0) target = 0;
    setState(() {
      _flat
        ..clear()
        ..addAll(newFlat);
      _i = target;
      _page.jumpToPage(target);
    });
    _onShown();
  }

  void _showViewers() {
    final sid = _status['status_id'] as String;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: StatusService.viewers(sid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()));
          }
          final rows = snap.data ?? [];
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('شاهدها ${rows.length} ${rows.length == 1 ? 'شخص' : 'أشخاص'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('لا مشاهدات بعد',
                      style: TextStyle(color: context.textFaint)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final p = rows[i]['profiles'] as Map<String, dynamic>?;
                      final name =
                          (p?['display_name'] ?? p?['username'] ?? 'مستخدم') as String;
                      return ListTile(
                        leading: UserAvatar(
                            name: name,
                            url: p?['avatar_url'] as String?,
                            radius: 18,
                            color: WaslColors.indigo),
                        title: Text(name),
                        trailing: Text(StatusService.ageText(rows[i]['viewed_at'] as String),
                            style: TextStyle(color: context.textFaint, fontSize: 12)),
                      );
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) => _timer?.cancel(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _page,
          itemCount: _flat.length,
          onPageChanged: (i) {
            setState(() => _i = i);
            _onShown();
          },
          itemBuilder: (context, i) {
            final g = widget.groups[_flat[i].group];
            final s = (g['statuses'] as List)[_flat[i].index] as Map<String, dynamic>;
            final sts = g['statuses'] as List;
            final posInGroup = _flat[i].index;
            return Column(children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(children: [
                    // شرائط التقدم: قطاع لكل حالة من حالات هذا الصاحب
                    Expanded(
                      child: Row(
                        children: [
                          for (var j = 0; j < sts.length; j++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: j == posInGroup && s['kind'] == 'video'
                                    ? ValueListenableBuilder<double>(
                                        valueListenable: _videoProgress,
                                        builder: (context, p, __) =>
                                            LinearProgressIndicator(
                                          value: p.clamp(0.0, 1.0),
                                          minHeight: 3,
                                          backgroundColor: Colors.white24,
                                          valueColor: const AlwaysStoppedAnimation(
                                              Colors.white),
                                        ),
                                      )
                                    : LinearProgressIndicator(
                                        value: j < posInGroup
                                            ? 1
                                            : (j == posInGroup ? 0.35 : 0),
                                        minHeight: 3,
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            const AlwaysStoppedAnimation(Colors.white),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(children: [
                    UserAvatar(
                      name: (g['author_name'] ?? '') as String,
                      url: g['author_avatar'] as String?,
                      radius: 18,
                      color: _isMine ? WaslColors.indigo : WaslColors.teal,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((g['author_name'] ?? '') as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700)),
                          if (s['reply_to'] != null)
                            Text(
                                StatusService.replyHeaderText(
                                    StatusService.replyAuthorName(
                                        s['reply_to'] as String?, widget.groups)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF5EEAD4), fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                          Text(StatusService.ageText(s['created_at'] as String),
                              style:
                                  const TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context, _changed)),
                  ]),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    // RTL: التالي يساراً والسابق يميناً
                    final isRtl = Directionality.of(context) == TextDirection.rtl;
                    final w = context.size?.width ?? MediaQuery.of(context).size.width;
                    final leftHalf = d.localPosition.dx < w / 2;
                    if (isRtl) {
                      if (leftHalf) {
                        _next();
                      } else {
                        _prev();
                      }
                    } else {
                      if (leftHalf) {
                        _prev();
                      } else {
                        _next();
                      }
                    }
                  },
                  child: Center(child: _body(s)),
                ),
              ),
              if (_isMine)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      FilledButton.tonalIcon(
                        onPressed: _showViewers,
                        icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                        label: Text('${s['views_count'] ?? 0} مشاهدة'),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'حذف الحالة',
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.white12),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: _deleteMine,
                      ),
                    ]),
                  ),
                )
              else
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(children: [
                      // الرد بحالة (0.27.0): تنشر حالتك مشفرة بمرجع لأصلها —
                      // والمرجع يفرضه الخادم حياً وشريكاً بلا حظر عبر RLS
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white),
                        onPressed: () => showStatusComposer(
                          context,
                          replyTo: s['status_id'] as String,
                          replyAuthor: (g['author_name'] ?? '') as String,
                        ),
                        icon: const Icon(Icons.reply_rounded, size: 18),
                        label: const Text('رد بحالة'),
                      ),
                      const Spacer(),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> s) {
    if (s['kind'] == 'video') {
      return FutureBuilder<Uint8List?>(
        future: StatusService.decryptMedia(s),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 10),
              Text('جارٍ فك التشفير…', style: TextStyle(color: Colors.white54)),
            ]);
          }
          final bytes = snap.data;
          if (bytes == null) return _locked();
          return _StatusVideoBody(
            bytes: bytes,
            progress: _videoProgress,
            onEnded: _next,
          );
        },
      );
    }
    if (s['kind'] == 'image') {
      return FutureBuilder<Uint8List?>(
        future: StatusService.decryptMedia(s),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 10),
              Text('جارٍ فك التشفير…', style: TextStyle(color: Colors.white54)),
            ]);
          }
          final bytes = snap.data;
          if (bytes == null) {
            return _locked();
          }
          return InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          );
        },
      );
    }
    return FutureBuilder<String?>(
      future: StatusService.decryptText(s),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator(color: Colors.white);
        }
        final text = snap.data;
        if (text == null) return _locked();
        if (text.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: WaslColors.gradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, height: 1.7, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  Widget _locked() => const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, color: Colors.white38, size: 44),
        SizedBox(height: 12),
        Text('تعذّر فك تشفير هذه الحالة على هذا الجهاز',
            style: TextStyle(color: Colors.white38)),
      ]);
}

/// مشغّل فيديو الحالة (0.27.0): بايتات مفكوكة تُكتب ملفاً مؤقتاً على الجوال
/// أو رابط blob على الويب — يعمل مع بدء الحالة، ويشغّل التالية عند اكتماله،
/// والتقدم يقرأ من مشغّله حصراً. الملف المؤقت يُحذف عند الخروج.
class _StatusVideoBody extends StatefulWidget {
  const _StatusVideoBody({
    required this.bytes,
    required this.progress,
    required this.onEnded,
  });
  final Uint8List bytes;
  final ValueNotifier<double> progress;
  final VoidCallback onEnded;

  @override
  State<_StatusVideoBody> createState() => _StatusVideoBodyState();
}

class _StatusVideoBodyState extends State<_StatusVideoBody> {
  VideoPlayerController? _c;
  File? _tmp;
  String? _blobUrl;
  bool _ready = false;
  bool _failed = false;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (kIsWeb) {
        _blobUrl = webBlobUrl(widget.bytes, 'video/mp4');
        _c = VideoPlayerController.networkUrl(Uri.parse(_blobUrl!));
      } else {
        final dir = Directory('${(await getTemporaryDirectory()).path}/wasl_status');
        await dir.create(recursive: true);
        _tmp = File(
            '${dir.path}/st_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await _tmp!.writeAsBytes(widget.bytes, flush: true);
        _c = VideoPlayerController.file(_tmp!);
      }
      await _c!.initialize();
      _c!.addListener(_onTick);
      if (!mounted) return;
      setState(() => _ready = true);
      await _c!.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    final c = _c!;
    final dur = c.value.duration.inMilliseconds;
    if (dur > 0) {
      widget.progress.value = c.value.position.inMilliseconds / dur;
    }
    if (c.value.isCompleted && !_ended) {
      _ended = true;
      widget.onEnded();
    }
  }

  @override
  void dispose() {
    try {
      _c?.removeListener(_onTick);
    } catch (_) {}
    _c?.dispose();
    _tmp?.delete().ignore();
    if (_blobUrl != null) webRevoke(_blobUrl!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Text('تعذّر تشغيل فيديو هذه الحالة على هذا الجهاز',
          style: TextStyle(color: Colors.white54));
    }
    if (!_ready) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final c = _c!;
    return GestureDetector(
      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: Stack(alignment: Alignment.center, children: [
          VideoPlayer(c),
          if (!c.value.isPlaying && !c.value.isCompleted)
            const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
        ]),
      ),
    );
  }
}

class _FlatStatus {
  _FlatStatus({required this.group, required this.index});
  final int group;
  final int index;
}
