import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'app_keys.dart';
import 'services/app_lock_service.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/security_screens.dart';
import 'services/push_service.dart';
import 'widgets/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeService.load();
  await FontScaleService.load();
  await WallpaperService.load();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await PushService.init();
  _initCrashlytics();
  runApp(const WaslApp());
}

/// تقارير الأعطال إلى Firebase Crashlytics (أندرويد فقط).
/// PushService.init يهيّئ Firebase قبله؛ إن فشلت التهيئة (لا خدمات Google) نتجاهل بهدوء.
void _initCrashlytics() {
  if (kIsWeb) return;
  try {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    // Firebase غير مهيّأ — تقارير الأعطال اختيارية ولا يمنع تشغيل التطبيق
  }
}

class WaslApp extends StatelessWidget {
  const WaslApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.mode,
      builder: (context, mode, _) => ValueListenableBuilder<double>(
        valueListenable: FontScaleService.scale,
        builder: (context, fontScale, _) => MaterialApp(
        title: 'وصل شات',
        debugShowCheckedModeBanner: false,
        theme: WaslTheme.light,
        darkTheme: WaslTheme.dark,
        themeMode: mode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
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
