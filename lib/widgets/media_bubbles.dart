import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// تُحمّل بايتات الوسيط (بعد فك التشفير إن كان مشفّراً)
typedef MediaLoader = Future<Uint8List?> Function();

/// فقاعة صورة: تُحمّل مرة واحدة، والضغط يفتحها بملء الشاشة
class ImageBubble extends StatefulWidget {
  const ImageBubble({super.key, required this.loader});
  final MediaLoader loader;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  late final Future<Uint8List?> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            width: 220,
            height: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            width: 220,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.wasl.glass,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('🔒 تعذّر فك تشفير الصورة',
                style: TextStyle(
                    color: context.wasl.textSecondary, fontSize: 13)),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _FullImage(bytes: bytes)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(bytes, width: 220, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
          child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))),
    );
  }
}

/// فقاعة ملصق (0.4.9): بلا خلفية فقاعة — الصورة الشفافة نفسها.
/// GIF/webp المتحركة تعمل تلقائياً عبر Image.memory. تعذّر فك meta
/// أو التحميل = نص بديل صادق.
class StickerBubble extends StatefulWidget {
  const StickerBubble({super.key, required this.loader});
  final MediaLoader loader;

  @override
  State<StickerBubble> createState() => _StickerBubbleState();
}

class _StickerBubbleState extends State<StickerBubble> {
  late final Future<Uint8List?> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            width: 140,
            height: 140,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Text('🩹 ملصق',
              style: TextStyle(
                  color: context.wasl.textSecondary, fontSize: 15));
        }
        return Image.memory(
          bytes,
          width: 140,
          height: 140,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Text('🩹 ملصق',
              style: TextStyle(
                  color: context.wasl.textSecondary, fontSize: 15)),
        );
      },
    );
  }
}

/// فقاعة رسالة صوتية: تشغيل/إيقاف وشريط تقدم ومدة
/// (يُفكّ تشفير الملف ويُكتب مؤقتاً ثم يُشغّل محلياً)
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.loader, this.durationMs});
  final MediaLoader loader;
  final int? durationMs;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  bool _ready = false;
  File? _file; // النسخة المفكوكة التشفير على القرص — تُحذف عند مغادرة الشاشة

  @override
  void dispose() {
    _player.dispose();
    try {
      _file?.deleteSync();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_player.playing && _player.processingState != ProcessingState.completed) {
        await _player.pause();
        return;
      }
      if (!_ready) {
        final bytes = await widget.loader();
        if (bytes == null) throw Exception('no bytes');
        final dir = await getTemporaryDirectory();
        final f =
            File('${dir.path}/voice_plain_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await f.writeAsBytes(bytes, flush: true);
        _file = f;
        await _player.setFilePath(f.path);
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
                  color: context.wasl.textPrimary, size: 30),
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
                          backgroundColor: context.wasl.border,
                          color: context.wasl.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_fmt(playing ? pos : total),
                          style: TextStyle(
                              color: context.wasl.textSecondary, fontSize: 11)),
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
