import 'package:flutter/material.dart';

import '../services/sticker_service.dart';
import '../theme.dart';

/// لوحة منتقي الملصقات (0.4.9): تبويب «الأحدث» (محلي فقط) + الحزمة المدمجة.
/// الضغط يُرسل فوراً وتبقى اللوحة مفتوحة للإرسال المتتابع.
class StickerPanel extends StatefulWidget {
  const StickerPanel({super.key, required this.onPick, required this.onClose});
  final void Function(String pack, String id) onPick;
  final VoidCallback onClose;

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  List<(String, String)> _recent = const [];
  bool _recentTab = false; // بوليان صريح: تبويب الأحدث أو الحزمة المدمجة

  @override
  void initState() {
    super.initState();
    StickerService.recent().then((r) {
      if (!mounted) return;
      setState(() {
        _recent = r;
        if (r.isNotEmpty) _recentTab = true;
      });
    });
  }

  void _pick(String pack, String id) {
    widget.onPick(pack, id);
    StickerService.remember(pack, id).then((_) async {
      final r = await StickerService.recent();
      if (!mounted) return;
      setState(() => _recent = r);
    });
  }

  Widget _tile(String pack, String id) {
    return InkWell(
      onTap: () => _pick(pack, id),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          StickerService.assetPath(pack, id),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined,
              color: context.wasl.textFaint),
        ),
      ),
    );
  }

  bool get _hasRecent => _recent.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onClose,
            tooltip: 'إغلاق',
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: context.wasl.textSecondary),
          ),
          const Spacer(),
          if (_hasRecent)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: const Text('الأحدث', style: TextStyle(fontSize: 12)),
                selected: _recentTab,
                onSelected: (_) => setState(() => _recentTab = true),
                visualDensity: VisualDensity.compact,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text(StickerService.packBasicsTitle,
                  style: TextStyle(fontSize: 12)),
              selected: !_recentTab,
              onSelected: (_) => setState(() => _recentTab = false),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 12),
        ]),
        SizedBox(height: 250, child: _grid()),
      ],
    );
  }

  Widget _grid() {
    if (_recentTab && _hasRecent) {
      return GridView.count(
        crossAxisCount: 5,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [for (final (p, i) in _recent) _tile(p, i)],
      );
    }
    return GridView.count(
      crossAxisCount: 5,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        for (final id in StickerService.basicsOrder)
          _tile(StickerService.packBasics, id),
      ],
    );
  }
}
