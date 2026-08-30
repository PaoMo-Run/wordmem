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
///
/// ⚠️ 2026-08-31 修复（重大 bug）：
/// 1. onTap 此前未接入任何点击处理 → 全 App 玻璃按钮不可点；
/// 2. Flutter 的 `BackdropFilter` 不参与命中测试（hitTest 恒 false），
///    点击层若在 blur 之下会连带失效 → 交互层必须放在 blur **之上**。
///
/// ⚠️ 2026-08-31 二次修复（尺寸 bug，勿再犯）：
/// **禁止 `Stack(fit: StackFit.expand)`**——它会让 Stack 撑到父约束允许的
/// 最大尺寸（而非内容尺寸），导致每个玻璃元素全屏化（nav dock 5 胶囊铺满
/// 全屏、内容被盖死的根因）。正确结构：**装饰层 `Positioned.fill` 铺满、
/// 内容层（唯一非定位 child）决定容器尺寸**。
///
/// ⚠️ 2026-08-31 三次修复（对齐/点击 bug，勿再犯）：
/// Stack 必须用 **`StackFit.passthrough`**（内容层继承**父级**约束而非 Stack 自身
/// 尺寸）。默认 loose 会让内容层收缩在容器左上角 → nav 胶囊图标/文字左对齐、
/// InkWell 只覆盖内容宽（点按钮空白处无效）的根因。passthrough 下内容层在
/// 紧约束父级（Row>Expanded、ListView 条目）自动撑满容器宽，InkWell 覆盖整个
/// 容器，内部元素再各自居中。
///
/// ⚠️ 2026-08-31 四次修复（实时 blur 冻结，勿再犯）：
/// **列表内/滚动内容之上的玻璃一律 `blur: 0` 静态磨砂**——Flutter 引擎对
/// BackdropFilter 的滚动内容采样滞后（滑动时冻结、到顶/到底才刷新）。
/// 静态磨砂靠「更高填充不透明度 + 亮描边 + 高光 + 阴影」呈现磨砂质感，
/// 背景用**流动光斑动画**提供实时可感知的透出效果。`blur > 0` 仅保留给
/// 背景完全静态的场景（当前 App 无此用法，全静态）。
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
    this.blur = 0,
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
    // 静态磨砂配方（2026-08-31 v5 去灰）：填充不透明度适中（太高会压成灰蒙），
    // 靠「亮描边 + 顶部高光 + 轻阴影」呈现通透磨砂，背景流动色彩透出
    if (tint == null) {
      // v11 退回 v8 的低不透明度：v10 把磨砂层加厚后，远看像脏污的"灰片"，
      // 失去了"玻璃透出背景"的核心质感。回到 v8 参数（dark 0.15/0.06、light 0.40/0.13）。
      // 真正的"叠加/文字突出"在后续重做实时模糊时再处理（v4 文档已记录引擎层无解）。
      colors = [
        Colors.white.withValues(alpha: isDark ? 0.15 : 0.40),
        Colors.white.withValues(alpha: isDark ? 0.06 : 0.13),
      ];
      stops = const [0.0, 1.0];
    } else {
      colors = [
        Colors.white.withValues(alpha: isDark ? 0.12 : 0.34),
        base.withValues(alpha: isDark ? 0.22 : 0.30),
        base.withValues(alpha: isDark ? 0.07 : 0.08),
        Colors.white.withValues(alpha: isDark ? 0.03 : 0.06),
      ];
      stops = const [0.0, 0.38, 0.85, 1.0];
    }
    final borderColor = isDark
        ? Colors.white.withValues(alpha: tint != null ? 0.20 : 0.14)
        : Colors.white.withValues(alpha: tint != null ? 0.62 : 0.55);

    // 内容层（交互）——必须放在 blur 之上，否则 BackdropFilter 的
    // hitTest 恒 false 会让内部 InkWell/GestureDetector 全部失效
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      );
    }

    // 装饰层：blur + saturate + 渐变填充 + 亮边框（仅视觉，不承载交互）
    Widget glassFill = DecoratedBox(
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
    );

    if (blur > 0) {
      // 真·液体玻璃：blur 只包装饰层，内容层叠加在上
      // （v5 起 App 内已无 blur>0 用例，仅保留给静态背景场景）
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(
                alpha: isDark ? 0.25 : 0.06,
              ),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            // passthrough：内容层继承父约束（紧约束下自动撑满容器宽，
            // InkWell 覆盖整个容器；loose 会导致内容收缩在左上角）
            fit: StackFit.passthrough,
            children: [
              // 装饰层铺满容器；内容层（下方 content）决定 Stack 尺寸
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.compose(
                    outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    inner: ColorFilter.matrix(_saturateMatrix(2.0)),
                  ),
                  child: glassFill,
                ),
              ),
              content,
            ],
          ),
        ),
      );
    }

    // 静态玻璃（blur == 0）：无 BackdropFilter，无命中测试问题
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            // elevated=false：轻阴影（长列表条目，避免叠影）
            color: cs.shadow.withValues(
              alpha: !elevated
                  ? (isDark ? 0.12 : 0.03)
                  : (isDark ? 0.25 : 0.06),
            ),
            blurRadius: elevated ? 20 : 10,
            offset: elevated ? const Offset(0, 8) : const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(child: glassFill),
            content,
          ],
        ),
      ),
    );
  }
}

