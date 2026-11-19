import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_studio_service.dart';
import '../theme.dart';
import '../widgets/tone_picker_sheet.dart';
import '../widgets/wasl_sheet.dart';

/// «استوديو المحادثة» (1.13.0): شكل هذه المحادثة وحدها — الخلفية (أو صورة
/// من جهازك)، ألوان الفقاعات وشكلها، حجم الخط، والنغمة. ما لا تغيّره يتبع
/// «استوديو التطبيق». كل شيء محفوظ على جهازك فقط ولا يراه الطرف الآخر.
class ChatStudioScreen extends StatelessWidget {
  const ChatStudioScreen({super.key, required this.conversationId, required this.title});
  final String conversationId;
  final String title;

  ValueNotifier<ChatStyle> get _n => ChatStudioService.of(conversationId);

  void _set(ChatStyle Function(ChatStyle c) f) {
    AppStudioService.tick();
    ChatStudioService.set(conversationId, f(_n.value));
  }

  Future<void> _pickImage(BuildContext context) async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (x == null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final path = '${dir.path}/chat_wp_${conversationId.hashCode.abs()}_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
      await x.saveTo(path);
      _set((c) => c.copyWith(imagePath: () => path, wallpaper: () => null));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر حفظ الصورة')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('استوديو المحادثة',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(title, style: TextStyle(fontSize: 12.5, color: context.textTertiary)),
        ]),
      ),
      body: ValueListenableBuilder<ChatStyle>(
        valueListenable: _n,
        builder: (context, c, _) => ValueListenableBuilder<StudioStyle>(
          valueListenable: AppStudioService.style,
          builder: (context, g, _) => Column(children: [
            // معاينة: خلفية المحادثة + فقاعات بحجم الخط المختار
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 190,
                  child: ChatBackground(
                    chat: c,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(
                              FontScaleService.scale.value * (c.fontScale ?? 1.0))),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          _PreviewBubble(g: g, c: c, mine: false, text: 'مرحباً! كيف حالك؟'),
                          _PreviewBubble(g: g, c: c, mine: true, text: 'بخير الحمد لله 🌿'),
                          _PreviewBubble(g: g, c: c, mine: false, text: 'شكل المحادثة رائع'),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  const SheetSectionLabel('الخلفية'),
                  GlassGroup([
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(spacing: 10, runSpacing: 10, children: [
                        _WpTile(
                          label: 'مثل التطبيق',
                          selected: c.wallpaper == null && c.imagePath == null,
                          onTap: () => _set((x) =>
                              x.copyWith(wallpaper: () => null, imagePath: () => null)),
                          child: Icon(Icons.auto_mode_rounded, color: context.textSecondary),
                        ),
                        for (var i = 0; i < WallpaperService.wallpapers.length; i++)
                          _WpTile(
                            label: WallpaperService.wallpapers[i].name,
                            selected: c.imagePath == null && c.wallpaper == i,
                            onTap: () => _set((x) =>
                                x.copyWith(wallpaper: () => i, imagePath: () => null)),
                            child: CustomPaint(
                              painter: WallpaperPainter(WallpaperService.wallpapers[i],
                                  dark: Theme.of(context).brightness == Brightness.dark),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        if (!kIsWeb)
                          _WpTile(
                            label: 'من جهازك',
                            selected: c.imagePath != null,
                            onTap: () => _pickImage(context),
                            child: Icon(Icons.add_photo_alternate_rounded,
                                color: WaslColors.accent),
                          ),
                      ]),
                    ),
                  ]),
                  const SheetSectionLabel('الفقاعات'),
                  GlassGroup([
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('لون رسائلي', style: TextStyle(color: context.textSecondary)),
                        const SizedBox(height: 8),
                        _ColorRow(
                          colors: StudioCatalog.swatches,
                          selected: c.ownBubble,
                          onPick: (v) => _set((x) => x.copyWith(ownBubble: () => v)),
                        ),
                        const SizedBox(height: 14),
                        Text('صبغة رسائلهم', style: TextStyle(color: context.textSecondary)),
                        const SizedBox(height: 8),
                        _ColorRow(
                          colors: StudioCatalog.otherTints,
                          selected: c.otherBubble,
                          onPick: (v) => _set((x) => x.copyWith(otherBubble: () => v)),
                        ),
                        const SizedBox(height: 14),
                        Text('الشكل', style: TextStyle(color: context.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          ChoiceChip(
                            label: const Text('مثل التطبيق'),
                            selected: c.bubbleShape == null,
                            onSelected: (_) =>
                                _set((x) => x.copyWith(bubbleShape: () => null)),
                          ),
                          for (final sh in StudioBubbleShape.values)
                            ChoiceChip(
                              label: Text(sh.label),
                              selected: c.bubbleShape == sh,
                              onSelected: (_) =>
                                  _set((x) => x.copyWith(bubbleShape: () => sh)),
                            ),
                          for (final f in StudioBubbleFill.values)
                            ChoiceChip(
                              label: Text(f.label),
                              selected: c.bubbleFill == f,
                              onSelected: (_) => _set((x) => x.copyWith(
                                  bubbleFill: () => c.bubbleFill == f ? null : f)),
                            ),
                        ]),
                      ]),
                    ),
                  ]),
                  const SheetSectionLabel('حجم الخط هنا'),
                  GlassGroup([
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final (v, label) in const [
                          (null, 'مثل التطبيق'),
                          (0.9, 'أصغر'),
                          (1.15, 'أكبر'),
                          (1.3, 'كبير جداً'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: c.fontScale == v,
                            onSelected: (_) => _set((x) => x.copyWith(fontScale: () => v)),
                          ),
                      ]),
                    ),
                  ]),
                  const SheetSectionLabel('الصوت'),
                  GlassGroup([
                    SheetTile(
                      icon: Icons.music_note_rounded,
                      color: WaslColors.teal,
                      title: 'نغمة هذه المحادثة',
                      subtitle: kIsWeb ? 'متاحة في تطبيق الجوال' : null,
                      onTap: kIsWeb
                          ? null
                          : () => showTonePicker(context, conversationId: conversationId),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  GlassGroup([
                    SheetTile(
                      icon: Icons.restart_alt_rounded,
                      danger: true,
                      title: 'رجوع لشكل التطبيق',
                      subtitle: 'يلغي تخصيص هذه المحادثة فقط',
                      onTap: () => ChatStudioService.reset(conversationId),
                    ),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// خلفية المحادثة الفعلية: صورة الجهاز ← خلفية المحادثة ← خلفية التطبيق
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key, required this.chat, required this.child});
  final ChatStyle chat;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final path = chat.imagePath;
    if (path != null && !kIsWeb) {
      return Stack(fit: StackFit.passthrough, children: [
        Positioned.fill(child: _LocalImage(path: path)),
        Positioned.fill(
          child: ColoredBox(
              color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.25)),
        ),
        child,
      ]);
    }
    final i = chat.wallpaper;
    return ValueListenableBuilder<int>(
      valueListenable: WallpaperService.index,
      builder: (context, _, __) {
        final wp = (i != null && i >= 0 && i < WallpaperService.wallpapers.length)
            ? WallpaperService.wallpapers[i]
            : WallpaperService.current;
        return CustomPaint(painter: WallpaperPainter(wp, dark: dark), child: child);
      },
    );
  }
}

