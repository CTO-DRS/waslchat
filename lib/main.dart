import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/app_lock_screen.dart';
import 'services/app_lock_service.dart';
import 'services/deep_link_service.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/security_screens.dart';
import 'services/push_service.dart';

void main() {
  // runZonedGuarded: يلتقط الأخطاء غير المتزامنة خارج إطار Flutter (Dart الخام)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    // يهيّئ Firebase إن أمكن — تقارير الأعطال تعتمد على نجاحه وتتخطى الصمت
    await PushService.init();
    // إعدادات قفل التطبيق (يبدأ مقفولاً إن كان مفعّلاً)
    await AppLockService.load();
    // المظهر: الوضع (فاتح/داكن/النظام) وحجم الخط (المرحلة 1)
    await ThemeService.load();
    // روابط دعوة المجموعات app.waslchat://join/CODE
    await DeepLinkService.init();
    _installCrashReporting();
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) _setCrashUser(uid);
    runApp(const LockGate(child: WaslApp()));
  }, (error, stack) {
    _reportCrash(error, stack, fatal: true);
  });
}

/// تقارير الأعطال عبر Firebase Crashlytics (مجاني، بند المرحلة 0 من خارطة الطريق).
/// آمنة تماماً: تُفعَّل على أندرويد/iOS فقط وبعد نجاح تهيئة Firebase، وأي فشل فيها صامت.
void _installCrashReporting() {
  try {
    if (kIsWeb || !PushService.firebaseReady) return;
    if (!(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }
    // أخطاء إطار Flutter (بناء الواجهات، setState...)
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _reportCrash(details.exception, details.stack ?? StackTrace.empty,
          fatal: details.library == null || details.library!.isEmpty);
    };
    // أخطاء غير المتزامنة داخل المنطقة (runZonedGuarded يمسكها)
    PlatformDispatcher.instance.onError = (error, stack) {
      _reportCrash(error, stack, fatal: true);
      return true;
    };
  } catch (_) {}
}

void _reportCrash(Object error, StackTrace stack, {required bool fatal}) {
  try {
    if (kIsWeb || !PushService.firebaseReady) return;
    unawaited(FirebaseCrashlytics.instance
        .recordError(error, stack, fatal: fatal)
        .catchError((_) {}));
  } catch (_) {}
}

/// ربط معرّف المستخدم بالأعطال لتمييز الأعطال التي تصيب مجموعة مستخدمين
void _setCrashUser(String uid) {
  try {
    if (kIsWeb || !PushService.firebaseReady) return;
    FirebaseCrashlytics.instance.setUserIdentifier(uid);
  } catch (_) {}
}

final navigatorKey = GlobalKey<NavigatorState>();

/// بوابة قفل التطبيق: تُغلف التطبيق كله وتعرض شاشة القفل فوقه عند القفل
/// (الخروج للخلفية يقفل فوراً — بند المرحلة 2 من خارطة الطريق)
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) AppLockService.onBackgrounded();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockService.lockState,
      builder: (context, locked, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (locked) const Positioned.fill(child: AppLockScreen()),
        ],
      ),
      child: widget.child,
    );
  }
}

class WaslApp extends StatelessWidget {
  const WaslApp({super.key});

  @override
  Widget build(BuildContext context) {
    // يستمع للوضع وحجم الخط معاً — التغيير من الإعدادات يسري فوراً بلا إعادة تشغيل
    return ListenableBuilder(
      listenable: Listenable.merge([ThemeService.mode, ThemeService.fontScale]),
      builder: (context, _) => MaterialApp(
        title: 'وصل شات',
        debugShowCheckedModeBanner: false,
        theme: WaslTheme.light,
        darkTheme: WaslTheme.dark,
        themeMode: ThemeService.mode.value,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorKey: navigatorKey,
        // تكبير الخط على مستوى التطبيق كله (شاشات ونوافذ حوارية)
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(ThemeService.fontScale.value),
          ),
          child: child!,
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// يعرض شاشة الدخول أو الشاشة الرئيسية حسب حالة تسجيل الدخول
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// ضمان دفع شاشة كلمة المرور الجديدة مرة واحدة لكل حدث استرداد
  /// (الحدث يبقى في البثّ ويُعاد البناء عند أي تغيير في MediaQuery — بلا هذا العلم
  ///  تُدفع الشاشة مراراً فوق نفسها)
  bool _recoveryPushed = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snap) {
        final event = snap.data?.event;
        if (event == AuthChangeEvent.passwordRecovery) {
          if (!_recoveryPushed) {
            _recoveryPushed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              navigatorKey.currentState
                  ?.push(MaterialPageRoute(builder: (_) => const NewPasswordScreen()));
            });
          }
        } else if (event != null) {
          _recoveryPushed = false;
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
