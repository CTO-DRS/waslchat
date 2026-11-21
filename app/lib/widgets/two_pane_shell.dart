/// قوقعة اللوحتين (1.21.0) — العرض الواسع «قائمة + دردشة» جنب إلى جنب:
/// القائمة في بداية اتجاه اللغة والفاصل الشعري بينهما، وشريط إغلاق رفيع
/// فوق التفصيل كي يعود المستخدم للقائمة الكاملة.
///
/// تفصيلان صادقان:
/// 1. التفصيل (`ChatScreen`) مضمّن **بلا أي مسار فوق مسار الجذر** —
///    شريط `AppBar` الافتراضي لا يعرض زر رجوع حين `canPop=false` فلا
///    يخطف المستخدم للخارج، والإغلاق من شريط القوقعة حصراً.
/// 2. التفصيل ملفوف بـ`HeroMode(enabled: false)` كي لا يتعارض طيران
///    الصورة (Hero بأفاتار القائمة) مع نسخة الأفاتار في التفصيل —
///    وسم واحد ببطلين في شجرة واحدة يستثني Flutter.
library;

import 'package:material_ui/material_ui.dart';

import '../services/wide_layout_service.dart';

class TwoPaneShell extends StatelessWidget {
  const TwoPaneShell({
    super.key,
    required this.list,
    required this.detail,
    required this.onClosed,
  });

  final Widget list;
  final Widget detail;
  final VoidCallback onClosed;

  static const Key listKey = Key('two-pane-list');
  static const Key detailKey = Key('two-pane-detail');
  static const Key closeKey = Key('two-pane-close');

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(key: listKey, child: list),
        VerticalDivider(
            width: 1, thickness: 1, color: Theme.of(context).dividerColor),
        Expanded(
          key: detailKey,
          child: Column(children: [
            // شريط الإغلاق الرفيع — زر واحد في بداية الاتجاه حيث يكون
            // زر الرجوع في أي شاشة، بلا نص يكرر عنوان الدردشة
            Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SizedBox(
                height: 36,
                width: double.infinity,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    key: closeKey,
                    tooltip: 'إغلاق اللوحة الجانبية',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClosed,
                  ),
                ),
              ),
            ),
            Divider(
                height: 1, thickness: 1, color: Theme.of(context).dividerColor),
            Expanded(
              child: HeroMode(enabled: false, child: detail),
            ),
          ]),
        ),
      ],
    );
  }
}

/// قرارات عرض القوقعة النقية — تفصل موضع الشريط عن قواعد الخدمة كي
/// تُختبَر الويدجت بلا شاشات التطبيق.
class TwoPaneRules {
  TwoPaneRules._();

  /// هل الانقسام ظاهر الآن؟ عتبة الخدمة + تبويب المحادثات + لوحة مفتوحة
  static bool showSplit({
    required double width,
    required bool chatsTabActive,
    required bool hasOpenChat,
  }) =>
      WideLayoutService.isWide(width) && chatsTabActive && hasOpenChat;
}
