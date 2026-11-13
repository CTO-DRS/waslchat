import 'package:flutter/material.dart';

/// الحركة (المرحلة 5 — v0.14.0): بدائل دخول خفيفة موحّدة — ظهور بانزلاق
/// وتلاشٍ للفقاعات والقوائم، مع ذاكرة «شُوهد سابقاً» حتى لا تُعاد الحركة عند
/// كل إعادة بناء للقائمة (فقط للعناصر الجديدة فعلاً).
///
/// الاستخدام النمطي داخل شاشة بها عناصر تتغير:
/// ```dart
/// final firstTime = _seenIds.add(id); // في build — إضافة صامتة لا setState
/// child = firstTime ? MotionBubble(child: child) : child;
/// ```

/// ظهور بانزلاق خفيف من الأسفل مع تلاشٍ (260ms).
class MotionBubble extends StatelessWidget {
  const MotionBubble({super.key, required this.child, this.mine = false});
  final Widget child;

  /// اتجاه البدء: رسائلي تنزلق من الأسفل، والأخرى من أعلى قليلاً.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, w) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * (mine ? 14 : -14)),
          child: w,
        ),
      ),
      child: child,
    );
  }
}

/// ظهور متدرج بعناصر القائمة: تلاشٍ + إزاحة، بتأخير بحسب الموضع (حتى 10 عناصر)
/// — للقوائم التي تُبنى من جديد عند الفتح (الأحداث، نتائج البحث).
class MotionStagger extends StatelessWidget {
  const MotionStagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 10)) * 28;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + delay),
      curve: const Interval(0, 1, curve: Curves.easeOutCubic),
      builder: (context, t, w) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: w),
      ),
      child: child,
    );
  }
}

/// ظهور بالتكبير للأزرار العائمة والشرائح (0.85→1 مع تلاشٍ).
class MotionScaleIn extends StatelessWidget {
  const MotionScaleIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, w) =>
          Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: t, child: w)),
      child: child,
    );
  }
}
