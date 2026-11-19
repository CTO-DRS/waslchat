import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'wasl_mascot.dart';
import '../services/app_studio_service.dart';

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
            // «وصول» يؤنس الحالة الفارغة (1.13.0) مع أيقونة القسم بجانبه
            SizedBox(
              width: 120,
              height: 112,
              child: Stack(clipBehavior: Clip.none, children: [
                const Center(child: WaslMascot(size: 104, mood: MascotMood.sleepy)),
                PositionedDirectional(
                  end: 0,
                  bottom: 4,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.surfaceAlt,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.hairline),
                    ),
                    child: Icon(icon, size: 19, color: context.iconStd),
                  ),
                ),
              ]),
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
    // استوديو التطبيق (1.13.0): صورة بمربع ناعم بدل الدائرة عند اختيارها
    if (AppStudioService.style.value.avatarShape == StudioAvatarShape.squircle) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius * 0.62),
          image: hasUrl
              ? DecorationImage(
                  image: NetworkImage(url!), fit: BoxFit.cover, onError: (_, __) {})
              : null,
        ),
        child: hasUrl
            ? null
            : icon != null
                ? Icon(icon, color: Colors.white, size: radius)
                : Text(name.isNotEmpty ? name.characters.first : '?',
                    style: TextStyle(color: Colors.white, fontSize: radius * 0.75)),
      );
    }
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

/// شارة التوثيق الرسمية (v0.13.0): علامة تحقق زرقاء بجانب اسم مجتمع أو قناة رسمية.
/// المنح والسحب من الخادم لمسؤولي التطبيق حصراً عبر دوال ترحيل 025 (verify_community /
/// verify_channel) — هنا العرض فقط بلا أي منطق كتابة.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    this.size = 16,
    this.tooltip = 'حساب رسمي موثّق من وصل شات',
  });
  final double size;
  final String tooltip;

  /// أزرق التوثيق القياسي — ثابت في الوضعين الفاتح والداكن على كل الخلفيات.
  static const color = Color(0xFF1D9BF0);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Icon(Icons.verified, size: size, color: color),
      );
}


/// شارة الحساب الرسمي لوصل شات (1.11.0): درع بتدرّج ألوان التطبيق مع علامة
/// تحقق — تميّز حسابات التطبيق نفسه (@waslchat، الدعم، القناة والمجموعة
/// الرسمية) عن التوثيق الأزرق العادي. العرض فقط؛ المنح من الخادم.
class OfficialBadge extends StatelessWidget {
  const OfficialBadge({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'حساب رسمي من وصل شات',
        child: ShaderMask(
          shaderCallback: (r) => WaslColors.gradient.createShader(r),
          child: Icon(Icons.verified_user_rounded, size: size, color: Colors.white),
        ),
      );
}

/// وسم «ما زالت تحت التطوير» (1.11.0) للميزات غير المكتملة
class DevBadge extends StatelessWidget {
  const DevBadge({super.key, this.short = false});
  final bool short;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(short ? 'تحت التطوير' : 'ما زالت تحت التطوير',
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
      );
}


/// هيكل تحميل لامع بدل الدائرة الدوّارة (1.13.0): صفوف رمادية يمر عليها
/// بريق خفيف — ثابتة عند إيقاف الحركة.
class WaslSkeletonList extends StatefulWidget {
  const WaslSkeletonList({super.key, this.rows = 8});
  final int rows;

  @override
  State<WaslSkeletonList> createState() => _WaslSkeletonListState();
}

class _WaslSkeletonListState extends State<WaslSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    if (AppStudioService.motionOn) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.hairline.withValues(alpha: 0.35);
    final hi = context.hairline.withValues(alpha: 0.8);
    Widget bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(h / 2)));
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: [base, hi, base],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1.6 + 3.2 * _c.value, 0),
          end: Alignment(-0.6 + 3.2 * _c.value, 0),
        ).createShader(r),
        child: child,
      ),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.rows,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                bar(120.0 + (i % 3) * 30, 12),
                const SizedBox(height: 8),
                bar(200.0 - (i % 4) * 25, 10),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
