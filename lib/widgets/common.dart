import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// إجمالي الرسائل غير المقروءة عبر المحادثات — يشغّل شارة تبويب
/// «المحادثات» في الشريط السفلي (تتحدث مع كل تحميل للقائمة).
class UnreadHub {
  static final ValueNotifier<int> total = ValueNotifier<int>(0);
}

/// مؤقّت تهدئة لحقول البحث: لا نضرب الخادم بكل حرف،
/// بل ننفّذ البحث بعد توقّف الكتابة عن الحركة.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 400)]);
  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}

/// الزر العائم الموحّد للتطبيق: تدرج العلامة (نيلة -> تركواز) بزوايا ناعمة
/// وظل هادئ — يستخدم في المحادثات والقنوات والمجتمعات بدل الألوان المتضاربة.
class WaslFab extends StatelessWidget {
  const WaslFab({super.key, required this.onPressed, required this.icon});
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: WaslColors.gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: WaslColors.indigo.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          onTap: onPressed,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

/// حالة فراغ موحّدة: أيقونة داخل حلقة زجاجية + عنوان + شرح —
/// تستخدم في المحادثات والقنوات والمجتمعات بدل النصوص العارية.
class GlassEmptyState extends StatelessWidget {
  const GlassEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: context.glass,
                shape: BoxShape.circle,
                border: Border.all(color: context.hairline),
              ),
              child: Icon(icon, size: 40, color: context.iconStd),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      height: 1.7,
                      color: context.textTertiary,
                      fontSize: 13.5)),
            ],
          ],
        ),
      ),
    );
  }
}

String previewText(Map<String, dynamic> row, {String empty = 'لا توجد رسائل بعد'}) {
  switch (row['last_type']) {
    case 'image':
      return '📷 صورة';
    case 'voice':
      return '🎤 رسالة صوتية';
    case 'video':
      return '🎬 فيديو';
    case 'file':
      return '📎 ملف';
    default:
      return (row['last_message'] as String?) ?? empty;
  }
}

String shortTime(String? iso) {
  if (iso == null) return '';
  final d = DateTime.parse(iso).toLocal();
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '${d.day}/${d.month}';
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: WaslColors.gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(count > 99 ? '99+' : '$count',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

/// نافذة: اسم + وصف (لإنشاء مجتمع أو قناة)
Future<(String, String)?> askNameAndDescription(
  BuildContext context, {
  required String title,
  required String nameHint,
  bool withDescription = true,
}) {
  final name = TextEditingController();
  final desc = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: context.surfaceAlt,
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, autofocus: true, decoration: InputDecoration(hintText: nameHint)),
        if (withDescription) ...[
          const SizedBox(height: 10),
          TextField(
            controller: desc,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(hintText: 'وصف قصير (اختياري)'),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) return;
            Navigator.pop(ctx, (name.text.trim(), desc.text.trim()));
          },
          child: const Text('إنشاء'),
        ),
      ],
    ),
  );
}

/// شريط بحث + عنوان قسم
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(color: context.textTertiary, fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

/// صورة شخصية دائرية: الصورة إن وُجدت، وإلا أول حرف من الاسم
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 26,
    this.color = WaslColors.indigo,
    this.icon,
  });
  final String name;
  final String? url;
  final double radius;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage: hasUrl ? NetworkImage(url!) : null,
      onForegroundImageError: hasUrl ? (_, __) {} : null,
      child: icon != null
          ? Icon(icon, color: Colors.white, size: radius)
          : Text(name.isNotEmpty ? name.characters.first : '?',
              style: TextStyle(color: Colors.white, fontSize: radius * 0.75)),
    );
  }
}
