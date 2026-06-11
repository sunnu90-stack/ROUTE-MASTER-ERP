import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Available themes ──────────────────────────────────────────
enum AppThemeType {
  cleanMaterial,    // Default — light and clean
  deepForestGlass,  // Dark green with frosted glass
  northernLights,   // Navy to emerald gradient
  wildBerry,        // Purple to pink gradient
}

// ── Persist theme across app restarts ────────────────────────
class ThemeNotifier extends StateNotifier<AppThemeType> {
  ThemeNotifier() : super(AppThemeType.cleanMaterial) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('rm_app_theme') ?? 'cleanMaterial';
    state = AppThemeType.values.firstWhere(
      (t) => t.name == saved,
      orElse: () => AppThemeType.cleanMaterial,
    );
  }

  Future<void> setTheme(AppThemeType theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rm_app_theme', theme.name);
  }
}

final appThemeProvider = StateNotifierProvider<ThemeNotifier, AppThemeType>(
  (ref) => ThemeNotifier(),
);

// ── Theme configuration model ─────────────────────────────────
class AppThemeConfig {
  final List<Color> backgroundGradient;
  final Color cardColor;
  final Color borderColor;
  final Color highlightColor;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final bool isGlass;
  final double shadowOpacity;
  final String displayName;
  final String emoji;

  const AppThemeConfig({
    required this.backgroundGradient,
    required this.cardColor,
    required this.borderColor,
    required this.highlightColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.isGlass,
    required this.shadowOpacity,
    required this.displayName,
    required this.emoji,
  });
}

// ── Helper that returns the right config per theme ────────────
class ThemeHelper {
  static AppThemeConfig getConfig(AppThemeType type) {
    switch (type) {
      case AppThemeType.cleanMaterial:
        return const AppThemeConfig(
          backgroundGradient: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          cardColor: Colors.white,
          borderColor: Color(0xFFE2E8F0),
          highlightColor: Color(0xFF0EA5E9),
          primaryTextColor: Color(0xFF0F172A),
          secondaryTextColor: Color(0xFF64748B),
          isGlass: false,
          shadowOpacity: 0.05,
          displayName: 'Clean Light',
          emoji: '☀️',
        );

      case AppThemeType.deepForestGlass:
        return AppThemeConfig(
          backgroundGradient: const [Color(0xFF064E3B), Color(0xFF022C22)],
          cardColor: Colors.white.withOpacity(0.08),
          borderColor: Colors.white.withOpacity(0.2),
          highlightColor: const Color(0xFF34D399),
          primaryTextColor: Colors.white,
          secondaryTextColor: Colors.white70,
          isGlass: true,
          shadowOpacity: 0.0,
          displayName: 'Deep Forest',
          emoji: '🌲',
        );

      case AppThemeType.northernLights:
        return const AppThemeConfig(
          backgroundGradient: [Color(0xFF0F172A), Color(0xFF059669), Color(0xFF34D399)],
          cardColor: Colors.white,
          borderColor: Colors.transparent,
          highlightColor: Color(0xFF059669),
          primaryTextColor: Color(0xFF1E293B),
          secondaryTextColor: Color(0xFF64748B),
          isGlass: false,
          shadowOpacity: 0.15,
          displayName: 'Northern Lights',
          emoji: '🌌',
        );

      case AppThemeType.wildBerry:
        return const AppThemeConfig(
          backgroundGradient: [Color(0xFF4C1D95), Color(0xFFBE185D), Color(0xFFF43F5E)],
          cardColor: Colors.white,
          borderColor: Colors.transparent,
          highlightColor: Color(0xFFBE185D),
          primaryTextColor: Color(0xFF1E293B),
          secondaryTextColor: Color(0xFF64748B),
          isGlass: false,
          shadowOpacity: 0.15,
          displayName: 'Wild Berry',
          emoji: '🍇',
        );
    }
  }
}
