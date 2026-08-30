import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

/// 应用主题定义（M3 规范化，2026-08-30 重构）
///
/// 设计原则：
/// 1. 用 [AppColors.seed] 生成 M3 全套角色（surfaceContainer 层级、onSurfaceVariant 等自动适配深浅模式）；
/// 2. 关键品牌角色用精修值覆盖（对比度达标）；
/// 3. 深色模式 onPrimary 用深色文字（AppColors.onPrimaryDark）；
/// 4. 卡片用 tonal elevation（浅色 surfaceContainerLow）而非纯白平铺，消除廉价扁平感；
/// 5. 页面禁止再写裸色值，一律通过 theme.colorScheme / AppColors 语义 token。
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // M3 全角色：seed 生成 + 品牌关键角色覆盖
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.primaryLight : AppColors.primary,
      onPrimary: isDark ? AppColors.onPrimaryDark : AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: isDark ? AppColors.secondaryContainer : AppColors.secondary,
      secondaryContainer: isDark ? AppColors.secondary : AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
      onSurfaceVariant: isDark
          ? AppColors.darkOnSurfaceVariant
          : AppColors.lightOnSurfaceVariant,
      outline: isDark ? AppColors.darkOutline : AppColors.lightOutline,
      error: AppColors.error,
    );

    final onBg = isDark ? AppColors.darkOnBg : AppColors.lightOnBg;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final outline = isDark ? AppColors.darkOutline : AppColors.lightOutline;
    // 卡片：浅色模式用 tonal 层级（surfaceContainerLow），深色模式用 surface
    final cardColor =
        isDark ? AppColors.darkSurface : scheme.surfaceContainerLow;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // 背景透明：aurora 由 MaterialApp.builder 的 AppBackground 全局提供
      // （2026-08-31：所有页面含 push 详情页统一玻璃世界，消除黑条白字割裂）
      scaffoldBackgroundColor: Colors.transparent,

      // v8：切页用轻量 FadeForwards（450ms，fade + 轻前推）。
      // `backgroundColor: Colors.transparent` 防止它默认在过渡期铺一层
      // 不透明 `ColorScheme.surface` 盖住 aurora 背景造成闪屏。
      // iOS/macOS 保留 CupertinoPageTransitionsBuilder（原生滑动 + 边缘返回手势）。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:
              FadeForwardsPageTransitionsBuilder(backgroundColor: Colors.transparent),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows:
              FadeForwardsPageTransitionsBuilder(backgroundColor: Colors.transparent),
          TargetPlatform.linux:
              FadeForwardsPageTransitionsBuilder(backgroundColor: Colors.transparent),
        },
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: onBg,
        surfaceTintColor: Colors.transparent,
      ),

      // ── Card（tonal elevation，统一圆角） ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline),
        ),
      ),

      // ── 输入框 ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ── 底部导航 ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer.withValues(alpha: 0.6),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          );
        }),
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.lightSurfaceVariant,
        side: BorderSide(color: outline),
        labelStyle: TextStyle(
          fontSize: 13,
          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkOnBg : AppColors.lightOnBg,
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.darkBg : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // ── BottomSheet ──
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── Divider ──
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),

      // ── Slider ──
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.2),
        thumbColor: scheme.primary,
      ),
    );
  }
}
