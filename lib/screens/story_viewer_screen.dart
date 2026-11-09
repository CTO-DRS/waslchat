import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/story_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// عارض الحالات: شريط تقدم لكل حالة، نق يمين = السابقة ويسار = التالية
/// (في RTL: التالي باتجاه القراءة). لحالاتي: عدد المشاهدين وقائمة أسمائهم وحذف.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.stories, this.mine = false});
  final List<StoryItem> stories;
  final bool mine;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final List<StoryItem> _stories;
  int _index = 0;
  bool _dataReady = false;
  String? _error;
  String _caption = '';
  Uint8ListHolder? _media;
  VideoPlayerController? _video;
  Timer? _autoNext;

  /// مدة عرض الصورة/النص قبل الانتقال التلقائي (الفيديو بطوله الحقيقي)
  static const _autoAdvance = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _stories = List.of(widget.stories);
    _open(_index);
  }

  @override
  void dispose() {
    _autoNext?.cancel();
    _video?.dispose();
    super.dispose();
  }

  StoryItem get _current => _stories[_index];

  Future<void> _open(int i) async {
    if (i < 0 || i >= _stories.length) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _index = i;
      _dataReady = false;
      _error = null;
      _caption = '';
      _media = null;
    });
    _disposeVideo();
    final s = _current;

    // تسجيل المشاهدة فور الفتح (الخادم + محلياً للون الحلقة)
    if (!s.mine) {
      await StoryService.markViewed(s.id);
    }
    await StoryService.markSeenLocally(s.id);

    final cap = await StoryService.caption(s);
    if (!mounted || _index != i) return;
    setState(() => _caption = cap);

    if (s.type != 'text') {
      final bytes = await StoryService.loadMedia(s);
      if (!mounted || _index != i) return;
      if (bytes == null) {
        setState(() {
          _error = 'تعذّر فك هذه الحالة';
          _dataReady = true;
        });
        return;
      }
      if (s.type == 'video') {
        final ok = await _setupVideo(bytes, i);
        if (!mounted || _index != i) return;
        if (!ok) {
          setState(() {
            _error = 'تعذّر تشغيل الفيديو';
            _dataReady = true;
          });
        }
      } else {
        setState(() {
          _media = Uint8ListHolder(bytes);
          _dataReady = true;
        });
        _armAutoNext();
      }
    } else {
      setState(() => _dataReady = true);
      _armAutoNext();
    }
  }

  /// انتقال تلقائي للحالة التالية (صورة/نص) — يُلغى عند الخروج أو التنقل
  void _armAutoNext() {
    _autoNext?.cancel();
    _autoNext = Timer(_autoAdvance, () {
      if (mounted) _next();
    });
  }

  void _disposeVideo() {
    _autoNext?.cancel();
    _video?.pause();
    _video?.dispose();
    _video = null;
  }

  Future<bool> _setupVideo(Uint8ListHolder bytes, int pageIndex) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/story_${_current.id}.mp4');
      await f.writeAsBytes(bytes.data);
      final c = VideoPlayerController.file(f);
      await c.initialize();
      await c.play();
      if (!mounted) {
        await c.dispose();
        return false;
      }
      // انتهاء الفيديو = الانتقال تلقائياً
      c.addListener(() {
        if (mounted && _index == pageIndex && c.value.position >= c.value.duration) {
          _next();
        }
      });
      _video = c;
      setState(() => _dataReady = true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _next() => _open(_index + 1);
  void _prev() {
    _autoNext?.cancel();
    if (_index == 0) {
      Navigator.pop(context);
    } else {
      _open(_index - 1);
    }
  }

  Future<void> _deleteCurrent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: context.wasl.surface,
        title: const Text('حذف الحالة؟'),
        content: const Text('ستُحذف للجميع فوراً، وملفها من التخزين خلال ساعة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.wasl.danger),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await StoryService.delete(_current.id);
    if (!mounted) return;
    setState(() => _stories.removeAt(_index));
    if (_stories.isEmpty) {
      Navigator.pop(context, true);
    } else {
      _open(_index.clamp(0, _stories.length - 1).toInt());
    }
  }

  void _showViewers() async {
    final rows = await StoryService.viewers(_current.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.wasl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('شاهدها ${rows.length}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Text('لا مشاهدات بعد',
                  style: TextStyle(color: context.wasl.textFaint)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (_, i) => ListTile(
                  leading: UserAvatar(
                      name: (rows[i]['name'] ?? '') as String,
                      url: rows[i]['avatar_url'] as String?,
                      radius: 20),
                  title: Text((rows[i]['name'] ?? '') as String,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_ago(rows[i]['viewed_at'] as String?),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  static String _ago(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    final m = DateTime.now().difference(d).inMinutes;
    if (m < 1) return 'الآن';
    if (m < 60) return 'قبل $m د';
    return 'قبل ${(m / 60).round()} س';
  }

  String _agoCreated() {
    final m = DateTime.now().difference(_current.createdAt).inMinutes;
    if (m < 1) return 'الآن';
    if (m < 60) return 'قبل $m د';
    final h = (m / 60).round();
    if (h < 24) return 'قبل $h س';
    return 'قبل ${(h / 24).round()} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final s = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // المحتوى
        Positioned.fill(
          child: !_dataReady
              ? const Center(child: CircularProgressIndicator(color: Colors.white60))
              : _error != null
                  ? Center(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 52, color: Colors.white24),
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: const TextStyle(color: Colors.white54)),
                      ],
                    ))
                  : _buildStoryBody(s),
        ),
        // مناطق النقر: يمين = السابقة، يسار = التالية (محاكاة اتجاه القراءة RTL)
        Positioned.fill(
          child: Row(children: [
            Expanded(child: GestureDetector(onTap: _prev, behavior: HitTestBehavior.translucent)),
            Expanded(child: GestureDetector(onTap: _next, behavior: HitTestBehavior.translucent)),
          ]),
        ),
        // أشرطة التقدم
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(
                children: [
                  for (var i = 0; i < _stories.length; i++)
                    Expanded(
                      child: Container(
                        height: 2.6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _index
                              ? const Color(0xE6FFFFFF)
                              : const Color(0x40FFFFFF),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // الترويسة: الناشر والوقت + أدوات حالاتي
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                UserAvatar(
                    name: s.mine ? 'أنا' : s.authorName,
                    url: s.authorAvatar,
                    radius: 18,
                    color: s.mine ? WaslColors.teal : WaslColors.indigo),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.mine ? 'حالتي' : s.authorName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5)),
                      Text(_agoCreated(),
                          style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
                    ],
                  ),
                ),
                if (s.mine) ...[
                  IconButton(
                    tooltip: 'المشاهدون',
                    icon: const Icon(Icons.remove_red_eye_outlined, color: Colors.white),
                    onPressed: _showViewers,
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: _deleteCurrent,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
          ]),
        ),
        // التعليق أسفل الشاشة
        if (_caption.isNotEmpty)
          PositionedDirectional(
            bottom: 34,
            start: 18,
            end: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x73000000),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15.5, height: 1.6)),
            ),
          ),
        // شارة المتبقي (شفافية: 24 ساعة من الخادم)
        PositionedDirectional(
          bottom: 6,
          start: 0,
          end: 0,
          child: Center(
            child: Text('تختفي بعد ${_remainingText(s)}',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
          ),
        ),
      ]),
    );
  }

  static String _remainingText(StoryItem s) {
    final r = s.remaining;
    if (r.inHours >= 1) return '${r.inHours} س';
    if (r.inMinutes >= 1) return '${r.inMinutes} د';
    return 'أقل من دقيقة';
  }

  Widget _buildStoryBody(StoryItem s) {
    if (s.type == 'text') {
      final bg = _textBg(s.bg);
      return Container(
          decoration: BoxDecoration(gradient: bg),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Text(
            _caption.isEmpty ? '…' : _caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.7),
          ));
    }
    if (s.type == 'video' && _video != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio == 0 ? 1 : _video!.value.aspectRatio,
          child: VideoPlayer(_video!),
        ),
      );
    }
    if (s.type == 'image' && _media != null) {
      return InteractiveViewer(
        maxScale: 4,
        child: Center(child: Image.memory(_media!.data, fit: BoxFit.contain)),
      );
    }
    return const SizedBox.shrink();
  }

  static LinearGradient _textBg(String? key) {
    switch (key) {
      case 'teal':
        return const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF14B8A6)]);
      case 'violet':
        return const LinearGradient(colors: [Color(0xFF7E22CE), Color(0xFFC026D3)]);
      case 'sunset':
        return const LinearGradient(colors: [Color(0xFFB45309), Color(0xFFDC2626)]);
      case 'night':
        return const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)]);
      case 'indigo':
      default:
        return const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]);
    }
  }
}

/// غلاف بسيط لبايتات الوسيط المفكوكة
class Uint8ListHolder {
  Uint8ListHolder(this.data);
  final Uint8List data;
}
