import 'package:flutter/material.dart';

/// Extension لإضافة ألوان success و warning بطريقة نظيفة
extension CustomColorScheme on ColorScheme {
  Color get success => brightness == Brightness.light ? Colors.green : Colors.green[300]!;
  Color get warning => brightness == Brightness.light ? Colors.orange : Colors.orange[300]!;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primarySwatch: Colors.indigo,
      brightness: Brightness.light,
      fontFamily: 'Cairo',
      colorScheme: ColorScheme.light(
        primary: Colors.indigo,
        primaryContainer: Colors.indigo[100],
        secondary: Colors.blue,
        secondaryContainer: Colors.blue[100],
        error: Colors.red,
        errorContainer: Colors.red[100],
        surface: Colors.white,
        onSurface: Colors.black87,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      // ✅ تم التصحيح: TabBarThemeData بدلاً من TabBarTheme
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
        ),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 2.0, color: Colors.indigo),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 2,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      useMaterial3: false,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      primarySwatch: Colors.indigo,
      brightness: Brightness.dark,
      fontFamily: 'Cairo',
      colorScheme: ColorScheme.dark(
        primary: Colors.indigo[300]!,
        primaryContainer: Colors.indigo[800],
        secondary: Colors.blue[300]!,
        secondaryContainer: Colors.blue[800],
        error: Colors.red[300]!,
        errorContainer: Colors.red[800],
        surface: Colors.grey[850]!,
        onSurface: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      // ✅ تم التصحيح هنا أيضاً
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
        ),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 2.0, color: Colors.indigo),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 2,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[700]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[700]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
        ),
      ),
      useMaterial3: false,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}