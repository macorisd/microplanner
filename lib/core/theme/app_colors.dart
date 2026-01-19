import 'package:flutter/material.dart';

/// Cashew-inspired color palette for MicroPlanner
/// Soft, muted tones with gentle contrast for a friendly, minimalist feel
class AppColors {
  AppColors._();

  // ─────────────────────────────────────────────────────────────────────────
  // Background & Surface
  // ─────────────────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF5F5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F0F2);

  // ─────────────────────────────────────────────────────────────────────────
  // Primary Accent (sage mint - grayish mint green)
  // ─────────────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6FA89F);
  static const Color primaryLight = Color(0xFFE4EFED);
  static const Color primaryDark = Color(0xFF5A8D84);

  // ─────────────────────────────────────────────────────────────────────────
  // Task Priority Colors (pastel versions)
  // ─────────────────────────────────────────────────────────────────────────
  static const Color priorityHigh = Color(0xFFF4A4A4);
  static const Color priorityHighLight = Color(0xFFFDF0F0);
  static const Color priorityMedium = Color(0xFFF5CFA3);
  static const Color priorityMediumLight = Color(0xFFFDF8F0);
  static const Color priorityLow = Color(0xFFA3E8B8);
  static const Color priorityLowLight = Color(0xFFF0FDF4);

  // ─────────────────────────────────────────────────────────────────────────
  // Column Header Colors (softer pastels)
  // ─────────────────────────────────────────────────────────────────────────
  static const Color completeHeader = Color(0xFF8DD4A0);
  static const Color completeHeaderLight = Color(0xFFF0FDF4);
  static const Color lateHeader = Color(0xFFF5D68A);
  static const Color lateHeaderLight = Color(0xFFFEF9E7);
  static const Color upcomingHeader = Color(0xFF8BB8E8);
  static const Color upcomingHeaderLight = Color(0xFFF0F6FD);

  // ─────────────────────────────────────────────────────────────────────────
  // Text Colors
  // ─────────────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF3D4156);
  static const Color textSecondary = Color(0xFF9094A6);
  static const Color textTertiary = Color(0xFFB8BCC8);

  // ─────────────────────────────────────────────────────────────────────────
  // Sidebar
  // ─────────────────────────────────────────────────────────────────────────
  static const Color sidebarBackground = Color(0xFFF0F0F3);
  static const Color sidebarItemActive = Color(0xFFE1EBE9);
  static const Color sidebarItemHover = Color(0xFFEAEAED);

  // ─────────────────────────────────────────────────────────────────────────
  // Other
  // ─────────────────────────────────────────────────────────────────────────
  static const Color divider = Color(0xFFE8E8EB);
  static const Color shadow = Color(0x08000000);
  static const Color error = Color(0xFFE8A3A3);
  static const Color success = Color(0xFF8DD4A0);

  // ─────────────────────────────────────────────────────────────────────────
  // Subject Palette (15-20 pastel options)
  // ─────────────────────────────────────────────────────────────────────────
  static const List<Color> subjectColors = [
    Color(0xFFE57373), // Red
    Color(0xFFF06292), // Pink
    Color(0xFFBA68C8), // Purple
    Color(0xFF9575CD), // Deep Purple
    Color(0xFF7986CB), // Indigo
    Color(0xFF64B5F6), // Blue
    Color(0xFF4FC3F7), // Light Blue
    Color(0xFF4DD0E1), // Cyan
    Color(0xFF4DB6AC), // Teal
    Color(0xFF81C784), // Green
    Color(0xFFAED581), // Light Green
    Color(0xFFDCE775), // Lime
    Color(0xFFFFF176), // Yellow
    Color(0xFFFFD54F), // Amber
    Color(0xFFFFB74D), // Orange
    Color(0xFFFF8A65), // Deep Orange
    Color(0xFFA1887F), // Brown
    Color(0xFF90A4AE), // Blue Grey
    Color(0xFFB0BEC5), // Slate
    Color(0xFFCFD8DC), // Cool Grey
  ];
}
