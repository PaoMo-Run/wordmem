import 'package:flutter/material.dart';

/// 筛选栏
class FilterBar extends StatelessWidget {
  final String? stateFilter;
  final String? tagFilter;
  final bool favoriteOnly;
  /// 仅看短文测试错词（分组视图）
  final bool quizOnly;
  /// 排序方式（v2.1.6）：'created' 添加时间 / 'due' 到期时间 / 'word' 字母
  final String? sortBy;
  final void Function({
    String? stateFilter,
    String? tagFilter,
    bool? favoriteOnly,
    bool? quizOnly,
    String? sortBy,
  }) onChanged;

  const FilterBar({
    super.key,
    this.stateFilter,
    this.tagFilter,
    this.favoriteOnly = false,
    this.quizOnly = false,
    this.sortBy,
    required this.onChanged,
  });

  String _sortLabel(String? s) => switch (s) {
        'due' => '按到期时间',
        'word' => '按字母',
        _ => '按添加时间',
      };

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
          // 排序方式（v2.1.6：新增「按到期时间」）
          PopupMenuButton<String>(
            tooltip: '排序方式',
            initialValue: sortBy ?? 'created',
            onSelected: (v) => onChanged(sortBy: v),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'created', child: Text('按添加时间（新→旧）')),
              PopupMenuItem(value: 'due', child: Text('按到期时间（近→远）')),
              PopupMenuItem(value: 'word', child: Text('按字母 A→Z')),
            ],
            child: Chip(
              avatar: const Icon(Icons.sort, size: 16),
              label: Text(_sortLabel(sortBy)),
            ),
          ),
        ],
      ),
    );
  }
}
