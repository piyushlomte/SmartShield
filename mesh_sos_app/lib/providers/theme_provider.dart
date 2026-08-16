import 'package:flutter/material.dart';

enum AppThemeMode {
  cyberDark,
  trailAmoled,
  tacticalLight
}

class ThemeProvider with ChangeNotifier {
  AppThemeMode _currentMode = AppThemeMode.cyberDark;

  AppThemeMode get currentMode => _currentMode;

  bool get isTrailMode => _currentMode == AppThemeMode.trailAmoled;

  void setThemeMode(AppThemeMode mode) {
    _currentMode = mode;
    notifyListeners();
  }

  void toggleTrailMode() {
    if (_currentMode == AppThemeMode.trailAmoled) {
      _currentMode = AppThemeMode.cyberDark;
    } else {
      _currentMode = AppThemeMode.trailAmoled;
    }
    notifyListeners();
  }

  ThemeData get themeData {
    switch (_currentMode) {
      case AppThemeMode.trailAmoled:
        // Pure black for maximum battery savings on OLED screens
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          cardColor: const Color(0xFF101010),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9800), // High-visibility Amber
            secondary: Color(0xFF00E676), // Neon Green
            surface: Color(0xFF0A0A0A),
            error: Color(0xFFFF1744),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            elevation: 0,
          ),
        );

      case AppThemeMode.tacticalLight:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F6F9),
          cardColor: Colors.white,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF00796B),
            secondary: Color(0xFFFF6D00),
            surface: Colors.white,
            error: Color(0xFFD50000),
          ),
        );

      case AppThemeMode.cyberDark:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          cardColor: const Color(0xFF161B22),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF2F81F7),
            secondary: Color(0xFF3FB950),
            surface: Color(0xFF161B22),
            error: Color(0xFFF85149),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0D1117),
            elevation: 0,
          ),
        );
    }
  }
}
