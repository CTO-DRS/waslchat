import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'app_keys.dart';
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
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/security_screens.dart';
import 'services/push_service.dart';
import 'widgets/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // المرحلة 12 ب (0.29.0): قياس الفتح البارد — من أول سطر إلى أول إطار مرسوم
  final coldStart0 = DateTime.now();
  await ThemeService.load();
  await FontScaleService.load();
  await WallpaperService.load();
  await LocaleService.load();
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
          builder: (context, fontScale, _) => MaterialApp(
        title: 'وصل شات',
        debugShowCheckedModeBanner: false,
        theme: WaslTheme.light,
        darkTheme: WaslTheme.dark,
        themeMode: mode,
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
        home: const LockGate(child: AuthGate()),
        // تطبيق حجم الخط المختار على كل النصوص (المظهر ← حجم الخط)
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      ),
      ),
    );
  }
}

/// يعرض شاشة الدخول أو الشاشة الرئيسية حسب حالة تسجيل الدخول
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
        if (session == null) return const AuthScreen();
        final aal = supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        if (aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
            aal.currentLevel != AuthenticatorAssuranceLevels.aal2) {
          return const MfaVerifyScreen();
        }
        return const HomeScreen();
      },
    );
  }
}
