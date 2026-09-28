import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/colors.dart';
import '../../../data/repositories/sync_repository.dart';
import '../../../infra/sync/webdav_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass.dart';
import '../../../domain/models/stats.dart';
import '../../settings/presentation/sync_restore_flow.dart';
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

/// 本次进程是否已做过「启动时云端备份探测」（v2.1.7）。
///
/// 底部导航是路由切换（不是 IndexedStack），每次点回「今日」都会重建本页，
/// 所以必须用**进程级**标志保证「只在冷启动探测一次」——
/// 单纯切页、切回前台都不打扰（用户拍板的设计点 1）。
bool _startupProbeDone = false;

class _TodayContent extends ConsumerStatefulWidget {
  const _TodayContent();

  @override
  ConsumerState<_TodayContent> createState() => _TodayContentState();
}

class _TodayContentState extends ConsumerState<_TodayContent>
    with WidgetsBindingObserver {
  TodayStats? _stats;
  int _streak = 0;
  List<QuickAction> _quickActions = [];
  final _quickRepo = QuickActionsRepo();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _loadQuickActions();
    _probeRemoteBackupOnStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台时重算「未来 3 小时到期」。
  ///
  /// 这个数字与**当前时刻**有关，会随时间自己变化；而 `upcomingDueCountProvider`
  /// 只在词库版本变化时重算 —— 不主动刷新就会一直停在打开 App 那一刻的值
  /// （真机反馈 2026-09-17：下拉刷新没反应，切到桌面再进才更新）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  /// 刷新首页全部数据：统计 + 「未来 3 小时到期」窗口
  ///
  /// 统计是普通查询，重跑即可；窗口值来自 FutureProvider，**必须显式失效**，
  /// 否则下拉刷新只会更新上面的数字、下面那行时间敏感的数字不动。
  Future<void> _refreshAll() async {
    if (!mounted) return;
    _loadData();
    ref.invalidate(upcomingDueCountProvider);
    try {
      await ref.read(upcomingDueCountProvider.future);
    } catch (_) {
      // 刷新失败保留原值，不打断下拉动画
    }
  }

  // ───────────── 提前背（v2.1.11）─────────────

  /// 「提前背」：把**未来 3 小时内到期**的词现在就先复习一轮。
  ///
  /// 场景：用户预知接下来几小时没法复习（开会 / 赶车 / 断网），
  /// 与其让这些词过期堆积，不如提前把复习阶段推进一格。
  ///
  /// 三重保护：
  /// 1. 按钮在计数为 0 时置灰；
  /// 2. 这里再**兜一次空**（provider 可能在按钮渲染后过期）；
  /// 3. **二次确认弹窗**明确告知"会立即开始一轮完整测验、并推进复习阶段"。
  ///
  /// 复习结果走的是**正常提交流程**（`submitReview` → FSRS 推进 T 节点 →
  /// 写复习记录），不是自选复习那种纯练习。完成后这些词的 `due` 已被推后，
  /// 所以不会再出现在今天的待复习里。
  Future<void> _confirmEarlyReview() async {
    final count = ref.read(upcomingDueCountProvider).valueOrNull ?? 0;
    if (count <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('未来 3 小时没有词到期')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('提前背这 $count 个词？'),
        content: const Text(
          '它们会在未来 3 小时内陆续到期。提前复习会立即开始一轮完整测验'
          '（英译汉 → 选单词 → 默写，和平时一样），并正常推进各自所属的复习阶段。\n\n'
          '做完后这些词今天就不会再出现了。适合预知接下来没空复习的情况。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再等等'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    await context.push('/review?mode=early');
    // 回来后重算统计与"未来 3 小时"窗口（做完的词 due 已被推后）
    if (mounted) await _refreshAll();
  }

  // ───────────── 启动时云端备份探测（v2.1.7）─────────────

  /// 冷启动时静默对比云端备份与本机水位（设计点 1~6）。
  ///
  /// 约束：
  /// - 只探测一次，且在**延迟 2 秒后**进行：不阻塞首屏、不显示 loading
  /// - 未配置网盘 → 直接返回：纯离线用户零网络行为（守住"可完全离线运行"）
  /// - 网络失败 → 静默，不弹任何错误
  /// - 用户选「稍后」→ 记住该快照名，同一份快照不再提示
  void _probeRemoteBackupOnStartup() {
    if (_startupProbeDone) return;
    _startupProbeDone = true;
    unawaited(_probeRemoteBackup());
  }

  /// 探测的外层保护：探测是后台增强，任何异常都必须静默吞掉——
  /// [unawaited] 触发的异步异常若无人接住会打穿到 Zone 层。
  Future<void> _probeRemoteBackup() async {
    try {
      await _runRemoteBackupProbe();
    } catch (_) {
      // 静默：失败无感是设计点 3
    }
  }

  Future<void> _runRemoteBackupProbe() async {
    await Future.delayed(AppConstants.syncProbeDelay);
    if (!mounted) return;

    // 1) 配置闸门：未配置网盘 = 纯离线用户，不发起任何网络请求
    final store = ref.read(syncSettingsStoreProvider);
    final url = await store.read(SyncSettingKeys.davUrl);
    final user = await store.read(SyncSettingKeys.davUser);
    final password = await store.read(SyncSettingKeys.davPassword);
    if (!mounted) return;
    if (url == null ||
        url.isEmpty ||
        user == null ||
        user.isEmpty ||
        password == null ||
        password.isEmpty) {
      return;
    }

    // 2) 只拉 manifest 探测（不下载快照内容；任何异常一律静默）
    final repo = SyncRepository(
      storage: WebdavSyncStorage(url: url, user: user, password: password),
      settings: store,
      localStats: ref.read(syncLocalStatsProvider),
      backup: ref.read(syncBackupGatewayProvider),
    );
    final entry = await repo.probeNewerSnapshot();
    if (entry == null || !mounted) return;

    // 3) 本次已忽略过这份快照 → 不再打扰（设计点 4）
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (!mounted) return;
    if (prefs.getString(AppConstants.keySyncProbeDismissed) == entry.name) {
      return;
    }

    // 4) 询问是否下载
    final local = entry.uploadedTime?.toLocal();
    final whenText = local != null ? _fmtDateTime(local) : entry.name;
    final deviceName = entry.deviceName;
    final deviceText = (deviceName != null && deviceName.isNotEmpty)
        ? '（来自 $deviceName）'
        : '';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('云端有更新的备份'),
        content: Text(
          '云端备份 $whenText$deviceText 比本机进度新，是否现在下载恢复？\n\n'
          '下载会用云端备份覆盖本机当前的学习数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (go != true) {
      // 记账：同一份快照不再提示，云端出现更新的快照时才会再问
      await prefs.setString(AppConstants.keySyncProbeDismissed, entry.name);
      return;
    }

    // 5) 走与「我的 → 进度同步」完全相同的恢复链路（含防呆确认，不绕过）
    final r = await executeCloudRestore(
      context: context,
      repo: repo,
      snapshotName: entry.name,
    );
    if (r == null || !mounted) return;
    _showSnack(r.message);
    if (r.ok) {
      // 恢复成功 → 通知全 App 重载（本页靠 ref.listen 自动刷新，无需下拉）
      ref.read(wordListVersionProvider.notifier).state++;
      ref.read(groupVersionProvider.notifier).state++;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _fmtDateTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _loadQuickActions() async {
    final ids = await _quickRepo.load();
    if (mounted) {
      setState(() => _quickActions = _quickRepo.resolve(ids));
    }
  }

  void _loadData() {
    if (!mounted) return;
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
    // v2.1.6：未来 3 小时内将到期的词数（首页提示）。
    // null = 尚未加载完成或查询异常 —— 此时整行不展示，避免显示误导性的 0。
    final upcoming = ref.watch(upcomingDueCountProvider).valueOrNull;

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 116),
        children: [
          _TodayHero(
            stats: stats,
            streak: _streak,
            upcoming: upcoming,
            // v2.1.11：提前背（计数为 0 时按钮自身置灰）
            onEarlyReview: _confirmEarlyReview,
          ),
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
        ],
      ),
    );
  }
}

/// 顶部 Hero：问候 + 连续天数 + 进度环 + 三项统计
class _TodayHero extends StatelessWidget {
  final TodayStats stats;
  final int streak;
  /// 未来 3 小时内将到期的词数（v2.1.6）；null = 尚未就绪，整行不展示
  final int? upcoming;
  /// v2.1.11：「提前背」的点击回调（null = 不展示按钮）
  final VoidCallback? onEarlyReview;

  const _TodayHero({
    required this.stats,
    required this.streak,
    this.upcoming,
    this.onEarlyReview,
  });

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
            // v2.1.6：未来 3 小时到期提示（独立一行，始终可见——值为 0 也展示，
            // 便于用户确认该功能生效；只有 provider 尚未就绪时才隐藏）
            if (upcoming != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 15,
                    color: upcoming! > 0 ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      upcoming! > 0
                          ? '未来 3 小时有 ${upcoming!} 个词将到期'
                          : '未来 3 小时没有词到期',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: upcoming! > 0
                            ? cs.primary
                            : cs.onSurfaceVariant,
                        fontWeight: upcoming! > 0 ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  // v2.1.11：提前背 —— 预知接下来没空复习时，把马上要到期的词先推一轮。
                  // 窗口内没有词时按钮置灰（点击时还会再兜一次，见 _confirmEarlyReview）。
                  if (onEarlyReview != null)
                    TextButton(
                      onPressed: upcoming! > 0 ? onEarlyReview : null,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('提前背'),
                    ),
                ],
              ),
            ],
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

    // 空词库：主按钮位直接显示「添加单词」（2026-08-31 用户要求：
    // 按钮上移到主行动位，下方 EmptyState 整块已删）
    if (goAdd) {
      return SizedBox(
        width: double.infinity,
        child: GlassButton(
          onPressed: () => context.push('/add-word'),
          icon: Icons.add,
          label: '添加单词',
          tinted: true,
        ),
      );
    }

    final icon = actionable ? Icons.play_arrow : Icons.check;
    final label = actionable ? '开始今日复习 · $due 词' : '今日任务已完成';

    return SizedBox(
      width: double.infinity,
      child: GlassButton(
        onPressed: actionable ? () => context.push('/review') : null,
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
      blur: 0,
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
