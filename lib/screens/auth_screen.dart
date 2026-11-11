import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  void _show(String msg) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: WaslColors.gradient,
                  ),
                  alignment: Alignment.center,
                  child: const Text('و',
                      style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(height: 16),
                const Text('وصل شات',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('تواصل بلا حدود', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 32),
                if (_isSignUp) ...[
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                        hintText: 'اسم المستخدم', prefixIcon: Icon(Icons.alternate_email)),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      hintText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      hintText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline)),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: WaslColors.gradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isSignUp ? 'إنشاء حساب' : 'تسجيل الدخول',
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                if (!_isSignUp)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(onPressed: _forgot, child: const Text('نسيت كلمة المرور؟')),
                  ),
                const SizedBox(height: 4),
                Row(children: const [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('أو', style: TextStyle(color: Colors.white54)),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _google,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: const Text('G',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    label: const Text('المتابعة باستخدام Google',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp ? 'لديك حساب؟ سجّل الدخول' : 'ليس لديك حساب؟ أنشئ واحداً'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
