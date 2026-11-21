/// اختبارات التخطيط الواسع (1.21.0): قواعد العتبة النقية، حالة اللوحة
/// (فتح واستبدال وإغلاق)، قوقعة اللوحتين (اللوحتان والفاصل وشريط
/// الإغلاق ومعطّل الـHero)، وقرار الانقسام النقي.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/wide_layout_service.dart';
import 'package:wasl_chat/widgets/two_pane_shell.dart';

void main() {
  group('قواعد العتبة النقية', () {
    test('تحت 900 عمود واحد ومن 900 لوحتان — الحد شامل', () {
      expect(WideLayoutService.isWide(899), isFalse);
      expect(WideLayoutService.isWide(900), isTrue);
      expect(WideLayoutService.isWide(1440), isTrue);
      expect(WideLayoutService.isWide(384), isFalse); // جوال
      expect(WideLayoutService.isWide(768), isFalse); // تابلت عمودي
      expect(WideLayoutService.isWide(1024), isTrue); // تابلت أفقي
    });

    test('الثابت 900 مطابق للخارطة', () {
      expect(WideLayoutService.threshold, 900);
    });
  });

  group('حالة اللوحة الثانية', () {
    test('open يضع المواصفات وclear يعيد الصمت', () {
      expect(WideLayoutService.activeChat.value, isNull);
      const spec = TwoPaneSpec(
          conversationId: 'c1', title: 'فريق العمل', isGroup: true);
      WideLayoutService.open(spec);
      expect(WideLayoutService.activeChat.value, same(spec));
      // الاستبدال طبيعي
      const spec2 = TwoPaneSpec(conversationId: 'c2', title: 'أخرى');
      WideLayoutService.open(spec2);
      expect(WideLayoutService.activeChat.value, same(spec2));
      WideLayoutService.clear();
      expect(WideLayoutService.activeChat.value, isNull);
    });

    test('المواصفات مرآة لمعاملات ChatScreen بالقيم الافتراضية الصحيحة',
        () {
      const spec = TwoPaneSpec(conversationId: 'c', title: 'ت');
      expect(spec.isGroup, isFalse);
      expect(spec.canPost, isTrue);
      expect(spec.encrypted, isFalse);
      expect(spec.otherId, isNull);
      expect(spec.initialAvatar, isNull);
    });
  });

  group('قرار الانقسام النقي', () {
    test('الشروط الثلاثة معاً: عرض + تبويب محادثات + لوحة مفتوحة', () {
      expect(
          TwoPaneRules.showSplit(
              width: 1200, chatsTabActive: true, hasOpenChat: true),
          isTrue);
      expect(
          TwoPaneRules.showSplit(
              width: 800, chatsTabActive: true, hasOpenChat: true),
          isFalse,
          reason: 'تحت العتبة عمود واحد');
      expect(
          TwoPaneRules.showSplit(
              width: 1200, chatsTabActive: false, hasOpenChat: true),
          isFalse,
          reason: 'الانقسام في تبويب المحادثات حصراً (بند الخارطة)');
      expect(
          TwoPaneRules.showSplit(
              width: 1200, chatsTabActive: true, hasOpenChat: false),
          isFalse,
          reason: 'بلا دردشة مفتوحة عمود واحد صادق');
    });
  });

  group('قوقعة اللوحتين', () {
    Future<void> _pump(WidgetTester tester,
        {required VoidCallback onClosed}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TwoPaneShell(
            list: Container(key: const Key('my-list')),
            detail: Container(key: const Key('my-detail')),
            onClosed: onClosed,
          ),
        ),
      ));
    }

    testWidgets('اللوحتان معاً: القائمة والتفصيل والفاصل الثلاثة', (t) async {
      await _pump(t, onClosed: () {});
      expect(find.byKey(const Key('my-list')), findsOneWidget);
      expect(find.byKey(const Key('my-detail')), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('شريط الإغلاق الرفيع يستدعي onClosed', (t) async {
      var closed = 0;
      await _pump(t, onClosed: () => closed++);
      expect(closed, 0);
      await t.tap(find.byKey(TwoPaneShell.closeKey));
      await t.pump();
      expect(closed, 1);
    });

    testWidgets('التفصيل معطّل الـHero — بطل واحد لا اثنان', (t) async {
      await _pump(t, onClosed: () {});
      expect(find.byType(HeroMode), findsOneWidget);
      final heroMode =
          t.widget<HeroMode>(find.byType(HeroMode));
      expect(heroMode.enabled, isFalse);
    });

    testWidgets('زر الإغلاق يملك tooltip صادقاً', (t) async {
      await _pump(t, onClosed: () {});
      expect(find.byTooltip('إغلاق اللوحة الجانبية'), findsOneWidget);
    });
  });
}
