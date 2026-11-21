import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show ModalRoute, RouteObserver;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// قفل التطبيق بالبصمة/رمز قفل الجهاز + منع لقطات الشاشة (المرحلة 2).
/// يعمل على تطبيق الجوال فقط؛ على الويب تُعاد قيم آمنة بلا فعل.
class AppLockService {
  static const _enabledKey = 'app_lock_enabled';
  static const _storage = FlutterSecureStorage();
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    try {
      return await _storage.read(key: _enabledKey) == '1';
    } catch (_) {
      return false;
    }
  }

  /// يفعّل القفل بعد التحقق الحيوي للتأكيد. يعيد رسالة خطأ أو null عند النجاح.
  static Future<String?> setEnabled(bool value) async {
    if (kIsWeb) return 'القفل يعمل على تطبيق الجوال فقط';
    if (value) {
      try {
        final can = await _auth.canCheckBiometrics;
        final supported = await _auth.isDeviceSupported();
        if ((!can && !supported)) {
          return 'لا توجد بصمة أو قفل جهاز مسجّل على هذا الهاتف';
        }
        final ok = await authenticate(reason: 'تأكيد تفعيل قفل التطبيق');
        if (!ok) return 'فشل التحقق — لم يُفعَّل القفل';
      } catch (_) {
        return 'تعذّر تشغيل التحقق الحيوي على هذا الجهاز';
      }
    }
    try {
      await _storage.write(key: _enabledKey, value: value ? '1' : '0');
    } catch (_) {
      return 'تعذّر حفظ الإعداد';
    }
    return null;
  }

  // ---------- رمز PIN خاص بالتطبيق (1.13.0) ----------
  // يُحفظ مُملَّحاً ومُجزّأً (SHA-256) فقط — لا يُحفظ الرمز نفسه أبداً.
  static const _pinKey = 'app_lock_pin_v1';
  static int _wrong = 0;
  static DateTime? _cooldownUntil;

  static Future<String> hashPin(String pin, List<int> salt) async {
    final h = await Sha256().hash([...salt, ...utf8.encode(pin)]);
    return base64Encode(h.bytes);
  }

  /// رمز صالح: 4 إلى 6 أرقام
  static bool validPin(String pin) => RegExp(r'^[0-9]{4,6}$').hasMatch(pin);

  static Future<bool> hasPin() async {
    try {
      return (await _storage.read(key: _pinKey)) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setPin(String pin) async {
    if (!validPin(pin)) return false;
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final h = await hashPin(pin, salt);
    try {
      await _storage.write(key: _pinKey, value: '${base64Encode(salt)}:$h');
      await _storage.write(key: '${_pinKey}_len', value: '${pin.length}');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// طول الرمز المحفوظ (4 افتراضياً) — للتحقق مرة واحدة عند اكتماله
  static Future<int> pinLength() async {
    try {
      return int.tryParse(await _storage.read(key: '${_pinKey}_len') ?? '') ?? 4;
    } catch (_) {
      return 4;
    }
  }

  static Future<void> removePin() async {
    try {
      await _storage.delete(key: '${_pinKey}_len');
      await _storage.delete(key: _pinKey);
    } catch (_) {}
  }

  /// ثوانٍ متبقية من مهلة المحاولات الخاطئة (0 = مسموح)
  static int get cooldownSeconds {
    final u = _cooldownUntil;
    if (u == null) return 0;
    final left = u.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  /// يتحقق من الرمز. بعد 5 محاولات خاطئة مهلة 30 ثانية.
  static Future<bool> checkPin(String pin) async {
    if (cooldownSeconds > 0) return false;
    String? raw;
    try {
      raw = await _storage.read(key: _pinKey);
    } catch (_) {}
    if (raw == null) return false;
    final ok = await verifyStored(raw, pin);
    if (ok) {
      _wrong = 0;
    } else if (++_wrong >= 5) {
      _wrong = 0;
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return ok;
  }

  @visibleForTesting
  static Future<bool> verifyStored(String raw, String pin) async {
    final i = raw.indexOf(':');
    if (i <= 0) return false;
    try {
      final salt = base64Decode(raw.substring(0, i));
      return await hashPin(pin, salt) == raw.substring(i + 1);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'افتح وصل شات'}) async {
    if (kIsWeb) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // يسمح برمز قفل الجهاز كبديل للبصمة
        // local_auth 3.0: stickyAuth صار persistAcrossBackgrounding،
        // وuseErrorDialogs حُذفت من الواجهة (v3 يفترضها false)
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// منع لقطات الشاشة (FLAG_SECURE على أندرويد) لكل محادثة على حدة.
class ScreenshotService {
  static const _channel = MethodChannel('wasl/secure');
  static const _storage = FlutterSecureStorage();

  /// مراقب المسارات لإعادة تطبيق العلم عند العودة من شاشة أخرى
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  /// Wasl Shield: حماية الشاشات الحساسة مفعّلة على مستوى التطبيق — لا تُرفع بإغلاق محادثة
  static bool globalSecure = false;

  static Future<void> setSecure(bool secure) async {
    if (kIsWeb) return;
    secure = secure || globalSecure;
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } on PlatformException {
      // منصة بلا قناة (iOS قبل إضافتها): تجاهل
    } on MissingPluginException {
      // الويب أو بيئة اختبار: تجاهل
    }
  }

  static String _key(String conversationId) => 'noshot_$conversationId';

  static Future<bool> flagOf(String conversationId) async {
    if (kIsWeb) return false;
    try {
      return await _storage.read(key: _key(conversationId)) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setFlag(String conversationId, bool value) async {
    if (kIsWeb) return;
    try {
      await _storage.write(
          key: _key(conversationId), value: value ? '1' : '0');
    } catch (_) {}
  }
}
