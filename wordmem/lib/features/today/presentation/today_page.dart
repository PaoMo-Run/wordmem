import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/stats.dart';
import 'widgets/today_summary_card.dart';
import 'widgets/today_action_buttons.dart';

/// 今日页面
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('今日')),
      body: dbAsync.when(
        data: (_) => const _TodayContent(),
        loading: () => const LoadingIndicator(message: '正在加载...'),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '初始化失败',
          subtitle: e.toString(),
        ),
      ),
    );
  }
}

class _TodayContent extends ConsumerStatefulWidget {
  const _TodayContent();

  @override
  ConsumerState<_TodayContent> createState() => _TodayContentState();
}

class _TodayContentState extends ConsumerState<_TodayContent> {
  TodayStats? _stats;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      final statsDao = ref.read(statsDaoProvider);
      final reviewDao = ref.read(reviewDaoProvider);
      setState(() {
        _stats = statsDao.getTodayStats();
        _streak = reviewDao.getCurrentStreak();
      });
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听词库版本变化，自动刷新统计数据
    ref.listen(wordListVersionProvider, (_, __) {
      _loadData();
    });

    if (_stats == null) {
      return const LoadingIndicator();
    }

    final stats = _stats!;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => _loadData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 连续学习天数
          if (_streak > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '连续学习 $_streak 天',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // 统计卡片
          TodaySummaryCard(stats: stats),
          const SizedBox(height: 24),

          // 操作按钮
          TodayActionButtons(
            stats: stats,
            onAdd: () => context.push('/add-word'),
            onReview: () => context.push('/review'),
            onCustomReview: () => context.push('/custom-review'),
            onSynonymChallenge: () => context.push('/synonym-challenge'),
            onTextImport: () => context.push('/text-import'),
          ),
          const SizedBox(height: 24),

          // 快捷入口
          if (stats.totalWords == 0)
            EmptyState(
              icon: Icons.menu_book_outlined,
              title: '开始你的词汇之旅',
              subtitle: '添加第一个单词，或从文本中批量导入',
              actionLabel: '添加单词',
              onAction: () => context.push('/add-word'),
            ),
        ],
      ),
    );
  }
}
