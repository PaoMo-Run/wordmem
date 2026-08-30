import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/stats.dart';
import '../../../core/theme/colors.dart';

/// 统计页面
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  StreakStats? _streakStats;
  StatusDistribution? _distribution;
  List<DailyRecord> _dailyRecords = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      final statsDao = ref.read(statsDaoProvider);
      setState(() {
        _streakStats = statsDao.getStreakStats();
        _distribution = statsDao.getStatusDistribution();
        _dailyRecords = statsDao.getDailyRecords(7);
      });
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_streakStats == null || _distribution == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('统计')),
        body: const LoadingIndicator(),
      );
    }

    final stats = _streakStats!;
    final dist = _distribution!;

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: stats.totalWords == 0
          ? const EmptyState(
              icon: Icons.bar_chart_outlined,
              title: '暂无统计数据',
              subtitle: '添加单词并开始学习后这里会显示统计',
            )
          : RefreshIndicator(
              onRefresh: () async => _loadData(),
              child: AdaptiveContent(
                child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 概览卡片
                  _OverviewCard(stats: stats),
                  const SizedBox(height: 16),

                  // 掌握状态分布
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('掌握状态分布',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 16),
                          _StatusDistribution(distribution: dist),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 趋势图
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('学习趋势',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )),
                              Text('近 7 天',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  )),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 180,
                            child: _TrendChart(records: _dailyRecords),
                          ),
                        ],
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

/// 概览卡片
class _OverviewCard extends StatelessWidget {
  final StreakStats stats;
  const _OverviewCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.local_fire_department,
                    label: '连续学习',
                    value: '${stats.currentStreak}',
                    unit: '天',
                    color: Colors.orange,
                  ),
                ),
                Expanded(
                  child: _StatBox(
                    icon: Icons.book_outlined,
                    label: '总单词数',
                    value: '${stats.totalWords}',
                    unit: '个',
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: _StatBox(
                    icon: Icons.repeat,
                    label: '总复习数',
                    value: '${stats.totalReviews}',
                    unit: '次',
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.psychology_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('预计平均记忆率: ',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    )),
                Text(
                  '${(stats.predictedRetention * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            children: [
              TextSpan(text: value, style: TextStyle(color: color)),
              TextSpan(
                text: ' $unit',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            )),
      ],
    );
  }
}

/// 掌握状态分布饼图
class _StatusDistribution extends StatelessWidget {
  final StatusDistribution distribution;
  const _StatusDistribution({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = distribution.total;
    if (total == 0) return const SizedBox.shrink();

    final items = [
      (label: '新词', count: distribution.newCount, color: AppColors.statusNew),
      (label: '学习中', count: distribution.learningCount, color: AppColors.statusLearning),
      (label: '熟悉', count: distribution.familiarCount, color: AppColors.statusReview),
      (label: '已掌握', count: distribution.masteredCount, color: AppColors.statusMastered),
    ];

    return Column(
      children: items.map((item) {
        final percent = total > 0 ? item.count / total : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 60, child: Text(item.label)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: item.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: Text(
                  '${item.count}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 趋势图（折线图）
class _TrendChart extends StatelessWidget {
  final List<DailyRecord> records;
  const _TrendChart({required this.records});

  static const double _chartHeight = 130.0;
  static const double _labelHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (records.isEmpty) {
      return Center(
        child: Text('暂无数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            )),
      );
    }

    final maxValue = records.fold<int>(
      0,
      (max, r) => (r.newWords + r.reviews) > max ? r.newWords + r.reviews : max,
    );
    if (maxValue == 0) {
      return Center(
        child: Text('暂无学习数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            )),
      );
    }

    final newColor = theme.colorScheme.primary;
    final reviewColor = AppColors.statusReview;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 图例
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(color: newColor, label: '新增'),
            const SizedBox(width: 16),
            _LegendItem(color: reviewColor, label: '复习'),
          ],
        ),
        const SizedBox(height: 6),
        // 图表主体：左侧 Y 轴 + 折线图
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _YAxis(maxValue: maxValue),
              const SizedBox(width: 6),
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TrendLinePainter(
                    records: records,
                    maxValue: maxValue,
                    newColor: newColor,
                    reviewColor: reviewColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 底部日期标签
        SizedBox(
          height: _labelHeight,
          child: Row(
            children: records.map((r) {
              return Expanded(
                child: Text(
                  '${r.date.month}/${r.date.day}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// Y 轴数量刻度（左侧）
class _YAxis extends StatelessWidget {
  final int maxValue;
  const _YAxis({required this.maxValue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mid = (maxValue / 2).ceil();
    final style = theme.textTheme.labelSmall?.copyWith(
      fontSize: 10,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );
    return SizedBox(
      width: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text('$maxValue', style: style),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text('$mid', style: style),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text('0', style: style),
          ),
        ],
      ),
    );
  }
}

/// 折线图绘制器
class _TrendLinePainter extends CustomPainter {
  final List<DailyRecord> records;
  final int maxValue;
  final Color newColor;
  final Color reviewColor;

  _TrendLinePainter({
    required this.records,
    required this.maxValue,
    required this.newColor,
    required this.reviewColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty || maxValue <= 0) return;

    const topPad = 6.0;
    const bottomPad = 6.0;
    final chartHeight = size.height - topPad - bottomPad;
    if (chartHeight <= 0) return;

    final stepX = records.length > 1
        ? size.width / (records.length - 1)
        : size.width / 2;
    double xAt(int i) =>
        records.length > 1 ? i * stepX : size.width / 2;
    double yAt(int value) =>
        topPad + chartHeight - (value / maxValue) * chartHeight;

    _drawSeries(canvas, xAt, yAt, (r) => r.reviews, reviewColor);
    _drawSeries(canvas, xAt, yAt, (r) => r.newWords, newColor);
  }

  void _drawSeries(
    Canvas canvas,
    double Function(int) xAt,
    double Function(int) yAt,
    int Function(DailyRecord) getter,
    Color color,
  ) {
    if (records.isEmpty) return;
    final path = Path();
    for (var i = 0; i < records.length; i++) {
      final x = xAt(i);
      final y = yAt(getter(records[i]));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dotPaint = Paint()..color = color;
    for (var i = 0; i < records.length; i++) {
      final value = getter(records[i]);
      canvas.drawCircle(Offset(xAt(i), yAt(value)), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter old) =>
      records != old.records || maxValue != old.maxValue;
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            )),
      ],
    );
  }
}
