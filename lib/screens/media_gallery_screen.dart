import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../services/media_gallery_service.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'chat_screen.dart';

/// صورة خلية شبكة: تنزيل وفك مرة واحدة ثم عرض cover —
/// بلا تبعية لفقاعة المحادثة (مقاسات شبكة لا مقاسات رسالة)
class _GridImage extends StatefulWidget {
  const _GridImage({required this.loader});
  final Future<Uint8List?> Function() loader;

  @override
  State<_GridImage> createState() => _GridImageState();
}

class _GridImageState extends State<_GridImage> {
  late final Future<Uint8List?> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            color: context.glass,
            child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.data == null) {
          return Container(
            color: context.glass,
            child: Icon(Icons.broken_image_rounded,
                size: 24, color: context.textFaint),
          );
        }
        return Image.memory(snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true);
      },
    );
  }
}

/// معرض وسائط المحادثة (المرحلة 8 ب — 0.21.0)
///
/// شبكة كل وسائط المحادثة (صور/فيديو/ملفات/صوتيات) بفلترة حسب النوع،
/// والنقر على أي وسيط يفتح المحادثة **مقفلاً على رسالته** (قفز دقيق
/// بالفهرس عبر scrollable_positioned_list).
///
/// الرسائل الوسائطية تُجلب من الخادم كما هي (مشفرة في المحادثات المشفرة)
/// وتُفك محلياً — لا يغادر أي شيء جهازك.
class MediaGalleryScreen extends StatefulWidget {
  const MediaGalleryScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.isGroup,
    required this.isChannel,
    required this.encrypted,
    this.otherId,
    this.isSaved = false,
    this.isBot = false,
  });

  final String conversationId;
  final String title;
  final bool isGroup;
  final bool isChannel;
  final bool encrypted;
  final String? otherId;
  final bool isSaved;
  final bool isBot;

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  static const _limit = 500;

  final String _me = supabase.auth.currentUser!.id;
  List<MediaItem> _items = const [];
  String _tab = MediaGalleryService.tabs.first;
  bool _loading = true;
  String? _error;

  // فك النص (ميتا/تعليق) — نفس منطق شاشة المحادثة
  final Map<String, String> _plain = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _e2e => widget.encrypted && !widget.isChannel;

  String? _textOf(Map<String, dynamic> m) {
    final raw = m['content'] as String? ?? '';
    if (raw.isEmpty) return null;
    return E2eService.isEncrypted(raw) ? _plain[raw] : raw;
  }

  Future<String?> _decrypt(String content) async {
    if (!widget.isGroup) {
      if (widget.otherId == null) return null;
      return E2eService.decryptDmText(widget.conversationId, widget.otherId!, content);
    }
    var plain = await E2eService.decryptGroupText(widget.conversationId, content);
    if (plain == null) {
      E2eService.invalidateGroupKey(widget.conversationId);
      plain = await E2eService.decryptGroupText(widget.conversationId, content);
    }
    return plain;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await supabase
          .from('messages')
          .select('id, sender_id, type, content, media_url, created_at, deleted_at, view_once')
          .eq('conversation_id', widget.conversationId)
          .inFilter('type', ['image', 'video', 'file', 'voice'])
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(_limit);
      final list = List<Map<String, dynamic>>.from(rows);
      // فك ميتا/تعليقات الوسائط المشفرة (نقطة واحدة لكل نص مشفر)
      if (_e2e) {
        final futures = <Future<void>>[];
        for (final m in list) {
          final c = m['content'] as String? ?? '';
          if (c.isNotEmpty &&
              E2eService.isEncrypted(c) &&
              !_plain.containsKey(c)) {
            futures.add(_decrypt(c).then((p) {
              _plain[c] = p ?? '🔒';
            }));
          }
        }
        await Future.wait(futures);
      }
      if (!mounted) return;
      setState(() {
        _items = MediaGalleryService.collect(list, _textOf, myId: _me);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذّر جلب الوسائط — تحقق من الاتصال';
        });
      }
    }
  }

  List<MediaItem> get _filtered => MediaGalleryService.filter(_items, _tab);
  Map<String, int> get _counts => MediaGalleryService.counts(_items);

  void _openInChat(MediaItem item) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: widget.conversationId,
          title: widget.title,
          isGroup: widget.isGroup,
          otherId: widget.otherId,
          isChannel: widget.isChannel,
          encrypted: widget.encrypted,
          isSaved: widget.isSaved,
          isBot: widget.isBot,
          focusMessageId: item.messageId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text('وسائط ${widget.title}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        // شريط الفلترة بأعداد كل نوع
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final t in MediaGalleryService.tabs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text('${t} ${_counts[t] == 0 ? '' : _counts[t]}'),
                    selected: _tab == t,
                    onSelected: (_) => setState(() => _tab = t),
                    selectedColor: WaslColors.teal,
                    labelStyle: TextStyle(
                        color: _tab == t ? Colors.white : context.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ListView(padding: const EdgeInsets.all(24), children: [
                      GlassEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: _error!,
                        subtitle: 'اضغط للمحاولة مجدداً',
                      ),
                    ])
                  : filtered.isEmpty
                      ? ListView(padding: const EdgeInsets.all(24), children: [
                          const GlassEmptyState(
                            icon: Icons.photo_library_outlined,
                            title: 'لا وسائط بعد',
                            subtitle:
                                'الصور والفيديو والملفات والصوتيات المتبادلة هنا ستظهر في شبكة واحدة',
                          ),
                        ])
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 120),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final item = filtered[i];
                              return MotionStagger(
                                index: i.clamp(0, 12),
                                child: _tile(item),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _tile(MediaItem item) {
    Widget child;
    if (item.isImage) {
      child = _GridImage(loader: () => _mediaBytes(item.mediaUrl));
    } else {
      final icon = item.isVideo
          ? Icons.play_circle_fill
          : item.isVoice
              ? Icons.graphic_eq_rounded
              : Icons.insert_drive_file_rounded;
      final color = item.isVideo
          ? WaslColors.indigo
          : item.isVoice
              ? WaslColors.teal
              : WaslColors.violet;
      child = Container(
        color: context.glass,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 30, color: color),
          if (item.name != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(item.name!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, height: 1.2)),
            ),
          ],
        ]),
      );
    }
    return InkWell(
      onTap: () => _openInChat(item),
      child: Stack(fit: StackFit.expand, children: [
        child,
        PositionedDirectional(
          top: 4,
          end: 4,
          child: Icon(
            item.mine ? Icons.north_west_rounded : Icons.south_east_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.9),
            shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
      ]),
    );
  }

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

  // مفتاح المحادثة الفردية (ECDH) — المجموعات تمر عبر decryptGroupBytes
  Future<dynamic> _convKey() async {
    if (widget.otherId == null) return null;
    return E2eService.dmKey(widget.conversationId, widget.otherId!);
  }
}
