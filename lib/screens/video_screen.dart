import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/webio/web_files.dart';

/// تشغيل فيديو مفكوك التشفير من ملف مؤقت على الجهاز
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, this.file, this.url});
  final File? file;

  /// على الويب: رابط blob مؤقت
  final String? url;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _c = widget.url != null
      ? VideoPlayerController.networkUrl(Uri.parse(widget.url!))
      : VideoPlayerController.file(widget.file!);
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    // الملف المؤقت مفكوك التشفير: نحذفه عند الخروج
    widget.file?.delete().ignore();
    if (widget.url != null) webRevoke(widget.url!);
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: _failed
            ? const Text('تعذّر تشغيل الفيديو', style: TextStyle(color: Colors.white70))
            : !_ready
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                    child: AspectRatio(
                      aspectRatio: _c.value.aspectRatio,
                      child: Stack(alignment: Alignment.center, children: [
                        VideoPlayer(_c),
                        if (!_c.value.isPlaying)
                          const Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
                      ]),
                    ),
                  ),
      ),
      bottomNavigationBar: _ready
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(children: [
                  Text(_fmt(_c.value.position), style: const TextStyle(color: Colors.white70)),
                  Expanded(
                    child: VideoProgressIndicator(_c,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                  Text(_fmt(_c.value.duration), style: const TextStyle(color: Colors.white70)),
                ]),
              ),
            )
          : null,
    );
  }
}
