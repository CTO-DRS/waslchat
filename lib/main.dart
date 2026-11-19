import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'app_keys.dart';
import 'services/shield_service.dart';
import 'services/app_lock_service.dart';
import 'services/desktop_notify_service.dart';
import 'services/jank_service.dart';
import 'services/link_preview_service.dart';
import 'services/locale_service.dart';
import 'services/media_service.dart';
import 'services/metrics_service.dart';
import 'services/offline_queue_service.dart';
import 'services/pwa_service.dart';
import 'services/web_push_service.dart';
import 'services/app_studio_service.dart';
import 'theme.dart';
import 'screens/welcome_screen.dart';
import 'widgets/wasl_mascot.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/security_screens.dart';
import 'services/push_service.dart';
import 'services/tone_service.dart';
import 'widgets/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // المرحلة 12 ب (0.29.0): قياس الفتح البارد — من أول سطر إلى أول إطار مرسوم
  final coldStart0 = DateTime.now();
  await ThemeService.load();
  await FontScaleService.load();
  await WallpaperService.load();
  // استوديو التطبيق (1.13.0): المظهر المختار + علم جولة الترحيب
  await AppStudioService.load();
  await LocaleService.load();
  await ToneService.load();
  await MetricsService.init();
  // المرحلة 13 أ (1.1.0): قياس السقوط الإطاري وذاكرة الوسائط بسقف معلن —
  // قياس محلي حصراً يعرضه صاحبه في ورقة المؤشرات
  await JankService.init();
  await MediaCacheService.init();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  // المرحلة 13 أ (1.1.0): طابور الإرسال بلا شبكة — بعد تهيئة Supabase
  // لأنه يربط نبضة قناة Realtime كإشارة عودة اتصال ويجرب الإرسال فوراً
  await OfflineQueueService.start();
  await PushService.init();
  await LinkPreviewService.init(); // معاينة الروابط (0.21.0): المفتاح والكاش المحلي
  // المرحلة 12 (0.28.0): انتشار المنصات — إشعارات سطح المكتب الأساسية
  // (تتفرغ بذاتها على الجوال والويب) وتجارب PWA وإشعارات المتصفح على الويب
  // (التنفيذات البديلة بلا عملية على المنصات الأصلية)
  await DesktopNotifyService.init();
  PwaService.init();
  WebPushService.init();
  _initCrashlytics();
  // جولة الترحيب (1.13.0): عند أول تسجيل دخول فعلي لكل حساب على الجهاز
  supabase.auth.onAuthStateChange.listen((st) {
    final uid = st.session?.user.id;
    if (st.event == AuthChangeEvent.signedIn && uid != null) {
      WelcomeService.onSignedIn(uid);
    }
  });
  // نبضة الدقيقة: الوضع التلقائي حسب الوقت وساعة شاشة القفل
  Timer.periodic(const Duration(minutes: 1),
      (_) => AppStudioService.minuteTick.value++);
  // عطل في جزء من الواجهة (نسخة الإصدار): «وصول» حزين بدل شاشة رمادية
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const MascotErrorView();
  }
  runApp(const WaslApp());
  // أول إطار مرسوم = نهاية الفتح البارد (قياس محلي لا يغادر الجهاز)
  WidgetsBinding.instance.endOfFrame.then((_) {
    MetricsService.recordColdStart(
        DateTime.now().difference(coldStart0).inMilliseconds);
  });
}

