import 'package:flutter/material.dart';
import '../../../../domain/models/stats.dart';

/// 今日操作按钮
class TodayActionButtons extends StatelessWidget {
  final TodayStats stats;
  final VoidCallback onAdd;
  final VoidCallback onReview;
  final VoidCallback onCustomReview;
  final VoidCallback onSynonymChallenge;
  final VoidCallback onTextImport;

  const TodayActionButtons({
    super.key,
    required this.stats,
    required this.onAdd,
    required this.onReview,
    required this.onCustomReview,
    required this.onSynonymChallenge,
    required this.onTextImport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 添加单词
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加单词'),
          ),
        ),
        const SizedBox(height: 12),
        // 今日复习（FSRS 算法）
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: stats.pendingReviews > 0 || stats.newWordsToday > 0
                ? onReview
                : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(stats.pendingReviews > 0
                ? '今日复习 (${stats.pendingReviews} 个待复习)'
                : '今日复习'),
          ),
        ),
        const SizedBox(height: 12),
        // 自选复习（按日期筛选，不影响算法）
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: stats.totalWords > 0 ? onCustomReview : null,
            icon: const Icon(Icons.school_outlined),
            label: const Text('自选复习'),
          ),
        ),
        const SizedBox(height: 12),
        // 近义词挑战
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: stats.totalWords > 0 ? onSynonymChallenge : null,
            icon: const Icon(Icons.hub_outlined),
            label: const Text('近义词挑战'),
          ),
        ),
        const SizedBox(height: 12),
        // 文本导入
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onTextImport,
            icon: const Icon(Icons.text_snippet_outlined),
            label: const Text('从文本批量导入'),
          ),
        ),
      ],
    );
  }
}
