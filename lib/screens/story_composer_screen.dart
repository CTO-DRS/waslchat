import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/story_service.dart';
import '../theme.dart';

/// خلفيات الحالة النصية (الاختيار يُخزَّن صريحاً كرمز bg — موثق في الشفافية)
const _textBackgrounds = <String, LinearGradient>{
  'indigo': LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
  'teal': LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF14B8A6)]),
  'violet': LinearGradient(colors: [Color(0xFF7E22CE), Color(0xFFC026D3)]),
  'sunset': LinearGradient(colors: [Color(0xFFB45309), Color(0xFFDC2626)]),
  'night': LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)]),
};

/// اختيار نوع الحالة من ورقة «حالتي +» — عام لتشاركه شاشة الشريط
enum StoryPick { gallery, camera, text }

/// منشئ الحالة: صورة (معرض/كاميرا) أو نص. الفيديو يُختار من المعرض.
/// النشر نفسه في StoryService.publish — التشفير يحدث محلياً قبل أي رفع.
class StoryComposerScreen extends StatefulWidget {
  const StoryComposerScreen({super.key, this.initialPick});

  /// اختيار مسبق من ورقة «حالتي +» (معرض/كاميرا/نص)
  final StoryPick? initialPick;

  @override
  State<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryComposerScreenState extends State<StoryComposerScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  final _focus = FocusNode();

  Uint8List? _bytes;
  String _kind = 'text'; // image | video | text
  String _bg = 'indigo';
  bool _busy = false;
  bool _picking = false;
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPick;
    if (p != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (p == StoryPick.text) {
          _focus.requestFocus();
        } else {
          _pick(p == StoryPick.camera ? ImageSource.camera : ImageSource.gallery,
              video: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _focus.dispose();
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    _video?.pause();
    _video?.dispose();
    _video = null;
  }

  Future<void> _pick(ImageSource source, {required bool video}) async {
    if (_picking || _busy) return;
    _picking = true;
    try {
      if (video) {
        final x = await _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 1));
        if (x == null) return;
        final b = await x.readAsBytes();
        if (b.length > StoryService.maxBytes) {
          _snack('الفيديو أكبر من 24 ميغابايت');
          return;
        }
        await _setMedia('video', b);
      } else {
        final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82);
        if (x == null) return;
        final b = await x.readAsBytes();
        await _setMedia('image', b);
      }
    } catch (_) {
      _snack('تعذّر اختيار الملف');
    } finally {
      _picking = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _setMedia(String kind, Uint8List bytes) async {
    _disposeVideo();
    if (kind == 'video') {
      try {
        // المعاينة تحتاج ملفاً على القرص — نكتبه في المجلد المؤقت (غير مشفر، محلي فقط)
        final dir = await getTempDir();
        final f = File('${dir.path}/story_preview_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await f.writeAsBytes(bytes);
        final c = VideoPlayerController.file(f);
        await c.initialize();
        await c.setLooping(true);
        await c.play();
        _video = c;
      } catch (_) {
        _snack('تعذّر تشغيل معاينة الفيديو');
      }
    }
    if (!mounted) return;
    setState(() {
      _kind = kind;
      _bytes = bytes;
    });
  }

  Future<void> _publish() async {
    if (_busy) return;
    if (_kind == 'text' && _caption.text.trim().isEmpty) {
      _snack('اكتب نص الحالة أولاً');
      return;
    }
    if (_kind != 'text' && _bytes == null) {
      _snack('اختر صورة أو فيديو أولاً');
      return;
    }
    setState(() => _busy = true);
    try {
      await StoryService.publish(
        type: _kind,
        bytes: _bytes,
        caption: _kind == 'text' ? _caption.text.trim() : (_caption.text.trim().isEmpty ? null : _caption.text.trim()),
        bg: _kind == 'text' ? _bg : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نُشرت حالتك — ستختفي بعد 24 ساعة')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.toString();
      _snack(msg.contains('24 ميغابايت') || msg.contains('طويل جداً') || msg.contains('النص مطلوب')
          ? msg.replaceFirst('Bad state: ', '')
          : 'تعذّر النشر — تحقق من الاتصال');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _kind == 'text' ? 'حالة نصية' : (_kind == 'video' ? 'حالة فيديو' : 'حالة صورة'),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'من المعرض',
            icon: const Icon(Icons.photo_outlined),
            onPressed: _busy ? null : () => _pick(ImageSource.gallery, video: false),
          ),
          IconButton(
            tooltip: 'كاميرا',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _busy ? null : () => _pick(ImageSource.camera, video: false),
          ),
          IconButton(
            tooltip: 'فيديو من المعرض',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: _busy ? null : () => _pick(ImageSource.gallery, video: true),
          ),
          IconButton(
            tooltip: 'نص',
            icon: const Icon(Icons.edit_note_outlined),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _disposeVideo();
                      _kind = 'text';
                      _bytes = null;
                    }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: WaslColors.teal,
        foregroundColor: Colors.white,
        onPressed: _busy ? null : _publish,
        icon: _busy
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_outlined),
        label: const Text('نشر'),
      ),
      body: _kind == 'text' ? _buildTextBody(context) : _buildMediaBody(context),
    );
  }

  // ---------- الحالة النصية ----------
  Widget _buildTextBody(BuildContext context) {
    final bg = _textBackgrounds[_bg] ?? _textBackgrounds['indigo']!;
    return Column(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(gradient: bg),
          child: Center(
            child: TextField(
              controller: _caption,
              focusNode: _focus,
              maxLines: null,
              maxLength: 280,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.6),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                hintText: 'اكتب حالتك…',
                hintStyle: TextStyle(color: Colors.white60),
              ),
            ),
          ),
        ),
      ),
      Container(
        height: 74,
        color: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final e in _textBackgrounds.entries)
              GestureDetector(
                onTap: () => setState(() => _bg = e.key),
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    gradient: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _bg == e.key ? Colors.white : Colors.white24,
                        width: _bg == e.key ? 3 : 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  // ---------- صورة / فيديو ----------
  Widget _buildMediaBody(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Center(
          child: _video != null
              ? AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: VideoPlayer(_video!))
              : (_kind == 'image' && _bytes != null)
                  ? InteractiveViewer(
                      maxScale: 4,
                      child: Image.memory(_bytes!, fit: BoxFit.contain))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            size: 64, color: Colors.white24),
                        const SizedBox(height: 12),
                        Text('اختر صورة أو فيديو من الأعلى',
                            style: const TextStyle(color: Color(0x80FFFFFF))),
                      ],
                    ),
        ),
      ),
      // تعليق اختياري للصورة/الفيديو
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: TextField(
            controller: _caption,
            maxLength: 280,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'أضف تعليقاً (اختياري)',
              hintStyle: const TextStyle(color: Color(0x61FFFFFF)),
              filled: true,
              fillColor: const Color(0x14FFFFFF),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
    ]);
  }
}
