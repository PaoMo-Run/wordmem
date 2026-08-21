import 'package:flutter/material.dart';

/// 筛选栏
class FilterBar extends StatelessWidget {
  final String? stateFilter;
  final String? tagFilter;
  final bool favoriteOnly;
  /// 仅看短文测试错词（分组视图）
  final bool quizOnly;
  final void Function({
    String? stateFilter,
    String? tagFilter,
    bool? favoriteOnly,
    bool? quizOnly,
  }) onChanged;

  const FilterBar({
    super.key,
    this.stateFilter,
    this.tagFilter,
    this.favoriteOnly = false,
    this.quizOnly = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilterChip(
            label: const Text('收藏'),
            selected: favoriteOnly,
            avatar: const Icon(Icons.star, size: 16),
            onSelected: (v) => onChanged(favoriteOnly: v),
          ),
          FilterChip(
            label: const Text('新词'),
            selected: stateFilter == 'new',
            onSelected: (v) =>
                onChanged(stateFilter: v ? 'new' : null),
          ),
          FilterChip(
            label: const Text('学习中'),
            selected: stateFilter == 'learning',
            onSelected: (v) =>
                onChanged(stateFilter: v ? 'learning' : null),
          ),
          FilterChip(
            label: const Text('复习中'),
            selected: stateFilter == 'review',
            onSelected: (v) =>
                onChanged(stateFilter: v ? 'review' : null),
          ),
          FilterChip(
            label: const Text('短文测试'),
            selected: quizOnly,
            avatar: const Icon(Icons.quiz_outlined, size: 16),
            onSelected: (v) => onChanged(quizOnly: v),
          ),
          // 航空专业词（专业版词典 pro_av 词自动打该标签）
          FilterChip(
            label: const Text('航空专业词'),
            selected: tagFilter == '航空专业词',
            avatar: const Icon(Icons.flight_takeoff, size: 16),
            onSelected: (v) =>
                onChanged(tagFilter: v ? '航空专业词' : null),
          ),
        ],
      ),
    );
  }
}
