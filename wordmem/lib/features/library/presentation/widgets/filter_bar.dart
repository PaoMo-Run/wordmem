import 'package:flutter/material.dart';

/// 筛选栏
class FilterBar extends StatelessWidget {
  final String? stateFilter;
  final String? tagFilter;
  final bool favoriteOnly;
  final void Function({
    String? stateFilter,
    String? tagFilter,
    bool? favoriteOnly,
  }) onChanged;

  const FilterBar({
    super.key,
    this.stateFilter,
    this.tagFilter,
    this.favoriteOnly = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            label: const Text('收藏'),
            selected: favoriteOnly,
            avatar: const Icon(Icons.star, size: 16),
            onSelected: (v) => onChanged(favoriteOnly: v),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('新词'),
            selected: stateFilter == 'new',
            onSelected: (v) =>
                onChanged(stateFilter: v ? 'new' : null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('学习中'),
            selected: stateFilter == 'learning',
            onSelected: (v) =>
                onChanged(stateFilter: v ? 'learning' : null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('复习中'),
            selected: stateFilter == 'review',
            onSelected: (v) =>
                onChanged(stateFilter: v ? 'review' : null),
          ),
        ],
      ),
    );
  }
}
