/// أيقونة التطبيق البديلة (المرحلة 8 ب — 0.21.0، موسّعة 1.13.0)
///
/// ستة خيارات للمشغّل على أندرويد عبر activity-alias في AndroidManifest:
/// الكلاسيكية (الافتراضي)، المتدرجة، الداكنة، الفاتحة، الذهبية، النيون.
///
/// التبديل عبر قناة أصلية `wasl/appicon` بsetComponentEnabledSetting:
/// يُفعَّل المطلوب ويُعطَّل الباقي دفعة واحدة. النمط الحالي يُحفظ محلياً
/// (على جهازك حصراً). أي فشل يهبط للسلوك السابق: تعذّر التغيير على الجهاز،
/// وبلا تعطيل لأي شيء آخر. الويب وسطح المكتب: غير مدعوم — يعيد false.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خيار أيقونة: المعرّف، الاسم العربي، اسم اللقب في الـManifest، ولونا المعاينة
class AppIconVariant {
  const AppIconVariant(this.id, this.label, this.alias, this.preview);
  final String id;
  final String label;
  final String alias;

  /// لونا المعاينة داخل التطبيق (خلفية، فقاعة)
  final (int, int) preview;

  /// صورة الأيقونة الحقيقية داخل التطبيق (نسخة من أصول المشغّل)
  String get asset => 'assets/app_icons/$id.png';
}

class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('wasl/appicon');
  static const _storageKey = 'app_icon_variant';
  static const _storage = FlutterSecureStorage();

  static const classic = 'classic';
  static const gradient = 'gradient';
  static const dark = 'dark';
  static const light = 'light';
  static const gold = 'gold';
  static const neon = 'neon';

  static const variants = <AppIconVariant>[
    AppIconVariant(classic, 'الكلاسيكية', 'MainActivityClassic', (0xFF0B1220, 0xFF3B82F6)),
    AppIconVariant(gradient, 'المتدرجة', 'MainActivityGradient', (0xFF6366F1, 0xFFFFFFFF)),
    AppIconVariant(dark, 'الداكنة', 'MainActivityDark', (0xFF06080E, 0xFF3B82F6)),
    AppIconVariant(light, 'الفاتحة', 'MainActivityLight', (0xFFF6F8FD, 0xFF3B82F6)),
    AppIconVariant(gold, 'الذهبية', 'MainActivityGold', (0xFF2B1F08, 0xFFF59E0B)),
    AppIconVariant(neon, 'النيون', 'MainActivityNeon', (0xFF1A0629, 0xFFE040FB)),
  ];

  static AppIconVariant byId(String id) =>
      variants.firstWhere((v) => v.id == id, orElse: () => variants.first);

  /// النمط الحالي (محلي على الجهاز — يبدأ بالكلاسيكية)
  static Future<String> current() async {
    try {
      final v = (await _storage.read(key: _storageKey)) ?? classic;
      return variants.any((x) => x.id == v) ? v : classic;
    } catch (_) {
      return classic;
    }
  }

  /// يبدّل الأيقونة — يعيد true عند النجاح على أندرويد فقط
  static Future<bool> set(String variant) async {
    if (!variants.any((v) => v.id == variant)) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('setAlias', {
        'alias': byId(variant).alias,
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
