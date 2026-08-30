import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/stats.dart';

/// 复习中心（底部导航第 2 个 tab）
/// 今日复习（FSRS 大卡）+ 自由练习（自选复习 / 词群记忆）+ 本周复习量
///
/// 设计约定（2026-08-30 重做，M3 + 玻璃质感）：
/// 1. 页面背景为品牌色系淡渐变，卡片用「毛玻璃」材质（半透明 surface + blur + 细边框 + 柔和阴影）。
///    玻璃容器用装饰性 alpha（允许），文本一律走 token（禁止 alpha 叠加文本）；
/// 2. 任务量口径与今日页一致：`dueReview` 待复习 / `dueNew` 待学新词（`pendingCount` 旧口径含重复计算，已弃用）；
/// 3. 自由练习两卡复用快捷入口语义色（quickCustomReview / quickGroupMemory），跨页配色协调；
/// 4. 字号全部取自 M3 type scale 角色，不手写 fontSize；
/// 5. 次级文本一律 onSurfaceVariant。
class ReviewCenterPage extends ConsumerStatefulWidget {
  const ReviewCenterPage({super.key});

  @override
  ConsumerState<ReviewCenterPage> createState() => _ReviewCenterPageState();
}

class _ReviewCenterPageState extends ConsumerState<ReviewCenterPage> {
  TodayStats? _stats;
  List<DailyRecord> _daily = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final statsDao = ref.read(statsDaoProvider);
      setState(() {
        _stats = statsDao.getTodayStats();
        _daily = statsDao.getDailyRecords(7);
      });
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // 监听词库版本变化，自动刷新（评分页 /review 提交后 bump，返回即刷新）
    ref.listen(wordListVersionProvider, (_, __) => _load());

    if (_stats == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('复习中心')),
        body: const LoadingIndicator(),
      );
    }

    final stats = _stats!;
    final due = stats.dueNew + stats.dueReview;
    final hasWords = stats.totalWords > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('复习中心')),
      body: Stack(
        children: [
          // 品牌色系淡渐变背景（玻璃材质赖以透出的底层，纯 token 派生）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55],
                  colors: [
                    cs.primaryContainer.withValues(alpha: isDark ? 0.16 : 0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: () async => _load(),
            child: AdaptiveContent(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _TodayHeroCard(stats: stats),
                  const SizedBox(height: 12),
                  _PrimaryAction(
                    actionable: due > 0,
                    due: due,
                    goAdd: !hasWords,
                  ),
                  const SizedBox(height: 26),
                  if (!hasWords) ...[
                    EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: '开始你的词汇之旅',
                      subtitle: '添加第一个单词，或从文本中批量导入',
                      actionLabel: '添加单词',
                      onAction: () => context.push('/add-word'),
                    ),
                    const SizedBox(height: 26),
                  ],
                  Text(
                    '自由练习',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PracticeCard(
                          icon: Icons.calendar_month_outlined,
                          title: '自选复习',
                          desc: '按日期筛选，不影响算法',
                          color: AppColors.quickCustomReview,
                          onTap: () => context.push('/custom-review'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PracticeCard(
                          icon: Icons.hub_outlined,
                          title: '词群记忆',
                          desc: '近义词 + 词根分组测试',
                          color: AppColors.quickGroupMemory,
                          onTap: () => context.push('/word-group-memory'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '本周复习量',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _GlassCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: _WeeklyBarChart(daily: _daily),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 毛玻璃卡片：半透明表面 + blur + 细边框 + 柔和阴影
/// 半透明仅作装饰性容器底色（非文本），文本仍走 token。
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: isDark ? 0.52 : 0.58),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outline.withValues(alpha: isDark ? 0.30 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.20 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 今日复习大卡：任务量口径与今日页一致（dueNew 待学 / dueReview 待复习）
class _TodayHeroCard extends StatelessWidget {
  final TodayStats stats;
  const _TodayHeroCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final due = stats.dueNew + stats.dueReview;

    return _GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primaryContainer
                  .withValues(alpha: isDark ? 0.26 : 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.play_circle_fill, color: cs.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日复习',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  due > 0
                      ? '${stats.dueReview} 个待复习 · ${stats.dueNew} 个新词待学习'
                      : '今日任务已清空，可以休息啦',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primaryContainer
                  .withValues(alpha: isDark ? 0.28 : 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$due',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// 主行动按钮：文案随任务状态变化（与今日页同款状态化逻辑）
class _PrimaryAction extends StatelessWidget {
  final bool actionable;
  final int due;
  final bool goAdd;

  const _PrimaryAction({
    required this.actionable,
    required this.due,
    required this.goAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon =
        actionable ? Icons.play_arrow : (goAdd ? Icons.add : Icons.check);
    final label = actionable
        ? '开始今日复习 · $due 词'
        : (goAdd ? '添加第一个单词' : '今日任务已完成');

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: actionable
            ? () => context.push('/review')
            : goAdd
                ? () => context.push('/add-word')
                : null,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          textStyle: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// 自由练习卡片：玻璃材质 + 快捷入口语义色浅底图标（跨页配色协调）
class _PracticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final VoidCallback onTap;

  const _PracticeCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: isDark ? 0.52 : 0.58),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outline.withValues(alpha: isDark ? 0.30 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.20 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, color: color, size: 23),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 近 7 天复习量柱状图（简单实现，无三方图表库）
class _WeeklyBarChart extends StatelessWidget {
  final List<DailyRecord> daily;
  const _WeeklyBarChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final byDate = {
      for (final d in daily)
        '${d.date.year}-${d.date.month}-${d.date.day}': d.reviews,
    };
    final now = DateTime.now();
    final days = <DateTime>[];
    for (var i = 6; i >= 0; i--) {
      days.add(now.subtract(Duration(days: i)));
    }
    final maxCount =
        daily.fold<int>(0, (m, d) => d.reviews > m ? d.reviews : m);

    // 全 0 空态：不画 7 根占位柱，给一句文案
    if (maxCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(
            '本周暂无复习记录',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    String fmt(DateTime d) => '${d.month}-${d.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.map((d) {
              final key = '${d.year}-${d.month}-${d.day}';
              final count = byDate[key] ?? 0;
              final height = (count / maxCount * 64.0).clamp(4.0, 64.0);
              final isToday = key == '${now.year}-${now.month}-${now.day}';
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$count',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isToday ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isToday ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        fmt(d),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isToday ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
