/// خدمة لغة التطبيق (المرحلة 12 ب — 0.29.0): اختيار مستمر ومحفوظ بين
/// العربية (أم التصميم) والإنجليزية والفرنسية الأساسية.
///
/// - القيمة ValueNotifier تقرأها MaterialApp (locale) فتتبدل الواجهة
///   واتجاهها لحظياً بلا إعادة تشغيل — en/fr يساران والعربية يميناً.
/// - الخزن بنمط ThemeService نفسه (مخزن آمن محلي — لا خادم ولا طرف ثالث).
/// - الدوال النقية في l10n.dart تُختبر مباشرة؛ هذه الخدمة طبقة خزن فقط.
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'l10n.dart';

class LocaleService {
  LocaleService._();

  static const _key = 'app_language';
  static const _storage = FlutterSecureStorage();

  /// اللغة الحالية — العربية افتراضياً حتى يختار المستخدم غيرها
  static final ValueNotifier<String> lang = ValueNotifier<String>('ar');

  static Locale get locale => Locale(lang.value);

  static Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      if (v != null && l10nSupported.contains(v)) lang.value = v;
    } catch (_) {
      // تعذر القراءة: تبقى العربية الافتراضية — بلا انهيار ولا ادعاء
    }
  }

  /// اختيار لغة وحفظها — يرفض غير المدعوم بصدق ويعيد false
  static Future<bool> set(String code) async {
    if (!l10nSupported.contains(code)) return false;
    lang.value = code;
    try {
      await _storage.write(key: _key, value: code);
    } catch (_) {}
    return true;
  }
}
