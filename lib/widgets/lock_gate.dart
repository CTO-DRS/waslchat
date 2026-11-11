import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';

/// بوابة قفل التطبيق: إذا كان القفل مفعّلاً تُحجب الواجهة وتُطلب البصمة
/// عند فتح التطبيق وعند العودة إليه من الخلفية.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _locked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.isEnabled().then((v) {
      if (!mounted) return;
      setState(() => _enabled = v);
      if (v) _lock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_enabled) return;
    if (_locked) {
      if (!_authenticating) _authenticate(); // إعادة محاولة تلقائية بعد العودة
    } else {
      _lock();
    }
  }

  void _lock() {
    if (_authenticating || _locked) return;
    setState(() => _locked = true);
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final ok = await AppLockService.authenticate();
    if (mounted) {
      setState(() {
        _authenticating = false;
        if (ok) _locked = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return _LockScreen(busy: _authenticating, onRetry: _authenticate);
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.busy, required this.onRetry});

  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x226366F1),
            ),
            child: const Icon(Icons.lock_rounded, size: 44, color: Colors.white70),
          ),
          const SizedBox(height: 18),
          const Text('وصل شات مقفل',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('افتح بالبصمة أو رمز قفل الجهاز',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: busy ? null : onRetry,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fingerprint_rounded),
            label: Text(busy ? 'بانتظار التحقق…' : 'فتح'),
          ),
        ]),
      ),
    );
  }
}
