import 'package:flutter/material.dart';

import '../theme.dart';

/// ورقة سفلية موحّدة لوصل (1.9.3): مقبض سحب، عنوان اختياري، محتوى قابل
/// للتمرير لا يتجاوز 88% من الشاشة، وحشوة سفلية تحترم شريط إيماءات الجوال
/// فلا ينقطع آخر عنصر تحته.
Future<T?> showWaslSheet<T>(
  BuildContext context, {
  String? title,
  IconData? titleIcon,
  required List<Widget> Function(BuildContext ctx) children,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.surfaceAlt,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: mq.viewPadding.bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                  child: Row(children: [
                    if (titleIcon != null) ...[
                      ShaderMask(
                        shaderCallback: (r) => WaslColors.gradient.createShader(r),
                        child: Icon(titleIcon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ...children(ctx),
            ],
          ),
        ),
      );
    },
  );
}

/// زر دائري ملوّن بعنوان تحته — لشبكة المرفقات والإجراءات السريعة
class SheetAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool active;
  const SheetAction(this.icon, this.label, this.color, this.onTap,
      {this.active = false});
}

class SheetActionGrid extends StatelessWidget {
  final List<SheetAction> actions;
  final int perRow;
  const SheetActionGrid(this.actions, {super.key, this.perRow = 4});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / perRow;
        return Wrap(
          children: [
            for (final a in actions)
              SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: a.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              a.color.withValues(alpha: a.active ? 0.95 : 0.85),
                              Color.lerp(a.color, Colors.black, 0.25)!,
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: a.color.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5)),
                          ],
                          border: a.active
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                        child: Icon(a.icon, color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(a.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary)),
                    ]),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// عنوان قسم صغير داخل الورقة أو الإعدادات
class SheetSectionLabel extends StatelessWidget {
  final String text;
  const SheetSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(22, 14, 22, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: context.textFaint)),
      );
}

/// صف إجراء في الورقة: أيقونة داخل مربع ملوّن ناعم + عنوان + وصف قصير
class SheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final bool danger;
  final Widget? trailing;
  final VoidCallback? onTap;
  const SheetTile(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.color,
      this.danger = false,
      this.trailing,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = danger ? Colors.redAccent : (color ?? context.textSecondary);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: c, size: 21),
      ),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: danger ? Colors.redAccent : null)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: context.textFaint)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// بطاقة زجاجية تجمع صفوفاً (أقسام الإعدادات)
class GlassGroup extends StatelessWidget {
  final List<Widget> children;
  const GlassGroup(this.children, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: context.glass,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.hairline.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                  height: 1,
                  indent: 70,
                  color: context.hairline.withValues(alpha: 0.4)),
          ]
        ]),
      );
}

/// يغلّف أيقونة صف بمربع ملوّن ناعم بلونها (هوية الإعدادات 1.9.3)
class TintIcon extends StatelessWidget {
  final Icon icon;
  const TintIcon(this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = icon.color ?? context.textSecondary;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon.icon, color: c, size: 21),
    );
  }
}
