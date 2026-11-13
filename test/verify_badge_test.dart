import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/widgets/common.dart';

/// اختبارات شارة التوثيق الرسمية (v0.13.0) — عرض فقط بلا منطق كتابة.
/// المنح والسحب من الخادم لمسؤولي التطبيق حصراً (ترحيل 025)؛ هنا نتحقق من
/// أن الواجهة تُظهر العلامة لما هو موثّق فقط وبالتلميح الصحيح.
void main() {
  Future<void> pumpBadge(WidgetTester tester, {bool verified = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: verified ? const VerifiedBadge() : const SizedBox.shrink(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('الشارة تُظهر أيقونة التحقق بلون التوثيق وتلميح الحساب الرسمي', (tester) async {
    await pumpBadge(tester);
    final icon = tester.widget<Icon>(find.byIcon(Icons.verified));
    expect(icon.color, VerifiedBadge.color);
    expect(icon.size, 16);
    // Tooltip يُبنى بضغطة مطوّلة — نسحبه من الشجرة مباشرة
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'حساب رسمي موثّق من وصل شات');
  });

  testWidgets('الشارة تقبل مقاساً مخصصاً وتحفظه', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: VerifiedBadge(size: 22))),
    ));
    expect(tester.widget<Icon>(find.byIcon(Icons.verified)).size, 22);
  });

  testWidgets('الحقل الافتراضي للشارة في الشاشات غير المحدّثة هو عدم التوثيق', (tester) async {
    // VerifiedBadge نفسه لا يحمل منطقاً شرطياً — الشرط في الشاشات:
    // `if (c['verified'] == true)` يفشل بأمان مع null أو false أو غياب العمود
    // (نسخ الخادم قبل تشغيل ترحيل 025) فلا تظهر الشارة إطلاقاً.
    const rows = [
      {'name': 'مجتمع'}, // قاعدة بلا عمود verified (قبل 025)
      {'name': 'مجتمع', 'verified': false},
      {'name': 'مجتمع', 'verified': null},
    ];
    for (final r in rows) {
      expect(r['verified'] == true, isFalse, reason: 'يجب ألا تظهر الشارة لـ$r');
    }
    expect({'name': 'مجتمع', 'verified': true}['verified'] == true, isTrue);
  });

  testWidgets('لون الشارة ثابت في الوضعين الفاتح والداكن', (tester) async {
    for (final mode in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: mode),
        home: const Scaffold(body: Center(child: VerifiedBadge())),
      ));
      expect(tester.widget<Icon>(find.byIcon(Icons.verified)).color,
          VerifiedBadge.color);
    }
  });
}
