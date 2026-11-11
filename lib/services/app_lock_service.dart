import 'package:flutter/foundation.dart' show kIsWeb;
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

  static Future<bool> authenticate({String reason = 'افتح وصل شات'}) async {
    if (kIsWeb) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // يسمح برمز قفل الجهاز كبديل للبصمة
          stickyAuth: true,
          useErrorDialogs: true,
        ),
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

  static Future<void> setSecure(bool secure) async {
    if (kIsWeb) return;
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
