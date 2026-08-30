import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// 液体玻璃材质组件库（2026-08-30 确立，iOS Liquid Glass 风格）
///
/// 配方（相比初版"磨砂玻璃"的关键升级）：
/// 1. 通透——填充 alpha 显著降低，能看清透出的背景光斑；
/// 2. 折射——blur 24 + 饱和度 1.8（`ImageFilter.compose`），透出色彩更鲜活；
/// 3. 高光——顶部白色高光渐变 + 1px 亮边框（模拟光源在上方）；
/// 4. 悬浮——漫射阴影（blur 32 / offset 0,12）。
///
/// 边界（勿破）：
/// - 玻璃填充/边框/高光属装饰性 alpha，**文本严禁 alpha**，一律走 token；
/// - 深色模式高光减半、填充更透，正文对比度仍须 ≥4.5:1；
/// - BackdropFilter 有渲染开销：每屏玻璃区控制数量，dock 用小胶囊分摊。
/// ─────────────────────────────────────────────────────────────────────────

/// 饱和度提升颜色矩阵（s=1 时为恒等变换）
List<double> _saturateMatrix(double s) => [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
      0, 0, 0, 1, 0,
    ];

/// 液体玻璃容器
///
/// [tint] 传入主色即为 tinted glass（选中态/主 CTA 用），null 为清透玻璃；
/// [onTap] 非空时整体可点（自带涟漪）；
/// [blur] 传 0 时跳过 BackdropFilter（**静态玻璃**）——长列表条目等高频项必须用 0，
/// 否则每条一个 blur 会拖垮滚动性能。
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final VoidCallback? onTap;
  final double blur;
  final bool elevated;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 18,
    this.tint,
    this.onTap,
    this.blur = 24,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final base = tint ?? Colors.white;

    // 单条渐变同时呈现「顶部高光 → 主体 → 底部微光」
    final List<Color> colors;
    final List<double> stops;
    if (tint == null) {
      colors = [
        Colors.white.withValues(alpha: isDark ? 0.12 : 0.30),
        Colors.white.withValues(alpha: isDark ? 0.04 : 0.09),
      ];
      stops = const [0.0, 1.0];
    } else {
      colors = [
        Colors.white.withValues(alpha: isDark ? 0.10 : 0.26),
        base.withValues(alpha: isDark ? 0.24 : 0.22),
        base.withValues(alpha: isDark ? 0.08 : 0.08),
        Colors.white.withValues(alpha: isDark ? 0.03 : 0.07),
      ];
      stops = const [0.0, 0.38, 0.85, 1.0];
    }
    final borderColor = isDark
        ? Colors.white.withValues(alpha: tint != null ? 0.20 : 0.13)
        : Colors.white.withValues(alpha: tint != null ? 0.62 : 0.55);

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: stops,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: padding == EdgeInsets.zero
          ? child
          : Padding(padding: padding, child: child),
    );

    // blur > 0：真·液体玻璃（实时模糊背后内容 + 提饱和）
    // blur == 0：静态玻璃（半透明 + 亮边 + 阴影，无 blur），长列表/高频项用
    if (blur > 0) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            inner: ColorFilter.matrix(_saturateMatrix(1.8)),
          ),
          child: content,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            // elevated=false：轻阴影（长列表条目，避免叠影）
            color: cs.shadow.withValues(
              alpha: !elevated
                  ? (isDark ? 0.15 : 0.04)
                  : (isDark ? 0.35 : 0.10),
            ),
            blurRadius: elevated ? 32 : 12,
            offset: elevated ? const Offset(0, 12) : const Offset(0, 3),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// 玻璃按钮（全部按钮的统一形态）
///
/// [tinted]=true 为主 CTA（primary 调味玻璃 + primary 文字，浅色深青字/深色亮青字）；
/// [tinted]=false 为次级清透玻璃。禁用态自动降为灰调玻璃 + onSurfaceVariant。
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tinted;
  final double height;
  final double radius;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tinted = false,
    this.height = 54,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onPressed != null;
    final fg = !enabled
        ? cs.onSurfaceVariant
        : cs.primary;
    final tint = !enabled
        ? cs.outline
        : (tinted ? cs.primary : null);

    return GlassContainer(
      onTap: onPressed,
      tint: tint,
      radius: radius,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部导航条：5 个独立玻璃胶囊（悬浮 dock，互不相连）
class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<GlassNavDestination> destinations;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _tab(context, i, cs)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i, ColorScheme cs) {
    final d = destinations[i];
    final selected = i == currentIndex;
    final fg = selected ? cs.primary : cs.onSurfaceVariant;

    return GlassContainer(
      onTap: () => onChanged(i),
      radius: 20,
      tint: selected ? cs.primary : null,
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? d.selectedIcon : d.icon,
            size: 22,
            color: fg,
          ),
          const SizedBox(height: 3),
          Text(
            d.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

/// 底部导航条目
class GlassNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const GlassNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 全局高级材质背景：aurora 柔光斑（品牌 teal 系）
///
/// 放在 MainShell 最底层，所有 tab 页共享；玻璃材质依赖它透出光斑。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        ColoredBox(color: isDark ? AppColors.darkBg : AppColors.lightBg),
        _blob(
          Alignment.topLeft,
          420,
          AppColors.seed,
          isDark ? 0.16 : 0.20,
          translation: const Offset(-0.16, -0.14),
        ),
        _blob(
          Alignment.centerRight,
          480,
          AppColors.glowCyan,
          isDark ? 0.10 : 0.15,
          translation: const Offset(0.24, 0.02),
        ),
        _blob(
          Alignment.bottomLeft,
          380,
          AppColors.glowMint,
          isDark ? 0.08 : 0.14,
          translation: const Offset(-0.10, 0.30),
        ),
      ],
    );
  }

  Widget _blob(
    Alignment alignment,
    double size,
    Color color,
    double alpha, {
    Offset translation = Offset.zero,
  }) {
    return Align(
      alignment: alignment,
      child: FractionalTranslation(
        translation: translation,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