/// تقارير الأعطال إلى Firebase Crashlytics (أندرويد فقط).
/// PushService.init يهيّئ Firebase قبله؛ إن فشلت التهيئة (لا خدمات Google) نتجاهل بهدوء.
void _initCrashlytics() {
  // المرحلة 12 ب (0.29.0): عدّ الأخطاء محلياً أولاً — مقياس صادق على الجهاز
  // يعمل بلا Firebase ولا شبكة، ثم تقرير Crashlytics لأندرويد كما هو.
  final crashlytics = kIsWeb ? null : _safeCrashlytics();
  FlutterError.onError = (details) {
    MetricsService.recordError();
    if (crashlytics != null) FlutterError.presentError(details);
    crashlytics?.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    MetricsService.recordError();
    crashlytics?.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Crashlytics بعد تهيئة Firebase — null على الويب أو عند فشل التهيئة
/// (تقارير الأعطال اختيارية ولا تمنع تشغيل التطبيق — السلوك القائم كما هو)
FirebaseCrashlytics? _safeCrashlytics() {
  try {
    return FirebaseCrashlytics.instance;
  } catch (_) {
    return null;
  }
}

class WaslApp extends StatelessWidget {
  const WaslApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.mode,
      builder: (context, mode, _) => ValueListenableBuilder<String>(
        valueListenable: LocaleService.lang,
        builder: (context, _, __) => ValueListenableBuilder<double>(
          valueListenable: FontScaleService.scale,
          builder: (context, fontScale, _) => ValueListenableBuilder<StudioStyle>(
            valueListenable: AppStudioService.style,
            builder: (context, studio, _) => ValueListenableBuilder<int>(
              valueListenable: AppStudioService.minuteTick,
              builder: (context, _, __) => MaterialApp(
        title: 'وصل شات',
        debugShowCheckedModeBanner: false,
        // استوديو التطبيق (1.13.0): الثيم يُبنى من اختياراتك
        theme: WaslTheme.build(Brightness.light, studio),
        darkTheme: WaslTheme.build(Brightness.dark, studio),
        // «تلقائي حسب الوقت»: فاتح نهاراً وداكن ليلاً
        themeMode: AppStudioService.effectiveMode(mode, studio, DateTime.now()),
        locale: LocaleService.locale,
        supportedLocales: const [
          Locale('ar'),
          Locale('en'),
          Locale('fr'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorKey: navigatorKey,
        navigatorObservers: [ScreenshotService.routeObserver],
        home: const AuthGate(),
        // تطبيق حجم الخط المختار على كل النصوص (المظهر ← حجم الخط)
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
            // «الحركة متوقفة» في الاستوديو = طلب تقليل الحركة للنظام كله
            disableAnimations: studio.motion == StudioMotion.off
                ? true
                : MediaQuery.of(context).disableAnimations,
          ),
          // شاشة القفل فوق المتصفّح كله (1.13.0) — تغطي أي شاشة مفتوحة
          child: LockGate(
            child: ShieldCaptureCover(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// يعرض شاشة الدخول أو الشاشة الرئيسية حسب حالة تسجيل الدخول.
/// منذ 1.13.0: عند نجاح الدخول تبقى شاشة الدخول لحظة يحتفل فيها «وصول»،
/// ثم تظهر جولة الترحيب إن كان هذا أول دخول للحساب على الجهاز.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _hadSession = supabase.auth.currentSession != null;
  bool _holding = false;

  void _hold() {
    _holding = true;
    authCelebrate.value = true;
    final ms = AppStudioService.motionOn ? 950 : 250;
    Future<void>.delayed(Duration(milliseconds: ms), () {
      authCelebrate.value = false;
      if (mounted) setState(() => _holding = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snap) {
        if (snap.data?.event == AuthChangeEvent.passwordRecovery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigatorKey.currentState
                ?.push(MaterialPageRoute(builder: (_) => const NewPasswordScreen()));
          });
        }
        final session = supabase.auth.currentSession;
        if (session != null && !_hadSession && !_holding) {
          _hadSession = true;
          _hold();
        }
        if (session == null) {
          _hadSession = false;
          return const AuthScreen();
        }
        if (_holding) return const AuthScreen();
        final aal = supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        if (aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
            aal.currentLevel != AuthenticatorAssuranceLevels.aal2) {
          return const MfaVerifyScreen();
        }
        // جولة الترحيب عند أول دخول لهذا الحساب على الجهاز (1.13.0)
        return ValueListenableBuilder<String?>(
          valueListenable: WelcomeService.pendingFor,
          builder: (context, pending, _) => pending == session.user.id
              ? WelcomeScreen(onDone: WelcomeService.markSeen)
              : const HomeScreen(),
        );
      },
    );
  }
}
