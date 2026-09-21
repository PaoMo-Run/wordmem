import 'package:flutter/material.dart';

/// 筛选栏（v2.1.7 压缩版：最多两排）
///
/// 改版原因：原先 收藏/新词/学习中/复习中/短文测试/航空专业词/排序 七个元素平铺，
/// 窄屏上占掉三排首屏。
///
/// 本次调整（用户 2026-09-18 指定）：
/// - **下线** 新词 / 学习中 / 复习中 三个状态芯片
/// - 排序菜单收敛为 4 项（按添加时间 / 按到期时间 / 按上次复习时间 / 按字母），**方向从菜单里移除**
/// - 升降序改为**同一排最右侧的上下箭头状态图标**，点击即切换
///
/// 回调改为「每个控件一个专用回调」：原先是单张 map 回调 + `?? 默认值` 合并，
/// 导致点任意一个芯片都会把其它筛选重置回默认（点收藏会把排序重置成按添加时间）。
/// 本次一并修掉——箭头切换方向时不会再意外重置排序类型。
class FilterBar extends StatelessWidget {
  final String? tagFilter;
  final bool favoriteOnly;
  /// 仅看短文测试错词（分组视图）
  final bool quizOnly;
  /// 排序方式：'created' 添加时间 / 'due' 到期时间 / 'word' 字母
  final String sortBy;
  /// 当前是否升序（决定箭头图标方向）
  final bool sortAsc;

  final ValueChanged<bool> onFavoriteOnlyChanged;
  final ValueChanged<bool> onQuizOnlyChanged;
  final ValueChanged<String?> onTagFilterChanged;
  final ValueChanged<String> onSortByChanged;
  final VoidCallback onSortDirToggled;

  const FilterBar({
    super.key,
    this.tagFilter,
    this.favoriteOnly = false,
    this.quizOnly = false,
    this.sortBy = 'created',
    this.sortAsc = false,
    required this.onFavoriteOnlyChanged,
    required this.onQuizOnlyChanged,
    required this.onTagFilterChanged,
    required this.onSortByChanged,
    required this.onSortDirToggled,
  });

  String get _sortLabel => switch (sortBy) {
        'due' => '按到期时间',
        'lastReview' => '按上次复习',
        'word' => '按字母',
        _ => '按添加时间',
      };

  /// 方向在当前排序类型下的具体含义（箭头图标无法自解释，放进 tooltip）
  String get _dirHint => switch (sortBy) {
        'due' => sortAsc ? '近 → 远' : '远 → 近',
        'lastReview' => sortAsc ? '久 → 近' : '近 → 久',
        'word' => sortAsc ? 'A → Z' : 'Z → A',
        _ => sortAsc ? '旧 → 新' : '新 → 旧',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('收藏'),
                  selected: favoriteOnly,
                  avatar: const Icon(Icons.star, size: 16),
                  onSelected: onFavoriteOnlyChanged,
                ),
                // 仅看短文测试错词
                FilterChip(
                  label: const Text('短文测试'),
                  selected: quizOnly,
                  avatar: const Icon(Icons.quiz_outlined, size: 16),
                  onSelected: onQuizOnlyChanged,
                ),
                // 航空专业词（专业版词典 pro_av 词自动打该标签）
                FilterChip(
                  label: const Text('航空专业词'),
                  selected: tagFilter == '航空专业词',
                  avatar: const Icon(Icons.flight_takeoff, size: 16),
                  onSelected: (v) =>
                      onTagFilterChanged(v ? '航空专业词' : null),
                ),
                PopupMenuButton<String>(
                  tooltip: '排序方式',
                  initialValue: sortBy,
                  onSelected: onSortByChanged,
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'created', child: Text('按添加时间')),
                    PopupMenuItem(value: 'due', child: Text('按到期时间')),
                    PopupMenuItem(value: 'lastReview', child: Text('按上次复习时间')),
                    PopupMenuItem(value: 'word', child: Text('按字母')),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.sort, size: 16),
                    label: Text(_sortLabel),
                  ),
                ),
              ],
            ),
          ),
          // 升/降序：同一排最右侧的状态图标，点击切换
          IconButton(
            onPressed: onSortDirToggled,
            tooltip: '切换升/降序（当前 $_dirHint）',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
