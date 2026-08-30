import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../domain/models/stats.dart';

/// 复习中心（B 方案第 2 个 tab）
/// 今日复习（FSRS 大卡）+ 自由练习（自选复习 / 近义词挑战）+ 本周复习量
class ReviewCenterPage extends ConsumerStatefulWidget {
  const ReviewCenterPage({super.key});

  @override
  ConsumerState<ReviewCenterPage> createState() => _ReviewCenterPageState();
}

class _ReviewCenterPageState extends ConsumerState<ReviewCenterPage> {
  int _pending = 0;
  int _newToday = 0;
  List<DailyRecord> _daily = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final reviewRepo = ref.read(reviewRepositoryProvider);
      final statsDao = ref.read(statsDaoProvider);
      final today = statsDao.getTodayStats();
      setState(() {
        _pending = reviewRepo.pendingCount;
        _newToday = today.newWordsToday;
        _daily = statsDao.getDailyRecords(7);
      });
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.listen(wordListVersionProvider, (_, __) => _load());

    return Scaffold(
      appBar: AppBar(title: const Text('复习中心')),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: AdaptiveContent(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            // 今日复习大卡
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill,
                      color: Colors.white, size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('今日复习 · 艾宾浩斯 7 周期',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          _pending + _newToday > 0
                              ? '$_pending 个待复习 · $_newToday 个新词待学习'
                              : '今日任务已清空，可以休息啦',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      (_pending + _newToday).toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_pending + _newToday) > 0 ? () => context.push('/review') : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始今日复习'),
              ),
            ),
            const SizedBox(height: 20),

            // 自由练习
            Text('自由练习', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PracticeCard(
                    icon: Icons.calendar_month_outlined,
                    title: '自选复习',
                    desc: '按日期筛选\n不影响算法',
                    color: theme.colorScheme.tertiary,
                    onTap: () => context.push('/custom-review'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PracticeCard(
                    icon: Icons.hub_outlined,
                    title: '词群记忆',
                    desc: '近义词 + 词根\n分组测试',
                    color: theme.colorScheme.primary,
                    onTap: () => context.push('/word-group-memory'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 本周复习量
            Text('本周复习量', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _WeeklyBarChart(daily: _daily),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

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
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 10),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(desc,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6))),
            ],
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

    String fmt(DateTime d) => '${d.month}-${d.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:             days.map((d) {
              final key = '${d.year}-${d.month}-${d.day}';
              final count = byDate[key] ?? 0;
              final height = maxCount == 0
                  ? 4.0
                  : (count / maxCount * 64.0).clamp(4.0, 64.0);
              final isToday = key == '${now.year}-${now.month}-${now.day}';
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5))),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isToday
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(fmt(d),
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: isToday
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5))),
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
