import 'package:flutter/material.dart';

/// 应用配色方案（M3 Token 体系）
///
/// 设计原则（2026-08-30 定稿，参考 impeccable Android 准则）：
/// 1. 品牌种子色 [seed] 供 ColorScheme.fromSeed 生成全套 M3 角色，深浅模式自动适配；
/// 2. 关键品牌角色用精修值覆盖（[primary]/[primaryLight] 等），保证 WCAG 对比度；
/// 3. 深色模式 onPrimary 用深色文字（[onPrimaryDark]），修复旧版近白文字对比不足（~2.2:1）问题；
/// 4. 语义色（评分/状态/快捷入口）收敛为 token，页面禁止再写裸色值。
class AppColors {
  AppColors._();

  // ────────────────────────── 品牌种子 ──────────────────────────
  /// M3 ColorScheme 种子色（teal 600，保持既有品牌）
  static const Color seed = Color(0xFF00897B);

  // ────────────────────────── 主色（品牌精修） ──────────────────────────
  /// 浅色模式主色：teal 800（白字对比度 ≈6:1，比旧 00897B 更稳）
  static const Color primary = Color(0xFF006A60);
  /// 深色模式主色：亮青（深底上对比度良好）
  static const Color primaryLight = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF00504A);
  static const Color primaryContainer = Color(0xFFB2DFDB);
  /// 浅色模式 onPrimary：白
  static const Color onPrimary = Color(0xFFFFFFFF);
  /// 深色模式 onPrimary：深青（★ 修复旧版近白文字对比度不足）
  static const Color onPrimaryDark = Color(0xFF00332F);
  static const Color onPrimaryContainer = Color(0xFF003733);

  // ────────────────────────── 次要色 ──────────────────────────
  static const Color secondary = Color(0xFF4A6360);
  static const Color secondaryContainer = Color(0xFFCCE8E4);
  static const Color onSecondaryContainer = Color(0xFF051F1C);

  // ────────────────────────── 评分按钮色（语义 token，深浅各一版） ──────────────────────────
  static const Color ratingAgain = Color(0xFFE53935);      // 红 - 没想起来（浅色）
  static const Color ratingAgainDark = Color(0xFFFF8A80);  // 红（深色模式亮化）
  static const Color ratingHard = Color(0xFFFFA726);       // 琥珀 - 困难（浅色）
  static const Color ratingHardDark = Color(0xFFFFB74D);   // 琥珀（深色模式亮化）
  static const Color ratingGood = Color(0xFF43A047);       // 绿 - 正确（浅色）
  static const Color ratingGoodDark = Color(0xFF81C784);   // 绿（深色模式亮化）
  static const Color ratingEasy = Color(0xFF1E88E5);       // 蓝 - 很轻松（浅色）
  static const Color ratingEasyDark = Color(0xFF64B5F6);   // 蓝（深色模式亮化）

  // ────────────────────────── 亮色主题表面 ──────────────────────────
  static const Color lightBg = Color(0xFFFAFBFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF0F4F3);
  static const Color lightOnBg = Color(0xFF191C1B);
  static const Color lightOnSurface = Color(0xFF191C1B);
  static const Color lightOnSurfaceVariant = Color(0xFF5F6B68); // 次级文本（替代 alpha 叠加）
  static const Color lightOutline = Color(0xFFDDE3E0);

  // ────────────────────────── 暗色主题表面 ──────────────────────────
  static const Color darkBg = Color(0xFF0F1413);
  static const Color darkSurface = Color(0xFF191E1D);
  static const Color darkSurfaceVariant = Color(0xFF232B29);
  static const Color darkOnBg = Color(0xFFE1E3E0);
  static const Color darkOnSurface = Color(0xFFE1E3E0);
  static const Color darkOnSurfaceVariant = Color(0xFFB3BCB9); // 次级文本（深色模式亮灰）
  static const Color darkOutline = Color(0xFF3A4543);

  // ────────────────────────── 功能色 ──────────────────────────
  static const Color error = Color(0xFFBA1A1A);
  static const Color warning = Color(0xFFFFA726);
  static const Color success = Color(0xFF43A047);
  static const Color info = Color(0xFF1E88E5);

  // ────────────────────────── 掌握状态颜色 ──────────────────────────
  static const Color statusNew = Color(0xFF9E9E9E);
  static const Color statusLearning = Color(0xFFFFA726);
  static const Color statusReview = Color(0xFF1E88E5);
  static const Color statusMastered = Color(0xFF43A047);

  // 收藏
  static const Color favorite = Color(0xFFFFC107);

  // ────────────────────────── 背景光斑（aurora 高级材质背景） ──────────────────────────
  /// 光斑色仅供 AppBackground 径向渐变使用，页面禁止直接引用
  static const Color glowCyan = Color(0xFF26A69A);   // 蓝绿（teal 400）
  static const Color glowMint = Color(0xFF80CBC4);   // 薄荷（teal 200）
  static const Color glowIndigo = Color(0xFF7986CB); // 靛蓝（冷色纵深，暗角）
  static const Color glowWarm = Color(0xFFFFB74D);   // 暖琥珀（对向暖点，提氛围）
  static const Color glowViolet = Color(0xFF9575CD); // 紫罗兰（底部暗光）

  // ────────────────────────── 今日快捷入口图标色（收敛为 8 语义 token） ──────────────────────────
  static const Color quickAddWord = Color(0xFF2F7BD6);      // 添加单词（蓝）
  static const Color quickStory = Color(0xFF009F93);        // 今日短文（青绿）
  static const Color quickImport = Color(0xFF7A5CC7);       // 批量导入（紫）
  static const Color quickCustomReview = Color(0xFFE08C00); // 自选复习（琥珀）
  static const Color quickGroupMemory = Color(0xFFD04A9E);  // 词群记忆（玫粉）
  static const Color quickStoryMemory = Color(0xFF0E9E9C);  // 短文记忆库（青）
  static const Color quickLibrary = Color(0xFF5C7280);      // 词库（蓝灰）
  static const Color quickStats = Color(0xFF3C9D6B);        // 统计（绿）
}
