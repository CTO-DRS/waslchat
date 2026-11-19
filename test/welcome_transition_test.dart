import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/app_studio_service.dart';
import 'package:wasl_chat/theme.dart';

/// 1.13.1: جولة الترحيب لا تظهر لمن كان داخلاً قبل التحديث، وانتقال الصفحات
/// الموحّد يحترم «مستوى الحركة».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('جولة الترحيب', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      WelcomeService.disarm();
      WelcomeService.pendingFor.value = null;
    });

    test('حدث signedIn بلا إجراء دخول صريح (استعادة/تجديد) لا يُظهر الجولة', () async {
      await WelcomeService.onSignedIn('u1');
      expect(WelcomeService.pendingFor.value, isNull);
    });

    test('دخول صريح من شاشة الدخول لحساب جديد يُظهر الجولة مرة واحدة', () async {
      WelcomeService.expectSignIn();
      expect(WelcomeService.armed, isTrue);
      await WelcomeService.onSignedIn('u2');
      expect(WelcomeService.pendingFor.value, 'u2');
      expect(WelcomeService.armed, isFalse);
      await WelcomeService.markSeen();
      expect(WelcomeService.pendingFor.value, isNull);
      expect(await WelcomeService.seenFor('u2'), isTrue);
      // دخول صريح لاحق للحساب نفسه: لا جولة مجدداً
      WelcomeService.expectSignIn();
      await WelcomeService.onSignedIn('u2');
      expect(WelcomeService.pendingFor.value, isNull);
    });

    test('جلسة موجودة عند الفتح تُعلَّم مشاهَدة بصمت', () async {
      expect(await WelcomeService.seenFor('old'), isFalse);
      await WelcomeService.onSessionRestored('old');
      expect(await WelcomeService.seenFor('old'), isTrue);
      expect(WelcomeService.pendingFor.value, isNull);
      // حتى لو حدث دخول صريح لاحقاً لنفس الحساب
      WelcomeService.expectSignIn();
      await WelcomeService.onSignedIn('old');
      expect(WelcomeService.pendingFor.value, isNull);
    });

    test('فشل الدخول يلغي التسليح', () async {
      WelcomeService.expectSignIn();
      WelcomeService.disarm();
      await WelcomeService.onSignedIn('u3');
      expect(WelcomeService.pendingFor.value, isNull);
    });
  });

  group('انتقال الصفحات', () {
    test('الثيم يستخدم الانتقال الموحّد على كل المنصات وبالمدة حسب مستوى الحركة', () {
      for (final m in StudioMotion.values) {
        final t = WaslTheme.build(Brightness.dark, StudioStyle.defaults.copyWith(motion: m));
        final pt = t.pageTransitionsTheme;
        expect(pt, isA<StudioPageTransitions>());
        for (final p in TargetPlatform.values) {
          final b = pt.builders[p];
          expect(b, isA<WaslPageTransitionsBuilder>());
          expect(b!.transitionDuration, WaslPageTransitionsBuilder.durationFor(m));
        }
      }
      expect(WaslPageTransitionsBuilder.durationFor(StudioMotion.full).inMilliseconds, 260);
      expect(WaslPageTransitionsBuilder.durationFor(StudioMotion.off), Duration.zero);
    });

    Future<void> pumpApp(WidgetTester tester, StudioMotion m) async {
      await tester.pumpWidget(MaterialApp(
        theme: WaslTheme.build(Brightness.dark, StudioStyle.defaults.copyWith(motion: m)),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => const Scaffold(body: Text('الصفحة الثانية')))),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pump();
    }

    testWidgets('الحركة المتوقفة: الصفحة تظهر فوراً بلا انتقال', (tester) async {
      await pumpApp(tester, StudioMotion.off);
      await tester.pump();
      expect(find.text('الصفحة الثانية'), findsOneWidget);
      expect(find.text('افتح'), findsNothing); // الصفحة السابقة لم تعد مرسومة
      expect(
          find.ancestor(of: find.text('الصفحة الثانية'), matching: find.byType(SlideTransition)),
          findsNothing);
    });

    testWidgets('الحركة الكاملة: تلاشٍ وانزلاق ينتهيان خلال ~260ms', (tester) async {
      await pumpApp(tester, StudioMotion.full);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('افتح'), findsOneWidget); // أثناء الانتقال
      expect(
          find.ancestor(of: find.text('الصفحة الثانية'), matching: find.byType(SlideTransition)),
          findsWidgets);
      await tester.pump(const Duration(milliseconds: 170));
      await tester.pump();
      expect(find.text('افتح'), findsNothing);
      expect(find.text('الصفحة الثانية'), findsOneWidget);
    });

    testWidgets('الحركة الخفيفة: تلاشٍ فقط بلا انزلاق', (tester) async {
      await pumpApp(tester, StudioMotion.reduced);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
          find.ancestor(of: find.text('الصفحة الثانية'), matching: find.byType(SlideTransition)),
          findsNothing);
      expect(
          find.ancestor(of: find.text('الصفحة الثانية'), matching: find.byType(FadeTransition)),
          findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('افتح'), findsNothing);
    });
  });
}