/// 玻璃按钮（全部按钮的统一形态）
///
/// [tinted]=true 为主 CTA（primary 调味玻璃 + primary 文字，浅色深青字/深色亮青字）；
/// [tinted]=false 为次级清透玻璃。禁用态自动降为灰调玻璃 + onSurfaceVariant。
/// [blur] 透传玻璃容器：默认 0（静态磨砂，滚动内容之上必须用 0）。
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tinted;
  final double height;
  final double radius;
  final double blur;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tinted = false,
    this.height = 54,
    this.radius = 18,
    this.blur = 0,
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
      blur: blur,
      // 水平留白：此前 EdgeInsets.zero 导致「按钮宽度 == 文字宽度」，
      // 文案视觉上铺满整颗按钮（如词群记忆「开始测试」）。加 18 左右留白后，
      // 短文案（如「测试」）也能与按钮高度形成协调比例。
      padding: const EdgeInsets.symmetric(horizontal: 18),
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
      // 静态玻璃（blur: 0）：dock 悬浮于滚动内容之上，实时 blur 会被 Flutter
      // 引擎按旧帧采样（滑动时冻结、停下才重渲，体验割裂）→ 用静态玻璃 +
      // 通透填充/描边/阴影，内容从胶囊后滚过仍清晰可见，且无冻结伪影。
      blur: 0,
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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

/// iOS 设置页式玻璃分组卡（静态玻璃，条目贴边满宽）
///
/// 配合 `_SectionHeader` 使用：Header 在上，分组卡包住该组 ListTile；
/// 替代「裸 ListTile + Divider」旧样式（me_page / settings_page 先例）。
class GlassSection extends StatelessWidget {
  final List<Widget> children;

  const GlassSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GlassContainer(
        blur: 0,
        elevated: false,
        radius: 14,
        padding: EdgeInsets.zero,
        child: Column(children: children),
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

/// 全局高级材质背景：**静态** aurora 光斑
/// （品牌 teal 系 + 冷靛纵深 + 暖点提氛围）
///
/// 2026-08-31 v8 最后一搏（用户真机 v7 反馈"关 Impeller 仍无效"后重判）：
/// 旧版光斑直径 520-560 逻辑像素，在 K60 Pro（屏幕逻辑宽 ~480）上**比屏幕还大**——
/// 6 个超大径向渐变 + 各自中心向外渐隐到 0 → 重叠成**均匀平涂**
///（看上去"静态青绿"，实际渲染了但被自己糊成一片）。深色模式 alpha 0.05-0.16
/// 也太低，看不出独立光晕。
///
/// 切页卡顿的另一个根因：旧版每帧 `ValueListenableBuilder` + `Transform` 重建
///（60fps × 节点重建），叠加新页玻璃 rasterize 爆掉帧预算。
///
/// v8 修复：
/// 1. **背景改纯静态**——去除动画（无 ValueListenableBuilder / Transform / 时钟），
///    零后台成本；同时彻底删除空转 60fps 的 AuroraTickerHost；
/// 2. **光斑改小改亮**——直径降到 200-320 逻辑像素（小于屏宽），dark 模式主光斑
///    alpha 0.16→0.40，做出 6 个**独立可辨**的彩色光晕（不再叠成糊）；
/// 3. 切页轻量化：见 app_theme 的 `pageTransitionsTheme`（FadeForwards +
///    透明背景，无 OOM/闪屏）。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 静态底色
        ColoredBox(color: isDark ? AppColors.darkBg : AppColors.lightBg),
        // 静态光斑层（RepaintBoundary 隔离：避免页面内容重绘时牵连背景重光栅化）
        RepaintBoundary(
          child: _AuroraBlobs(isDark: isDark),
        ),
      ],
    );
  }
}

/// 静态 6 光斑：小尺寸 + 高 alpha，确保独立可辨、不再叠成平涂
class _AuroraBlobs extends StatelessWidget {
  final bool isDark;
  const _AuroraBlobs({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: _blobs(isDark),
    );
  }

  List<Widget> _blobs(bool isDark) => [
        // 主锚点：左上 teal（品牌主光，最亮最大）
        _blob(
          Alignment.topLeft,
          320,
          AppColors.seed,
          isDark ? 0.40 : 0.30,
          const Offset(-0.10, -0.10),
        ),
        // 右侧蓝绿（中景光）
        _blob(
          Alignment.centerRight,
          300,
          AppColors.glowCyan,
          isDark ? 0.28 : 0.22,
          const Offset(0.15, 0.00),
        ),
        // 左下薄荷（底光）
        _blob(
          Alignment.bottomLeft,
          260,
          AppColors.glowMint,
          isDark ? 0.22 : 0.18,
          const Offset(-0.05, 0.20),
        ),
        // 右下靛蓝（冷色纵深，压住画面重心）
        _blob(
          Alignment.bottomRight,
          240,
          AppColors.glowIndigo,
          isDark ? 0.20 : 0.14,
          const Offset(0.10, 0.18),
        ),
        // 右上暖琥珀（对向暖点，克制用量）
        _blob(
          Alignment.topRight,
          200,
          AppColors.glowWarm,
          isDark ? 0.16 : 0.10,
          const Offset(0.20, -0.08),
        ),
        // 中下紫罗兰（底部暗光，平滑过渡）
        _blob(
          Alignment.bottomCenter,
          240,
          AppColors.glowViolet,
          isDark ? 0.18 : 0.12,
          const Offset(0.0, 0.25),
        ),
      ];

  /// 三停径向渐变光斑：中心最实 → 中段渐弱 → 外缘透明（比两停过渡更柔和）
  Widget _blob(
    Alignment alignment,
    double size,
    Color color,
    double alpha, [
    Offset translation = Offset.zero,
  ]) {
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
                color.withValues(alpha: alpha * 0.45),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.42, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
