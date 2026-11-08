import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// قفل التطبيق (بند المرحلة 2 من خارطة الطريق):
/// رمز PIN إلزامي (4-6 أرقام، مخزّن هاشاً بـPBKDF2-SHA256 ولا يُحفظ صريحاً أبداً)
/// + بصمة/رمز جهاز اختيارية عبر local_auth كطريق مختصر فوق الـPIN.
/// القفل يُفعَّل عند الخروج من التطبيق للخلفية، وعند فتحه من جديد.
class AppLockService {
  static const _storage = FlutterSecureStorage();
  static final LocalAuthentication _auth = LocalAuthentication();

  static const _kEnabled = 'app_lock.enabled';
  static const _kPinRecord = 'app_lock.pin'; // "salt:hash" hex
  static const _kBiometric = 'app_lock.biometric';

  static bool enabled = false;
  static bool useBiometric = false;
  static bool _hasPin = false;

  /// حالة القفل كـValueNotifier حتى يعيد LockGate البناء عند الفتح
  static final ValueNotifier<bool> lockState = ValueNotifier<bool>(false);

  static bool get locked => lockState.value;
  static bool get hasPin => _hasPin;

  /// قراءة الإعدادات عند بدء التطبيق — يبدأ مقفولاً إن كان مفعّلاً
  static Future<void> load() async {
    try {
      enabled = (await _storage.read(key: _kEnabled)) == '1';
      useBiometric = (await _storage.read(key: _kBiometric)) == '1';
      _hasPin = await _storage.containsKey(key: _kPinRecord);
      lockState.value = enabled; // يبدأ مقفولاً إن كان مفعّلاً
      // تحقق من دعم البصمة على هذا الجهاز (قد يختلف بين الأجهزة)
      if (useBiometric && !await biometricAvailable()) useBiometric = false;
    } catch (_) {
      enabled = false;
      lockState.value = false;
    }
  }

  // ---------- التفعيل من الإعدادات ----------

  static Future<void> _write(String key, String value) =>
      _storage.write(key: key, value: value);

  /// تفعيل القفل مع رمز PIN جديد (إلزامي كطريق احتياطي حتى لا يُقفل المستخدم خارجاً)
  static Future<void> enable(String pin) async {
    await setPin(pin);
    enabled = true;
    lockState.value = false; // ضبطه الآن لا يقفل فوراً
    await _write(_kEnabled, '1');
  }

  static Future<void> disable() async {
    enabled = false;
    lockState.value = false;
    useBiometric = false;
    await _storage.delete(key: _kEnabled);
    await _storage.delete(key: _kBiometric);
    await _storage.delete(key: _kPinRecord);
    _hasPin = false;
  }

  static Future<void> setBiometric(bool v) async {
    useBiometric = v;
    await _write(_kBiometric, v ? '1' : '0');
  }

  /// تعيين/تغيير رمز الـPIN
  static Future<void> setPin(String pin) async {
    final salt = _randomBytes(16);
    final hash = await hashPin(pin, salt);
    await _write(_kPinRecord, '${_hex(salt)}:${_hex(hash)}');
    _hasPin = true;
  }

  static Future<bool> verifyPin(String pin) async {
    try {
      final rec = await _storage.read(key: _kPinRecord);
      if (rec == null) return false;
      return await checkPinRecord(pin, rec);
    } catch (_) {
      return false;
    }
  }

  /// دالة نقية قابلة للاختبار: فحص رمز مقابل سجل "salt:hash" hex
  static Future<bool> checkPinRecord(String pin, String record) async {
    try {
      final parts = record.split(':');
      if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return false;
      final salt = _fromHex(parts[0]);
      final hash = await hashPin(pin, salt);
      return _hex(hash) == parts[1];
    } catch (_) {
      return false;
    }
  }

  /// محاولة البصمة/رمز الجهاز
  static Future<bool> verifyBiometric() async {
    try {
      if (kIsWeb) return false;
      if (!useBiometric || !await biometricAvailable()) return false;
      return await _auth.authenticate(
        localizedReason: 'افتح وصل شات بالبصمة أو رمز الجهاز',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> biometricAvailable() async {
    try {
      if (kIsWeb) return false;
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return (can || supported);
    } catch (_) {
      return false;
    }
  }

  // ---------- دورة الحياة ----------

  /// الخروج للخلفية يقفل فوراً (الخصوصية أولاً)
  static void onBackgrounded() {
    if (enabled) lockState.value = true;
  }

  static void unlock() {
    lockState.value = false;
  }

  // ---------- تجزئة الـPIN (دوال نقية — قابلة للاختبار) ----------

  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  /// SHA-256-PBKDF2 (100 ألف دورة) — يعيد 32 بايت
  static Future<Uint8List> hashPin(String pin, List<int> salt) async {
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode('wasl-lock:$pin')),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _fromHex(String s) {
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
