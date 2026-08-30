import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/stats.dart';
import '../models/quick_action.dart';
import '../data/quick_actions_repo.dart';

/// 今日页面（B 方案精简版：问候 + 进度环 + 主行动 + 快捷入口）
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
  List<QuickAction> _quickActions = [];
  final _quickRepo = QuickActionsRepo();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadQuickActions();
  }

  Future<void> _loadQuickActions() async {
    final ids = await _quickRepo.load();
    if (mounted) {
      setState(() => _quickActions = _quickRepo.resolve(ids));
    }
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
    final todo = stats.pendingReviews + stats.newWordsToday;

    return RefreshIndicator(
      onRefresh: () async => _loadData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 问候卡
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '早上好 👋',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '连续学习 $_streak 天 · 今日目标 ${stats.totalTasks} 词',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$todo',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 进度环卡
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _ProgressRing(progress: stats.progress),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('今日任务',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        _TaskLine(
                            icon: Icons.fiber_new_outlined,
                            color: theme.colorScheme.primary,
                            text: '新词 ${stats.newWordsToday}'),
                        const SizedBox(height: 4),
                        _TaskLine(
                            icon: Icons.pending_actions_outlined,
                            color: theme.colorScheme.tertiary,
                            text: '待复习 ${stats.pendingReviews}'),
                        const SizedBox(height: 4),
                        _TaskLine(
                            icon: Icons.check_circle_outline,
                            color: theme.brightness == Brightness.dark
                                ? AppColors.ratingGoodDark
                                : AppColors.ratingGood,
                            text: '已复习 ${stats.reviewedToday}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 主行动：开始今日复习
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: todo > 0
                  ? () => context.push('/review')
                  : stats.totalWords == 0
                      ? () => context.push('/add-word')
                      : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(todo > 0
                  ? '开始今日复习 ($todo)'
                  : stats.totalWords == 0
                      ? '先添加第一个单词'
                      : '今日任务已完成，休息一下'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 快捷入口（可自定义，最多 8 个）
          Row(
            children: [
              Text('快捷入口', style: theme.textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: '自定义快捷入口',
                onPressed: () async {
                  await context.push('/today-quick-actions');
                  _loadQuickActions();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_quickActions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('添加快捷入口'),
                  onPressed: () async {
                    await context.push('/today-quick-actions');
                    _loadQuickActions();
                  },
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _quickActions
                  .map((a) => SizedBox(
                        width: (MediaQuery.of(context).size.width - 32 - 20) / 3,
                        child: _QuickActionCard(
                          icon: a.icon,
                          label: a.label,
                          color: a.color,
                          onTap: () => context.push(a.route),
                        ),
                      ))
                  .toList(),
            ),

          // 空词库引导
          if (stats.totalWords == 0) ...[
            const SizedBox(height: 20),
            EmptyState(
              icon: Icons.menu_book_outlined,
              title: '开始你的词汇之旅',
              subtitle: '添加第一个单词，或从文本中批量导入',
              actionLabel: '添加单词',
              onAction: () => context.push('/add-word'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double progress;
  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 7,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('完成度',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5))),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _TaskLine(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              // 图标带彩色浅底，提升质感（避免裸图标廉价感）
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
