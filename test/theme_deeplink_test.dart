import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_chat/services/deep_link_service.dart';
import 'package:wasl_chat/theme.dart';

/// اختبارات وحدة: خدمة روابط الدعوة + خدمة المظهر (المرحلة 1)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeepLinkService.parseInvite', () {
    test('يربط رابط الدعوة الصحيح رمزاً بالأحرف الكبيرة', () {
      final code = DeepLinkService.parseInvite(
          Uri.parse('app.waslchat://join/ab12cd34ef'));
      expect(code, 'AB12CD34EF');
    });

    test('يرفض مخططات ومضيفات أخرى (callback الدخول مثلها)', () {
      expect(
          DeepLinkService.parseInvite(
              Uri.parse('app.waslchat://login-callback?x=1')),
          isNull);
      expect(
          DeepLinkService.parseInvite(Uri.parse('https://wasl.chat/join/X')),
          isNull);
    });

    test('يرفض رابطاً بلا رمز', () {
      expect(DeepLinkService.parseInvite(Uri.parse('app.waslchat://join')),
          isNull);
      expect(
          DeepLinkService.parseInvite(Uri.parse('app.waslchat://join/  ')),
          isNull);
    });
  });

  group('ThemeService', () {
    test('يجلب الوضع وحجم الخط المحفوظين ويعيد تعيينهما', () async {
      SharedPreferences.setMockInitialValues(
          {'theme_mode': 'light', 'font_scale': 1.15});
      await ThemeService.load();
      expect(ThemeService.mode.value, ThemeMode.light);
      expect(ThemeService.fontScale.value, 1.15);

      // تعيين وضع النظام وحجم كبير
      SharedPreferences.setMockInitialValues({});
      await ThemeService.setMode(ThemeMode.system);
      await ThemeService.setFontScale(1.3);
      final p = await SharedPreferences.getInstance();
      expect(ThemeService.mode.value, ThemeMode.system);
      expect(ThemeService.fontScale.value, 1.3);
      expect(p.getString('theme_mode'), 'system');
      expect(p.getDouble('font_scale'), 1.3);
    });

    test('الافتراضي داكن وحجم عادي عند غياب التخزين', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeService.load();
      expect(ThemeService.mode.value, ThemeMode.dark);
      expect(ThemeService.fontScale.value, 1.0);
    });

    test('اللوحة الفاتحة والداكنة مكتملتان ومختلفتان بالخلفية', () {
      expect(WaslPalette.light.bg, isNot(WaslPalette.dark.bg));
      for (final p in [WaslPalette.light, WaslPalette.dark]) {
        expect(p.textPrimary, isNotNull);
        expect(p.surface, isNotNull);
        expect(p.bubbleMine, isNotNull);
        expect(p.danger, isNotNull);
      }
      // الوضع الداكن مطابق لمظهر ما قبل 0.4.0
      expect(WaslPalette.dark.bg, const Color(0xFF0B0F1A));
      expect(WaslPalette.dark.surface, const Color(0xFF151B2B));
    });
  });
}
