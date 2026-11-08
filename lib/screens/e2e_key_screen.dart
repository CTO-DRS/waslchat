import 'package:flutter/material.dart';

import '../services/e2e_service.dart';
import '../theme.dart';

/// إدارة مفتاح التشفير: إنشاء نسخة احتياطية، أو استعادتها على جهاز جديد، أو إنشاء مفتاح جديد.
class E2eKeyScreen extends StatefulWidget {
  const E2eKeyScreen({super.key, required this.state});
  final E2eKeyState state;

  @override
  State<E2eKeyScreen> createState() => _E2eKeyScreenState();
}

enum _Mode { backup, restore, reset }

class _E2eKeyScreenState extends State<E2eKeyScreen> {
  late _Mode _mode;
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _ack = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = switch (widget.state) {
      E2eKeyState.needsRestore => _Mode.restore,
      E2eKeyState.needsReset => _Mode.reset,
      _ => _Mode.backup,
    };
  }

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  String? _validateNew() {
    final a = _p1.text;
    if (a.length < 8) return 'كلمة السر 8 أحرف على الأقل';
    if (!RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(a) || !RegExp(r'[0-9]').hasMatch(a)) {
      return 'استخدم حروفاً وأرقاماً معاً';
    }
    if (a != _p2.text) return 'كلمتا السر غير متطابقتين';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_mode != _Mode.restore) {
      final err = _validateNew();
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      if (!_ack) {
        setState(() => _error = 'يجب التأكيد أولاً أنك حفظت كلمة السر في مكان آمن');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      switch (_mode) {
        case _Mode.backup:
          await E2eService.createBackup(_p1.text);
          break;
        case _Mode.restore:
          final ok = await E2eService.restoreBackup(_p1.text);
          if (!ok) {
            setState(() => _error = 'كلمة السر غير صحيحة');
            return;
          }
          break;
        case _Mode.reset:
          await E2eService.resetKeys(_p1.text);
          break;
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'تعذّر الإكمال، تحقق من الاتصال وحاول مجدداً');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, body, button) = switch (_mode) {
      _Mode.backup => (
          'احفظ مفتاح التشفير',
          'اختر كلمة سر لحفظ نسخة مشفّرة من مفتاحك. تحتاجها لقراءة رسائلك المشفّرة على جوال جديد أو بعد إعادة التثبيت. لا نستطيع استرجاعها لك إن نسيتها.',
          'حفظ النسخة الاحتياطية'
        ),
      _Mode.restore => (
          'استعادة مفتاح التشفير',
          'حسابك له مفتاح تشفير محفوظ. أدخل كلمة سر النسخة الاحتياطية لقراءة رسائلك المشفّرة على هذا الجهاز.',
          'استعادة'
        ),
      _Mode.reset => (
          'مفتاح تشفير جديد',
          'سيُنشأ مفتاح جديد لهذا الحساب. الرسائل المشفّرة السابقة لن تُقرأ، وسيظهر لمن تراسلهم تنبيه بتغيّر رمز الأمان. اختر كلمة سر لحفظ المفتاح الجديد.',
          'إنشاء مفتاح جديد'
        ),
    };
    final newPass = _mode != _Mode.restore;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(_mode == _Mode.reset ? Icons.warning_amber_rounded : Icons.lock_outline,
              size: 56, color: _mode == _Mode.reset ? Colors.amber : WaslColors.teal),
          const SizedBox(height: 16),
          Text(body, style: const TextStyle(fontSize: 15, height: 1.6)),
          const SizedBox(height: 20),
          TextField(
            controller: _p1,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: 'كلمة سر النسخة الاحتياطية',
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (newPass) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _p2,
              obscureText: _hide,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة السر'),
            ),
          ],
          if (newPass) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                    SizedBox(width: 8),
                    Text('لا تُسترجع هذه الكلمة أبداً',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'وصل شات لا يعرف كلمة السر ولا يستطيع إرسالها لك أو إعادة تعيينها. إن نسيتها فلن تقرأ رسائلك المشفّرة على جوال جديد أو بعد إعادة تثبيت التطبيق، بلا استثناء. اكتبها الآن على ورقة واحفظها في مكان آمن، أو في مدير كلمات مرور.',
                    style: TextStyle(fontSize: 14, height: 1.7),
                  ),
                  CheckboxListTile(
                    value: _ack,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _ack = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: WaslColors.teal,
                    title: const Text('أفهم ذلك — حفظت الكلمة في مكان آمن',
                        style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_busy || (newPass && !_ack)) ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(button),
          ),
          const SizedBox(height: 8),
          if (_mode == _Mode.restore)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _mode = _Mode.reset;
                        _error = null;
                        _p1.clear();
                        _ack = false;
                      }),
              child: const Text('نسيت كلمة السر؟ إنشاء مفتاح جديد'),
            ),
          if (_mode == _Mode.backup)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('لاحقاً'),
            ),
        ],
      ),
    );
  }
}

/// يفحص المفاتيح ويفتح الشاشة المناسبة إن لزم. يُستدعى بعد الدخول ومن الإعدادات.
Future<void> checkE2eKeys(BuildContext context, {bool fromSettings = false}) async {
  final state = await E2eService.checkKeys();
  if (!context.mounted) return;
  if (state == E2eKeyState.error) {
    if (fromSettings) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر فحص مفتاح التشفير')));
    }
    return;
  }
  if (state == E2eKeyState.ready && !fromSettings) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => E2eKeyScreen(state: state),
  ));
}
