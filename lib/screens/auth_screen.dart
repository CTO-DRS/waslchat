import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as ul;

import '../config.dart';
import '../theme.dart';
import '../widgets/wasl_mascot.dart';

/// يحتفل «وصول» لحظة نجاح الدخول (تضبطه AuthGate في main)
final authCelebrate = ValueNotifier<bool>(false);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  bool _showPass = false;
  // «وصول» (1.13.0): ينظر للحقول ويغطي عينيه عند كلمة المرور ويحزن عند الخطأ
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _sad = false;
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _glow.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    for (final f in [_emailFocus, _passFocus]) {
      f.addListener(() => setState(() {}));
    }
    _email.addListener(() {
      if (_emailFocus.hasFocus) setState(() {});
    });
  }

  MascotMood get _mood {
    if (authCelebrate.value) return MascotMood.celebrating;
    if (_sad) return MascotMood.sad;
    if (_passFocus.hasFocus && !_showPass) return MascotMood.shy;
    if (_emailFocus.hasFocus) return MascotMood.curious;
    if (_loading) return MascotMood.thinking;
    return MascotMood.waving;
  }

  void _show(String msg) {
    setState(() => _sad = true);
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _sad = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      _show('أدخل بريداً صحيحاً وكلمة مرور من 6 أحرف على الأقل');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        final username = _username.text.trim();
        if (username.length < 3) {
          _show('اسم المستخدم 3 أحرف على الأقل');
          return;
        }
        TextInput.finishAutofillContext();
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'username': username},
        );
        if (res.session == null) {
          _show('تم إنشاء الحساب. تحقق من بريدك لتفعيله');
        }
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AppConfig.authRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('تعذّر فتح تسجيل الدخول بجوجل');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _show('اكتب بريدك أولاً ثم اضغط «نسيت كلمة المرور»');
      return;
    }
    try {
      await supabase.auth.resetPasswordForEmail(email, redirectTo: AppConfig.authRedirect);
      _show('أرسلنا رابط استعادة كلمة المرور إلى بريدك');
    } on AuthException catch (e) {
      _show(e.message);
    }
  }

  InputDecoration _field(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: context.textFaint),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.glass,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WaslColors.teal, width: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(children: [
        // توهّج خلفي متنفّس: هوية «القوة والذكاء»
        AnimatedBuilder(
          animation: _glow,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_glow.value);
            return Stack(children: [
              Positioned(
                top: -120 + 30 * t,
                right: -80,
                child: _orb(320, WaslColors.indigo, dark ? 0.45 : 0.25),
              ),
              Positioned(
                bottom: -140 + 40 * (1 - t),
                left: -100,
                child: _orb(360, WaslColors.teal, dark ? 0.35 : 0.20),
              ),
            ]);
          },
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Column(children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: authCelebrate,
                      builder: (context, _, __) => WaslMascot(
                        size: 128,
                        mood: _mood,
                        // ينظر نحو موضع المؤشر في حقل البريد أثناء الكتابة
                        look: _emailFocus.hasFocus
                            ? Offset((_email.text.length.clamp(0, 30) / 15.0) - 1, 0.9)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ShaderMask(
                      shaderCallback: (r) => WaslColors.gradient.createShader(r),
                      child: const Text('وصل شات',
                          style: TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    const SizedBox(height: 6),
                    Text('تواصل أذكى. أسرع. أكثر أماناً.',
                        style: TextStyle(
                            color: context.textTertiary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 28),
                    // بطاقة زجاجية للنموذج
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: context.surfaceAlt.withValues(alpha: dark ? 0.72 : 0.92),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: context.hairline.withValues(alpha: 0.6)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 12)),
                        ],
                      ),
                      child: Column(children: [
                        // مبدّل دخول/حساب جديد
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: context.glass, borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            for (final up in [false, true])
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _isSignUp = up),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      gradient: _isSignUp == up ? WaslColors.gradient : null,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(up ? 'حساب جديد' : 'تسجيل الدخول',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: _isSignUp == up
                                                ? Colors.white
                                                : context.textTertiary)),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          child: _isSignUp
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TextField(
                                    controller: _username,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.newUsername],
                                    decoration: _field('اسم المستخدم', Icons.alternate_email),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        TextField(
                          controller: _email,
                          focusNode: _emailFocus,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: _field('البريد الإلكتروني', Icons.mail_outline_rounded),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          focusNode: _passFocus,
                          obscureText: !_showPass,
                          textDirection: TextDirection.ltr,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _loading ? null : _submit(),
                          autofillHints: [
                            _isSignUp ? AutofillHints.newPassword : AutofillHints.password
                          ],
                          decoration: _field('كلمة المرور', Icons.lock_outline_rounded,
                              suffix: IconButton(
                                tooltip: _showPass ? 'إخفاء' : 'إظهار',
                                icon: Icon(
                                    _showPass
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: context.textFaint),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              )),
                        ),
                        if (!_isSignUp)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                                onPressed: _forgot, child: const Text('نسيت كلمة المرور؟')),
                          )
                        else
                          const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: WaslColors.gradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                    color: WaslColors.indigo.withValues(alpha: 0.4),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6)),
                              ],
                            ),
                            child: TextButton(
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : Text(_isSignUp ? 'إنشاء الحساب' : 'دخول',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: Divider(color: context.hairline)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('أو', style: TextStyle(color: context.textFaint)),
                          ),
                          Expanded(child: Divider(color: context.hairline)),
                        ]),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _google,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: context.glass,
                              side: BorderSide(color: context.hairline),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: ShaderMask(
                              shaderCallback: (r) => const LinearGradient(colors: [
                                Color(0xFF4285F4),
                                Color(0xFFEA4335),
                                Color(0xFFFBBC05),
                                Color(0xFF34A853),
                              ]).createShader(r),
                              child: const Text('G',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                            ),
                            label: Text('المتابعة بحساب Google',
                                style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.verified_user_rounded, size: 15, color: context.textFaint),
                      const SizedBox(width: 6),
                      Text('محادثاتك الخاصة مشفّرة بين الطرفين',
                          style: TextStyle(fontSize: 12.5, color: context.textFaint)),
                    ]),
                    TextButton(
                      onPressed: () => ul.launchUrl(Uri.parse('https://waslchat.app/privacy/'),
                          mode: ul.LaunchMode.externalApplication),
                      child: Text('بالمتابعة توافق على الشروط وسياسة الخصوصية',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: context.textTertiary,
                              decoration: TextDecoration.underline)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _orb(double size, Color c, double a) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: a), c.withValues(alpha: 0)]),
          ),
        ),
      );
}
