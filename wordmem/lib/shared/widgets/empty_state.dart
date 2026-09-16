import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../domain/models/review_rating.dart';
import 'glass.dart';

/// 空状态组件
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(
                title!,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              GlassButton(
                onPressed: onAction,
                icon: Icons.add,
                label: actionLabel!,
                tinted: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 加载指示器
class LoadingIndicator extends StatelessWidget {
  final String? message;
  const LoadingIndicator({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 熟练度档位颜色（v2.1.6：按 T0–T7 节点映射的 4 档）
///
/// `difficulty` 在未掌握时承载跳过加速态；1 档最浅 → 4 档最深。
Color masteryColor(
  String cardState,
  int reps,
  int lapses, {
  double difficulty = 0,
}) {
  if (cardState == 'mastered') return AppColors.statusMastered;
  final level = MasteryStatus.levelOf(
    reps: reps,
    skipState: difficulty.toInt(),
  );
  return switch (level) {
    1 => AppColors.statusNew,
    2 => AppColors.statusLearning,
    3 => AppColors.statusReview,
    _ => AppColors.statusMastered,
  };
}

/// 熟练度档位文字：小试牛刀 / 初出茅庐 / 炉火纯青 / 登峰造极
String masteryLabel(
  String cardState,
  int reps,
  int lapses, {
  double difficulty = 0,
}) {
  if (cardState == 'mastered') return MasteryStatus.level4.label;
  return MasteryStatus.fromLevel(
    MasteryStatus.levelOf(reps: reps, skipState: difficulty.toInt()),
  ).label;
}