class _LocalImage extends StatefulWidget {
  const _LocalImage({required this.path});
  final String path;

  @override
  State<_LocalImage> createState() => _LocalImageState();
}

class _LocalImageState extends State<_LocalImage> {
  static final Map<String, Uint8List> _mem = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LocalImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    final cached = _mem[widget.path];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    try {
      final b = await XFile(widget.path).readAsBytes();
      _mem[widget.path] = b;
      if (mounted) setState(() => _bytes = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) return const SizedBox.shrink();
    return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({required this.g, required this.c, required this.mine, required this.text});
  final StudioStyle g;
  final ChatStyle c;
  final bool mine;
  final String text;

  @override
  Widget build(BuildContext context) {
    final look = BubbleLook.resolve(g, c);
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: look.decoration(mine: mine, otherBase: context.bubbleOther),
        child: Text(text, style: TextStyle(color: mine ? Colors.white : null)),
      ),
    );
  }
}

class _WpTile extends StatelessWidget {
  const _WpTile({required this.label, required this.selected, required this.onTap, required this.child});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 66,
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.glass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: selected ? WaslColors.accent : context.hairline,
                    width: selected ? 2.5 : 1),
              ),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(14), child: Center(child: child)),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
      );
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.colors, required this.selected, required this.onPick});
  final List<int> colors;
  final int? selected;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 9, runSpacing: 9, children: [
        ChoiceChip(
          label: const Text('مثل التطبيق'),
          selected: selected == null,
          onSelected: (_) => onPick(null),
        ),
        for (final c in colors)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected == c ? context.textPrimary : Colors.transparent,
                    width: 2.5),
              ),
              child: selected == c
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : null,
            ),
          ),
      ]);
}
