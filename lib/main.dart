import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/security_screens.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await PushService.init();
  runApp(const WaslApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class WaslApp extends StatelessWidget {
  const WaslApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'وصل شات',
      debugShowCheckedModeBanner: false,
      theme: WaslTheme.light,
      darkTheme: WaslTheme.dark,
      themeMode: ThemeMode.dark,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: navigatorKey,
      home: const AuthGate(),
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
