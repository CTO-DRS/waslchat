import 'package:flutter/material.dart';

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
      );
}
