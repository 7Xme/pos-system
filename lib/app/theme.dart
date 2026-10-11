import 'package:flutter/material.dart';

/// ثيم Material 3 مخصص للديسكتوب + اللمس + RTL
/// أزرار ≥ 56px، مسافات 4/8/12/16/24، خط Cairo عربي مدمج (يعمل دون إنترنت)
class AppTheme {
  static const _primary = Color(0xFF1B6B4A); // أخضر مكتبي هادئ
  static const _accent = Color(0xFFF2A007); // كهرماني للتنبيهات/الإجمالي
  static const _danger = Color(0xFFC0392B);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        primary: _primary,
        secondary: _accent,
        error: _danger,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Cairo'),
      scaffoldBackgroundColor: const Color(0xFFF6F4EE),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      // أزرار لمس كبيرة — لا تعتمد على Hover
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(120, 56),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 60),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(100, 56),
          textStyle: const TextStyle(fontSize: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  // Tokens موحدة
  static const double touchButtonHeight = 60;
  static const double touchIconSize = 28;
  static const EdgeInsets pagePadding = EdgeInsets.all(16);
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXL = 24;
}
