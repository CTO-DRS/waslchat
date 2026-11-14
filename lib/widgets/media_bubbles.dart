import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../services/webio/web_files.dart';
import '../theme.dart';

/// تُحمّل بايتات الوسيط (بعد فك التشفير إن كان مشفّراً)
typedef MediaLoader = Future<Uint8List?> Function();

/// بطاقة وسيط «تُعرض مرة واحدة»: قبل الفتح (اضغط للعرض) وبعده (انتهى)،
/// وللمرسل (لم يُعرض بعد / تم العرض).
class ViewOnceCard extends StatelessWidget {
  const ViewOnceCard({
    super.key,
    required this.mine,
    required this.viewed,
    this.mediaType = 'image',
    this.onTap,
  });

  final bool mine;
  final bool viewed;

  /// 'image' أو 'video'
  final String mediaType;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = !viewed && onTap != null;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        width: 220,
        height: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: viewed
                ? [context.hairline, context.hairline.withValues(alpha: 0.4)]
                : const [Color(0xFF2A2D3A), Color(0xFF15161F)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: viewed ? context.hairline : Colors.white24,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: viewed
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.10),
                border: viewed ? Border.all(color: context.textFaint) : null,
              ),
              child: Icon(
                viewed
                    ? Icons.visibility_off_rounded
                    : (mediaType == 'video'
                        ? Icons.play_circle_fill_rounded
                        : Icons.photo_rounded),
                size: 22,
                color: viewed ? context.textFaint : Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              viewed
                  ? (mine ? 'انتهى — يُعرض مرة واحدة' : 'انتهى هذا الوسيط')
                  : (mine ? 'وسيط للعرض مرة واحدة' : 'اضغط للعرض مرة واحدة'),
              style: TextStyle(
                color: viewed ? context.textSecondary : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!viewed) ...[
              const SizedBox(height: 4),
              Text(
                mine ? (active ? 'اضغط لعرض نسختك' : 'لم يُعرض بعد') : 'لا يُحفظ ولا يُلتقط',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ] else if (mine) ...[
              const SizedBox(height: 4),
              Text('تم العرض', style: TextStyle(color: context.textFaint, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

/// عارض الصورة «مرة واحدة»: بلا حفظ أو مشاركة، وخلفية سوداء.
/// منع لقطات الشاشة يُطبَّق من الشاشة المستدعية (FLAG_SECURE) قبل فتحه.
class ViewOnceImageScreen extends StatelessWidget {
  const ViewOnceImageScreen({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white54,
        title: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.looks_one_rounded, size: 18),
          SizedBox(width: 6),
          Text('عرض مرة واحدة', style: TextStyle(fontSize: 14)),
        ]),
      ),
      body: Center(
          child: InteractiveViewer(
              maxScale: 4, child: Image.memory(bytes, fit: BoxFit.contain))),
    );
  }
}

/// فقاعة صورة: تُحمّل مرة واحدة، والضغط يفتحها بملء الشاشة
class ImageBubble extends StatefulWidget {
  const ImageBubble({super.key, required this.loader, this.width = 220});
  final MediaLoader loader;

  /// العرض المطلوب (يتغير في شبكة الألبوم — 0.20.0)
  final double width;

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
          return SizedBox(
            width: widget.width,
            height: widget.width,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            width: widget.width,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.hairline,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('🔒 تعذّر فك تشفير الصورة',
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _FullImage(bytes: bytes)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(bytes, width: widget.width, fit: BoxFit.cover),
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
        final bytes = await widget.loader();
        if (bytes == null) throw Exception('no bytes');
        if (kIsWeb) {
          final webm = bytes.length > 4 &&
              bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3;
          await _player.setUrl(webBlobUrl(bytes, webm ? 'audio/webm' : 'audio/mp4'));
        } else {
          final dir = await getTemporaryDirectory();
          final f = File(
              '${dir.path}/voice_enc_${DateTime.now().millisecondsSinceEpoch}.m4a');
          await f.writeAsBytes(bytes, flush: true);
          await _player.setFilePath(f.path);
        }
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
