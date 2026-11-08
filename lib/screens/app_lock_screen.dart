import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_service.dart';
import '../theme.dart';

/// حوار إعداد/تغيير رمز الـPIN (يُستخدم من الإعدادات عند التفعيل والتغيير).
/// يعيد الرمز عند نجاح الإدخال مرتين متطابقتين، أو null عند الإلغاء.
Future<String?> showPinSetupDialog(BuildContext context) async {
  final c1 = TextEditingController();
  final c2 = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('رمز قفل التطبيق'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c1,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'رمز من 4 إلى 6 أرقام', counterText: ''),
            onChanged: (_) => setState(() => error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c2,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'تأكيد الرمز', counterText: ''),
            onChanged: (_) => setState(() => error = null),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final a = c1.text.trim();
              if (a.length < 4) {
                setState(() => error = 'الرمز 4 أرقام على الأقل');
                return;
              }
              if (a != c2.text.trim()) {
                setState(() => error = 'الرمزان غير متطابقين');
                return;
              }
              Navigator.pop(ctx, a);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

/// شاشة قفل التطبيق: تُعرض فوق كل شيء عند العودة من الخلفية أو فتح التطبيق
/// إذا كان القفل مفعّلاً. الفتح بالبصمة (إن اختيرت) أو برمز الـPIN.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _error;
  bool _busyBiometric = false;
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    // مطالبة البصمة تلقائياً عند ظهور القفل
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric(auto: true));
  }

  Future<void> _tryBiometric({bool auto = false}) async {
    if (_busyBiometric) return;
    if (auto && _autoPrompted) return;
    _autoPrompted = true;
    setState(() => _busyBiometric = true);
    final ok = await AppLockService.verifyBiometric();
    if (!mounted) return;
    setState(() => _busyBiometric = false);
    if (ok) _unlocked();
  }

  void _unlocked() {
    AppLockService.unlock();
    // يُعاد بناء الواجهة عبر LockGate الذي يستمع إلى الخدمة
  }

  void _pressDigit(String d) {
    HapticFeedback.selectionClick();
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length >= 4) _verify();
  }

  Future<void> _verify() async {
    final ok = await AppLockService.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      _unlocked();
    } else {
      setState(() {
        _error = 'رمز غير صحيح، حاول مجدداً';
        _pin = '';
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WaslColors.darkBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    gradient: WaslColors.gradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: Colors.white, size: 34),
                ),
                const SizedBox(height: 16),
                const Text('وصل شات مقفل',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  AppLockService.hasPin
                      ? 'أدخل رمز القفل للمتابعة'
                      : 'افتح بالبصمة أو رمز الجهاز',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 28),
                // نقاط الـPIN
                if (AppLockService.hasPin) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 6; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length
                                ? WaslColors.teal
                                : WaslColors.glass,
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
                const SizedBox(height: 28),
                // لوحة الأرقام
                if (AppLockService.hasPin)
                  _Keypad(onDigit: _pressDigit, onBackspace: () {
                    if (_pin.isEmpty) return;
                    setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  }),
                // البصمة
                if (AppLockService.useBiometric) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: WaslColors.teal),
                    onPressed: _busyBiometric ? null : () => _tryBiometric(),
                    icon: _busyBiometric
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.fingerprint, size: 22),
                    label: const Text('فتح بالبصمة أو رمز الجهاز'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final key in row)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    width: 76,
                    height: 62,
                    child: key.isEmpty
                        ? const SizedBox.expand()
                        : _Key(
                            label: key,
                            onTap: () => key == '⌫'
                                ? onBackspace()
                                : onDigit(key),
                          ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WaslColors.glass,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Center(
          child: label == '⌫'
              ? const Icon(Icons.backspace_outlined, color: Colors.white70)
              : Text(label,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
