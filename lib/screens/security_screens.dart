import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme.dart';

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Widget _codeField(TextEditingController c) => TextField(
      controller: c,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(hintText: '000000', counterText: ''),
    );

Widget _primary(String text, VoidCallback? onTap, {bool loading = false}) => SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: WaslColors.gradient, borderRadius: BorderRadius.circular(16)),
        child: TextButton(
          onPressed: loading ? null : onTap,
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );

/// إدارة التحقق بخطوتين (تطبيق مصادقة مثل Google Authenticator)
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});
  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  bool _loading = true;
  Factor? _active;
  AuthMFAEnrollResponse? _pending;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await supabase.auth.mfa.listFactors();
      Factor? active;
      for (final f in res.totp) {
        if (f.status == FactorStatus.verified) active = f;
      }
      // احذف أي محاولة تفعيل غير مكتملة
      for (final f in res.all) {
        if (f.status == FactorStatus.unverified) {
          await supabase.auth.mfa.unenroll(f.id);
        }
      }
      _active = active;
    } catch (e) {
      if (mounted) _snack(context, 'تعذّر تحميل الإعدادات');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _enroll() async {
    setState(() => _loading = true);
    try {
      _pending = await supabase.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'Wasl Chat',
        friendlyName: 'وصل شات ${DateTime.now().millisecondsSinceEpoch}',
      );
    } on AuthException catch (e) {
      if (mounted) _snack(context, e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verify() async {
    final p = _pending;
    if (p == null || _code.text.trim().length != 6) return;
    setState(() => _loading = true);
    try {
      await supabase.auth.mfa.challengeAndVerify(factorId: p.id, code: _code.text.trim());
      _pending = null;
      _code.clear();
      if (mounted) _snack(context, 'تم تفعيل التحقق بخطوتين');
      await _load();
      return;
    } on AuthException catch (e) {
      if (mounted) _snack(context, 'الرمز غير صحيح: ${e.message}');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _disable() async {
    final f = _active;
    if (f == null) return;
    setState(() => _loading = true);
    try {
      await supabase.auth.mfa.unenroll(f.id);
      if (mounted) _snack(context, 'تم إيقاف التحقق بخطوتين');
    } on AuthException catch (e) {
      if (mounted) _snack(context, e.message);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق بخطوتين')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              if (_active != null) ...[
                const Icon(Icons.verified_user, size: 64, color: WaslColors.teal),
                const SizedBox(height: 12),
                const Text('التحقق بخطوتين مفعّل',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('سيُطلب منك رمز من تطبيق المصادقة عند كل تسجيل دخول.',
                    textAlign: TextAlign.center, style: TextStyle(color: context.wasl.textFaint)),
                const SizedBox(height: 24),
                OutlinedButton(onPressed: _disable, child: const Text('إيقاف التحقق بخطوتين')),
              ] else if (p == null) ...[
                const Icon(Icons.shield_outlined, size: 64, color: WaslColors.indigo),
                const SizedBox(height: 12),
                const Text('احمِ حسابك بخطوة إضافية',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('تحتاج تطبيق مصادقة مثل Google Authenticator أو Microsoft Authenticator.',
                    textAlign: TextAlign.center, style: TextStyle(color: context.wasl.textFaint)),
                const SizedBox(height: 24),
                _primary('تفعيل', _enroll),
              ] else ...[
                const Text('١. أضف الحساب في تطبيق المصادقة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: p.totp?.uri ?? '', size: 200),
                  ),
                ),
                const SizedBox(height: 12),
                Text('أو انسخ المفتاح وألصقه في التطبيق:', style: TextStyle(color: context.wasl.textFaint)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: p.totp?.secret ?? ''));
                    _snack(context, 'تم نسخ المفتاح');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: context.wasl.glass, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(
                        child: SelectableText(p.totp?.secret ?? '',
                            textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace')),
                      ),
                      const Icon(Icons.copy, size: 18),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('٢. اكتب الرمز المكوّن من 6 أرقام',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _codeField(_code),
                const SizedBox(height: 16),
                _primary('تأكيد', _verify),
              ],
            ]),
    );
  }
}

/// تُعرض عند الدخول إذا كان الحساب مفعّلاً فيه التحقق بخطوتين
class MfaVerifyScreen extends StatefulWidget {
  const MfaVerifyScreen({super.key});
  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) return;
    setState(() => _loading = true);
    try {
      final res = await supabase.auth.mfa.listFactors();
      final f = res.totp.firstWhere((f) => f.status == FactorStatus.verified);
      await supabase.auth.mfa.challengeAndVerify(factorId: f.id, code: _code.text.trim());
    } on AuthException catch (e) {
      if (mounted) _snack(context, 'الرمز غير صحيح: ${e.message}');
    } catch (_) {
      if (mounted) _snack(context, 'تعذّر التحقق');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.lock_person_outlined, size: 72, color: WaslColors.teal),
              const SizedBox(height: 16),
              const Text('رمز التحقق', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('افتح تطبيق المصادقة واكتب الرمز الظاهر لـ «Wasl Chat»',
                  textAlign: TextAlign.center, style: TextStyle(color: context.wasl.textFaint)),
              const SizedBox(height: 24),
              _codeField(_code),
              const SizedBox(height: 20),
              _primary('تحقق', _verify, loading: _loading),
              TextButton(
                onPressed: () => supabase.auth.signOut(),
                child: const Text('تسجيل الخروج'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// تعيين كلمة مرور جديدة بعد فتح رابط الاستعادة
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p1.text.length < 6) return _snack(context, 'كلمة المرور 6 أحرف على الأقل');
    if (_p1.text != _p2.text) return _snack(context, 'كلمتا المرور غير متطابقتين');
    setState(() => _loading = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: _p1.text));
      if (mounted) {
        _snack(context, 'تم تغيير كلمة المرور');
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (mounted) _snack(context, e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كلمة مرور جديدة')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: _p1,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'كلمة المرور الجديدة')),
        const SizedBox(height: 12),
        TextField(
            controller: _p2,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'أعد كتابتها')),
        const SizedBox(height: 20),
        _primary('حفظ', _save, loading: _loading),
      ]),
    );
  }
}

/// يسمح للمستخدم المسجّل بتغيير كلمة المرور من الإعدادات
void openChangePassword(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewPasswordScreen()));
}


