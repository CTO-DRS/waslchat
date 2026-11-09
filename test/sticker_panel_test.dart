import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_chat/services/sticker_service.dart';
import 'package:wasl_chat/widgets/sticker_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPanel(WidgetTester tester,
      {required void Function(String, String) onPick,
      required VoidCallback onClose}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StickerPanel(onPick: onPick, onClose: onClose),
      ),
    ));
    // ننتظر تحميل «الأحدث» من التخزين دون pumpAndSettle (فكّ الصور يتدفق)
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// GridView كسول: نمرّر للنهاية ونجمع أسماء الأصول المبنية كمجموعة
  Set<String> _builtNames(WidgetTester tester) =>
      tester
          .widgetList<Image>(find.byType(Image))
          .map((w) => (w.image as AssetImage).assetName)
          .toSet();

  Future<Set<String>> _scrollAll(WidgetTester tester) async {
    final seen = <String>{};
    for (var i = 0; i < 10; i++) {
      seen.addAll(_builtNames(tester));
      if (seen.length >= StickerService.basicsOrder.length) return seen;
      await tester.fling(
          find.byType(GridView).first, const Offset(0, -300), 2000);
      await tester.pump(const Duration(milliseconds: 100));
    }
    seen.addAll(_builtNames(tester));
    return seen;
  }

  testWidgets('تبويب الأساسيات يعرض كل ملصقات الحزمة المدمجة عند التمرير',
      (tester) async {
    await pumpPanel(tester, onPick: (_, __) {}, onClose: () {});
    final seen = await _scrollAll(tester);
    final expected = {
      for (final id in StickerService.basicsOrder)
        'assets/stickers/basics/$id.${StickerService.extOf(id)}'
    };
    expect(seen, expected);
  });

  testWidgets('الضغط على ملصق يرسل المفتاح الصحيح ويحدّث الأحدث',
      (tester) async {
    var picked = <String>[];
    await pumpPanel(tester,
        onPick: (p, i) => picked.add('$p/$i'), onClose: () {});
    // أول بلاطة صورة = أول id في الترتيب — والـInkWell سلفها
    // (أول InkWell في الشجرة هو داخلي الشيب وليس بلاطة)
    final tileInk = find.ancestor(
        of: find.byType(Image).first, matching: find.byType(InkWell));
    await tester.tap(tileInk.first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(picked, ['basics/${StickerService.basicsOrder.first}']);
    // وقد دخل سجل «الأحدث» المحلي
    expect(await StickerService.recent(),
        [('basics', StickerService.basicsOrder.first)]);
  });

  testWidgets('وجود سجل محلي مسبق يفتح تبويب الأحدث', (tester) async {
    SharedPreferences.setMockInitialValues({
      'sticker_recent': ['basics|star', 'basics|fire'],
    });
    await pumpPanel(tester, onPick: (_, __) {}, onClose: () {});
    expect(find.text('الأحدث'), findsOneWidget);
    // البلاطتان المبنيتان هما نجمة ونار (الشبكة كسولة والبلاطتان أولتان)
    expect(_builtNames(tester),
        {'assets/stickers/basics/star.webp', 'assets/stickers/basics/fire.webp'});
  });

  testWidgets('زر الإغلاق يستدعي onClose', (tester) async {
    var closed = false;
    await pumpPanel(tester, onPick: (_, __) {}, onClose: () => closed = true);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    expect(closed, isTrue);
  });

  testWidgets('التبديل بين الأحدث والأساسيات يعمل', (tester) async {
    SharedPreferences.setMockInitialValues({
      'sticker_recent': ['basics|star'],
    });
    await pumpPanel(tester, onPick: (_, __) {}, onClose: () {});
    // نحن في الأحدث (بلاطة واحدة)
    expect(_builtNames(tester), {'assets/stickers/basics/star.webp'});
    await tester.tap(find.text(StickerService.packBasicsTitle));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_builtNames(tester),
        contains('assets/stickers/basics/smile.webp')); // أول الأساسيات
    expect(_builtNames(tester).length, greaterThanOrEqualTo(10));
    // والعودة للأحدث
    await tester.tap(find.text('الأحدث'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_builtNames(tester), {'assets/stickers/basics/star.webp'});
  });
}
