import 'package:flutter/material.dart';

/// 应用配色方案 - Teal 主色调
class AppColors {
  AppColors._();

  // 主色 - Teal
  static const Color primary = Color(0xFF00897B);
  static const Color primaryLight = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF00504A);
  static const Color primaryContainer = Color(0xFFB2DFDB);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF003733);

  // 次要色
  static const Color secondary = Color(0xFF4A6360);
  static const Color secondaryContainer = Color(0xFFCCE8E4);
  static const Color onSecondaryContainer = Color(0xFF051F1C);

  // 评分按钮颜色
  static const Color ratingAgain = Color(0xFFE53935); // 红 - 没想起来
  static const Color ratingHard = Color(0xFFFFA726);  // 琥珀 - 困难
  static const Color ratingGood = Color(0xFF43A047);  // 绿 - 正确
  static const Color ratingEasy = Color(0xFF1E88E5);  // 蓝 - 很轻松

  // 亮色主题
  static const Color lightBg = Color(0xFFFAFBFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF0F4F3);
  static const Color lightOnBg = Color(0xFF191C1B);
  static const Color lightOnSurface = Color(0xFF191C1B);
  static const Color lightOutline = Color(0xFFDDE3E0);

  // 暗色主题
  static const Color darkBg = Color(0xFF0F1413);
  static const Color darkSurface = Color(0xFF191E1D);
  static const Color darkSurfaceVariant = Color(0xFF232B29);
  static const Color darkOnBg = Color(0xFFE1E3E0);
  static const Color darkOnSurface = Color(0xFFE1E3E0);
  static const Color darkOutline = Color(0xFF3A4543);

  // 功能色
  static const Color error = Color(0xFFBA1A1A);
  static const Color warning = Color(0xFFFFA726);
  static const Color success = Color(0xFF43A047);
  static const Color info = Color(0xFF1E88E5);

  // 掌握状态颜色
  static const Color statusNew = Color(0xFF9E9E9E);
  static const Color statusLearning = Color(0xFFFFA726);
  static const Color statusReview = Color(0xFF1E88E5);
  static const Color statusMastered = Color(0xFF43A047);

  // 收藏
  static const Color favorite = Color(0xFFFFC107);
}
