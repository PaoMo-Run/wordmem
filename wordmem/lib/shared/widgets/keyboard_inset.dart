import 'package:flutter/material.dart';

/// 键盘遮挡处理（v2.1.8）
///
/// **问题场景**：页面结构为
/// `SingleChildScrollView → ConstrainedBox(minHeight: 视口高) → Center → 卡片`，
/// 卡片里含 `TextField`。软键盘弹出后可视区被压缩，内容高于视口时输入框会落到
/// 折叠线以下，而 `SingleChildScrollView` **不会**自动把输入框滚上来。
///
/// **两层兜底**：
/// 1. [ensureFieldVisible] —— 聚焦后 / 键盘高度变化后，把输入框滚进可视区
///    （必须等键盘动画开始后再算位置，否则目标位置是旧的）；
/// 2. [KeyboardInsetPadding] —— 给滚动内容底部留出键盘高度的余量，
///    让第 1 层「有地方可滚」。
///
/// ⚠️ **实现须知**：`Scaffold` 在 `resizeToAvoidBottomInset: true`（默认）时
/// 会对 body 执行 `MediaQuery.removeViewInsets(removeBottom: true)`，
/// 因此 body 内读到的 `viewInsets.bottom` 恒为 0 —— 此时 [KeyboardInsetPadding]
/// 高度为 0（安全网，不是空转 bug）；**真正的修复来自 [ensureFieldVisible]**，
/// 因为 Scaffold 已把视口底边压到键盘上沿，`ensureVisible` 的目标位置天然在键盘之上。
/// 若某页显式设了 `resizeToAvoidBottomInset: false`，[KeyboardInsetPadding] 才会生效。

/// 当前键盘高度。Scaffold 已处理 inset 的页面里返回 0。
double keyboardInsetBottom(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom;

/// 给滚动内容底部留出键盘等高的可滚动余量（见文件头「实现须知」）。
class KeyboardInsetPadding extends StatelessWidget {
  const KeyboardInsetPadding({super.key, required this.child, this.extra = 0});

  final Widget child;

  /// 额外余量（如希望输入框下方再多留一点呼吸空间）。
  final double extra;

  @override
  Widget build(BuildContext context) {
    final bottom = keyboardInsetBottom(context) + extra;
    if (bottom <= 0) return child;
    return Padding(padding: EdgeInsets.only(bottom: bottom), child: child);
  }
}

/// 把 [fieldContext]（输入框自身或其父）滚到可视区内。
///
/// [alignment] 0 = 顶对齐，1 = 底对齐；0.25 让输入框稳定落在键盘上方约 1/4 屏处。
/// 内部用 `addPostFrameCallback` 兜一层——必须在键盘动画开始之后调用，
/// 否则算出来的目标位置还是键盘弹出前的旧值。
void ensureFieldVisible(BuildContext fieldContext, {double alignment = 0.25}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!fieldContext.mounted) return;
    // 没有可滚动祖先时静默跳过（此时输入框本就在视口内，无需滚动）
    if (Scrollable.maybeOf(fieldContext) == null) return;
    Scrollable.ensureVisible(
      fieldContext,
      alignment: alignment,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  });
}
