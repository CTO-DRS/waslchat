import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../services/app_studio_service.dart';
import '../theme.dart';

/// الإشعار المنبثق داخل التطبيق: يظهر عند وصول رسالة والتطبيق مفتوح.
/// شكله ومكانه ومدته وإخفاء نصه كلها من «استوديو التطبيق» (1.13.0):
/// بطاقة زجاجية، أو كبسولة صغيرة، أو شريط سفلي. يختفي تلقائياً أو باللمس،
/// ويُسحب للإغلاق.
class WaslBanner {
  WaslBanner._();

  static OverlayEntry? _current;

  /// يعرض اللافتة فوق أي شاشة مفتوحة. [style] للمعاينة من الاستوديو.
  static void show(String title, String body, {StudioStyle? style}) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    late final OverlayState overlay;
    try {
      overlay = Overlay.of(ctx, rootOverlay: true);
    } catch (_) {
      return;
    }
    try {
      _current?.remove();
    } catch (_) {}
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => WaslBannerView(
        title: title,
        body: body,
        style: style ?? AppStudioService.style.value,
        onDismiss: () {
          try {
            entry.remove();
          } catch (_) {}
          if (identical(_current, entry)) _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class WaslBannerView extends StatefulWidget {
  const WaslBannerView({
    super.key,
    required this.title,
    required this.body,
    required this.style,
    required this.onDismiss,
  });
  final String title;
  final String body;
  final StudioStyle style;
  final VoidCallback onDismiss;

  @override
  State<WaslBannerView> createState() => _WaslBannerViewState();
}

class _WaslBannerViewState extends State<WaslBannerView> {
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: widget.style.bannerSeconds), _close);
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final top = s.banner != StudioBanner.toast && s.bannerTop;
    final body = s.bannerPreview ? widget.body : 'رسالة جديدة';
    final title = widget.title;
    final surface = dark ? WaslColors.darkSurface : WaslColors.lightSurface;
    final text2 = dark ? Colors.white70 : WaslColors.ink2;
    final motion = s.motion;

    Widget card;
    switch (s.banner) {
      case StudioBanner.card:
        card = ClipRRect(
          borderRadius: BorderRadius.circular(s.r(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(s.r(20)),
                border: Border.all(
                    color: dark ? Colors.white24 : Colors.black.withValues(alpha: 0.08)),
              ),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: s.gradient,
                    borderRadius: BorderRadius.circular(s.r(14)),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: text2, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.close_rounded,
                    size: 18, color: dark ? Colors.white54 : WaslColors.ink3),
              ]),
            ),
          ),
        );
      case StudioBanner.pill:
        card = Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: s.accentColor.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: s.gradient),
                child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 15),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: '  $body', style: TextStyle(color: text2)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
        );
      case StudioBanner.toast:
        card = Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: s.gradient,
            borderRadius: BorderRadius.circular(s.r(16)),
          ),
          child: Row(children: [
            const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$title: $body',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        );
    }

    final shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s.r(20)),
        boxShadow: s.banner == StudioBanner.pill
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: card,
    );

    final dir = top ? -1.0 : 1.0;
    return Positioned(
      top: top ? mq.padding.top + 8 : null,
      bottom: top ? null : mq.padding.bottom + 90,
      left: 12,
      right: 12,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: motion == StudioMotion.off ? 1 : 0, end: 1),
        duration: Duration(milliseconds: motion == StudioMotion.full ? 300 : 160),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * dir * (1 - t)),
            child: child,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: const ValueKey('wasl-banner'),
            direction: top ? DismissDirection.up : DismissDirection.down,
            onDismissed: (_) => _close(),
            child: InkWell(
              borderRadius: BorderRadius.circular(s.r(20)),
              onTap: _close,
              child: shadowed,
            ),
          ),
        ),
      ),
    );
  }
}
