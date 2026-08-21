import 'package:flutter/material.dart';

/// 平板横屏适配：宽屏（> [maxWidth]）时内容居中限宽。
///
/// 解决平板横屏下列表/图表满宽拉伸、阅读体验差的问题：
/// - 手机窄屏：原样返回 [child]
/// - 平板宽屏：居中包裹 [ConstrainedBox(maxWidth)]，行宽保持舒适阅读宽度
class AdaptiveContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AdaptiveContent({
    super.key,
    required this.child,
    this.maxWidth = 640,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) return child;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}
