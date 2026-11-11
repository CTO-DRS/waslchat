import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WaslColors {
  static const indigo = Color(0xFF6366F1);
  static const teal = Color(0xFF14B8A6);
  static const violet = Color(0xFFA855F7);
  static const darkBg = Color(0xFF0B0F1A);
  static const darkSurface = Color(0xFF151B2B);
  static const glass = Color(0x14FFFFFF);

  static const gradient = LinearGradient(
    colors: [indigo, teal],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
}

class WaslTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: WaslColors.indigo,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: WaslColors.darkBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: WaslColors.glass,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: WaslColors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF2F4FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0x0F6366F1), // نيلة خفيفة تعمل على الفاتح
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

/// وضع المظهر (داكن/فاتح/النظام) مع حفظه محلياً — الوضع الفاتح تجريبي:
/// بعض الشاشات ما زالت محسّنة للداكن (انظر خارطة الطريق).
class ThemeService {
  static const _key = 'theme_mode';
  static const _storage = FlutterSecureStorage();
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      mode.value = switch (v) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    } catch (_) {}
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final v = switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
        _ => 'dark',
      };
      await _storage.write(key: _key, value: v);
    } catch (_) {}
  }
}
