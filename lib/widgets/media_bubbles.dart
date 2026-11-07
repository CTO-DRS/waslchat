import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/media_service.dart';

/// فقاعة صورة: تُحمَّل برابط آمن، والضغط يفتحها بملء الشاشة
class ImageBubble extends StatelessWidget {
  const ImageBubble({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: MediaService.signedUrl(path),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            width: 220,
            height: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final url = snap.data!;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _FullImage(url: url)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(url, width: 220, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(child: InteractiveViewer(child: Image.network(url))),
    );
  }
}

/// فقاعة رسالة صوتية: تشغيل/إيقاف وشريط تقدم ومدة
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.path, this.durationMs});
  final String path;
  final int? durationMs;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  bool _ready = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_player.playing && _player.processingState != ProcessingState.completed) {
        await _player.pause();
        return;
      }
      if (!_ready) {
        await _player.setUrl(await MediaService.signedUrl(widget.path));
        _ready = true;
      }
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      _player.play(); // لا ننتظرها: تكتمل عند انتهاء التشغيل
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر تشغيل الرسالة الصوتية')));
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, s) {
        final playing = (s.data?.playing ?? false) &&
            s.data?.processingState != ProcessingState.completed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _toggle,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 30),
            ),
            SizedBox(
              width: 140,
              child: StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, p) {
                  final total =
                      _player.duration ?? Duration(milliseconds: widget.durationMs ?? 0);
                  final pos = p.data ?? Duration.zero;
                  final value = total.inMilliseconds == 0
                      ? 0.0
                      : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_fmt(playing ? pos : total),
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
