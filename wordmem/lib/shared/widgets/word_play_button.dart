import 'package:flutter/material.dart';

/// 单词发音播放按钮（喇叭图标）。
///
/// 视觉规范仿 GlassButton：取色走 colorScheme、深浅模式自适应；
/// `onPressed == null` 时不渲染（开关关闭时由调用方传 null 隐藏）。
class WordPlayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;

  const WordPlayButton({
    super.key,
    required this.onPressed,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.volume_up_outlined),
      iconSize: size * 0.55,
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      color: cs.primary,
      tooltip: '播放发音',
    );
  }
}
