import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass.dart';
import '../../../domain/models/stats.dart';
import '../models/quick_action.dart';
import '../data/quick_actions_repo.dart';

/// 今日页面（首页发射台：问候 + 进度 + 主行动 + 快捷入口）
///
/// 设计约定（2026-08-30 重做，M3 + 液体玻璃）：
/// 1. 单张玻璃 Hero 卡承载问候/连续天数/进度环/三项统计；
/// 2. 页面背景为全局 aurora 光斑（MainShell 注入），Scaffold 透明；
/// 3. 次级文本一律 [ColorScheme.onSurfaceVariant]，不用 alpha 叠加；
/// 4. 字号全部取自 M3 type scale 角色，不手写 fontSize；
/// 5. 进度环是全局唯一一处主动动画，且尊重系统「移除动画」设置。
///    extendBody 布局：列表底部 padding 须避开悬浮玻璃 dock（≈116）。
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('今日'),
        backgroundColor: Colors.transparent,
      ),
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

    return RefreshIndicator(
      onRefresh: () async => _loadData(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 116),
        children: [
          _TodayHero(stats: stats, streak: _streak),
          const SizedBox(height: 14),
          _PrimaryAction(stats: stats),
          const SizedBox(height: 26),
          _QuickActionSection(
            actions: _quickActions,
            onEdit: () async {
              await context.push('/today-quick-actions');
              if (mounted) _loadQuickActions();
            },
          ),
          if (stats.totalWords == 0) ...[
            const SizedBox(height: 28),
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

/// 顶部 Hero：问候 + 连续天数 + 进度环 + 三项统计
class _TodayHero extends StatelessWidget {
  final TodayStats stats;
  final int streak;

  const _TodayHero({required this.stats, required this.streak});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 13) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 23) return '晚上好';
    return '夜深了';
  }

  String _subtitle(int due) {
    if (stats.totalWords == 0) return '词库还是空的，先加几个单词';
    if (due > 0) return '还有 $due 个单词到期';
    if (stats.reviewedToday > 0) return '今天过了 ${stats.reviewedToday} 个，收工';
    return '今天没有到期的单词';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(stats.pendingReviews),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StreakBadge(days: streak),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _ProgressRing(progress: stats.progress),
                const SizedBox(width: 18),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          icon: Icons.fiber_new_outlined,
                          color: cs.primary,
                          value: stats.dueNew,
                          label: '待学新词',
                        ),
                      ),
                      Expanded(
                        child: _HeroStat(
                          icon: Icons.pending_actions_outlined,
                          color: cs.tertiary,
                          value: stats.dueReview,
                          label: '待复习',
                        ),
                      ),
                      Expanded(
                        child: _HeroStat(
                          icon: Icons.check_circle_outline,
                          color: theme.brightness == Brightness.dark
                              ? AppColors.ratingGoodDark
                              : AppColors.ratingGood,
                          value: stats.reviewedToday,
                          label: '今日已学',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }
}

/// 连续学习天数（无容器，减少一层 chrome）
class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.local_fire_department, size: 18, color: cs.primary),
        const SizedBox(width: 4),
        Text(
          '连续 $days',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 2),
        Text(
          '天',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 进度环：整页唯一的主动动画，尊重系统「移除动画」
class _ProgressRing extends StatelessWidget {
  final double progress;
  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: cs.primary,
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
                  Text(
                    '完成度',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Hero 内的单项统计
class _HeroStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;

  const _HeroStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 主行动按钮：图标与文案随状态切换
class _PrimaryAction extends StatelessWidget {
  final TodayStats stats;
  const _PrimaryAction({required this.stats});

  @override
  Widget build(BuildContext context) {
    final due = stats.pendingReviews;
    final hasWords = stats.totalWords > 0;
    final actionable = due > 0;
    final goAdd = !actionable && !hasWords;

    final icon =
        actionable ? Icons.play_arrow : (goAdd ? Icons.add : Icons.check);
    final label = actionable
        ? '开始今日复习 · $due 词'
        : (goAdd ? '添加第一个单词' : '今日任务已完成');

    return SizedBox(
      width: double.infinity,
      child: GlassButton(
        onPressed: actionable
            ? () => context.push('/review')
            : goAdd
                ? () => context.push('/add-word')
                : null,
        icon: icon,
        label: label,
        tinted: true,
      ),
    );
  }
}

/// 快捷入口区块（可自定义，最多 8 个）
class _QuickActionSection extends StatelessWidget {
  final List<QuickAction> actions;
  final VoidCallback onEdit;

  const _QuickActionSection({required this.actions, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '快捷入口',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: Icon(Icons.tune, size: 20, color: cs.onSurfaceVariant),
              tooltip: '自定义快捷入口',
              onPressed: onEdit,
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (actions.isEmpty)
          SizedBox(
            height: 88,
            child: Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('添加快捷入口'),
                onPressed: onEdit,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 92,
            ),
            itemBuilder: (context, index) {
              final action = actions[index];
              return _QuickActionCard(
                icon: action.icon,
                label: action.label,
                color: action.color,
                onTap: () => context.push(action.route),
              );
            },
          ),
      ],
    );
  }
}

/// 快捷入口磁贴：彩色浅底图标容器 + 单行标签
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
    final isDark = theme.brightness == Brightness.dark;
    return GlassContainer(
      onTap: onTap,
      radius: 16,
      blur: 16,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // 深色底上提高着色浓度，保证 22dp 图标 ≥3:1
              color: color.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
