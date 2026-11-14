/// أيقونة التطبيق البديلة (المرحلة 8 ب — 0.21.0)
///
/// خياران للمشغّل على أندرويد عبر activity-alias في AndroidManifest:
/// - classic: الأيقونة المعتمدة (الافتراضي)
/// - gradient: البديل المتدرج بألوان وصل
///
/// التبديل عبر قناة أصلية `wasl/appicon` بsetComponentEnabledSetting —
/// النمط الحالي يُحفظ محلياً (على جهازك حصراً). أي فشل يهبط للسلوك
/// السابق: تعذّر التغيير على الجهاز، وبلا تعطيل لأي شيء آخر.
/// الويب وسطح المكتب: غير مدعوم — يعيد false بلا ريمي.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('wasl/appicon');
  static const _storageKey = 'app_icon_variant';
  static const _storage = FlutterSecureStorage();

  static const classic = 'classic';
  static const gradient = 'gradient';

  /// النمط الحالي (محلي على الجهاز — يبدأ بالكلاسيكية)
  static Future<String> current() async {
    try {
      return (await _storage.read(key: _storageKey)) ?? classic;
    } catch (_) {
      return classic;
    }
  }

  /// يبدّل الأيقونة — يعيد true عند النجاح على أندرويد فقط
  static Future<bool> set(String variant) async {
    if (variant != classic && variant != gradient) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('setAlias', {
        'alias': variant == gradient ? 'MainActivityGradient' : 'MainActivityClassic',
      });
      if (ok == true) {
        try {
          await _storage.write(key: _storageKey, value: variant);
        } catch (_) {}
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
