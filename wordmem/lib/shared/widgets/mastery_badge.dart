import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// 熟悉度标签（0~4 级，与单词复习熟悉度一致的表现方式）：
/// 0=未开始(灰) / 1=学习中(橙) / 2~3=熟悉(蓝) / 4=已掌握(绿)
class MasteryBadge extends StatelessWidget {
  final int level;
  const MasteryBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (level) {
      0 => ('未开始', AppColors.statusNew),
      1 => ('学习中', AppColors.statusLearning),
      2 || 3 => ('熟悉', AppColors.statusReview),
      _ => ('已掌握', AppColors.statusMastered),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
