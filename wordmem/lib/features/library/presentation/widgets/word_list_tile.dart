import 'package:flutter/material.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/string_utils.dart';

/// 词库列表项
class WordListTile extends StatelessWidget {
  final Map<String, dynamic> word;
  final VoidCallback onTap;

  const WordListTile({super.key, required this.word, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wordText = word['word'] as String;
    final customDef = word['custom_def'] as String?;
    final note = word['note'] as String? ?? '';
    final tags = word['tags'] as String? ?? '';
    final isFavorite = (word['is_favorite'] as int?) == 1;
    final cardState = word['card_state'] as String? ?? 'new';
    final reps = (word['reps'] as int?) ?? 0;
    final lapses = (word['lapses'] as int?) ?? 0;
    final due = word['due'] as String?;

    final statusColor = masteryColor(cardState, reps, lapses);
    final statusLabel = masteryLabel(cardState, reps, lapses);

    final displayDef = customDef ?? note;
    final dueDate = due != null ? DateTime.tryParse(due) : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 掌握状态指示
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // 单词信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          wordText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isFavorite) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star,
                              size: 14, color: AppColors.favorite),
                        ],
                        const Spacer(),
                        Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    if (displayDef.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        StringUtils.truncate(displayDef, 50),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: tags
                            .split(',')
                            .where((t) => t.trim().isNotEmpty)
                            .take(3)
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    t.trim(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // 下次复习时间
              if (dueDate != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    StringUtils.formatDue(dueDate),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
