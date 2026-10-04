import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/mastery_badge.dart';
import '../../../domain/services/root_matcher.dart';
import '../../../domain/services/word_root_dict.dart';

/// 词群记忆（B 方案复习中心 → 自由练习）
/// Tab 1 近义词群：按近义词聚类；Tab 2 词根群：按词根聚合
/// 选择具体词群后进入对应挑战
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 静态玻璃列表卡（blur 0）。
class WordGroupMemoryPage extends ConsumerStatefulWidget {
  const WordGroupMemoryPage({super.key});

  @override
  ConsumerState<WordGroupMemoryPage> createState() =>
      _WordGroupMemoryPageState();
}

class _WordGroupMemoryPageState extends ConsumerState<WordGroupMemoryPage> {
  bool _rootsLoaded = false;
  List<RootMatch> _rootMatches = [];
  List<Map<String, dynamic>> _synonymGroups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 词根字典（首次加载）
    if (!_rootsLoaded) {
      try {
        final dict = await WordRootDict.load();
        final wordDao = ref.read(wordDaoProvider);
        final words = wordDao.getAllWordTexts();
        if (mounted) {
          setState(() {
            _rootMatches = RootMatcher().match(words, dict.roots);
            _rootsLoaded = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _rootsLoaded = true);
      }
    }
    _loadSynonymGroups();
  }

  void _loadSynonymGroups() {
    try {
      final repo = ref.read(wordRepositoryProvider);
      // v2.1.7：建群逻辑移到 WordRepository.buildSynonymGroups()。
      // 原实现在这里只拿**最新添加的 40 个词**当种子（words.take(40)），
      // 而近义词匹配本身是全库扫描的 —— 词库 < 40 词时它等于全库（所以早期有群），
      // 涨到 285 词后窗口只剩 14%，聚类词全在窗口外 → 群数为 0（真机反馈）。
      final groups = repo.buildSynonymGroups();
      // 旧 ID（成员列表串）→ 新 ID（核心词）的熟悉度数据迁移（一次性）
      repo.migrateSynonymGroupMastery(groups);
      if (mounted) setState(() => _synonymGroups = groups);
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    // 群挑战通过 / 手动移出词林 / 从词根移出 后自动刷新（熟悉度与群成员即时更新）—— 必须在 build 中调用
    ref.listen(groupVersionProvider, (_, __) => _load());
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('词群记忆'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.hub_outlined), text: '近义词群'),
              Tab(icon: Icon(Icons.spa_outlined), text: '词根群'),
            ],
          ),
        ),
        body: Stack(
          children: [
            AdaptiveContent(
              child: TabBarView(
                children: [
                  _buildSynonymTab(theme),
                  _buildRootTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 近义词群 ----------
  Widget _buildSynonymTab(ThemeData theme) {
    if (_synonymGroups.isEmpty) {
      return const EmptyState(
        icon: Icons.hub_outlined,
        title: '还没有可组群的近义词',
        subtitle: '词库中的近义词达到一定数量后，这里会自动聚类成词群',
      );
    }
    final mastery = ref.read(wordRepositoryProvider).getSynonymGroupMastery();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _synonymGroups.length,
      itemBuilder: (context, i) {
        final g = _synonymGroups[i];
        final words = (g['words'] as List).cast<String>();
        final m = mastery[g['id'] as String] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassContainer(
            onTap: () => _startSynonymChallenge(g, i),
            // 列表条目：静态玻璃（blur 0）避免滚动掉帧
            blur: 0,
            elevated: false,
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.hub_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g['def'] as String? ?? '',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        '${words.length} 个近义词 · ${words.take(4).join(' / ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      MasteryBadge(level: m),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  onPressed: () => _startSynonymChallenge(g, i),
                  label: '测试',
                  blur: 0,
                  height: 46,
                  radius: 14,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startSynonymChallenge(Map<String, dynamic> group, int index) async {
    // 进入词群专属挑战：按群依次测，通过则熟悉度+1
    // await 返回后显式重载（双保险：版本号监听 + 返回刷新），
    // 确保挑战期间的熟悉度变化 / 人工复核移出词林立即反映到列表
    await context.push('/synonym-group-challenge', extra: {
      'groups': _synonymGroups,
      'start': index,
    });
    if (mounted) _load();
  }

  // ---------- 词根群 ----------
  Widget _buildRootTab(ThemeData theme) {
    if (!_rootsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rootMatches.isEmpty) {
      return const EmptyState(
        icon: Icons.spa_outlined,
        title: '词库里还没有命中词根',
        subtitle: '添加更多单词后，含同一词根的单词会自动聚成词根群',
      );
    }
    final rootMastery = ref.read(wordRepositoryProvider).getRootMastery();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rootMatches.length,
      itemBuilder: (context, i) {
        final m = _rootMatches[i];
        final rm = rootMastery[m.root.root] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassContainer(
            onTap: () => _startRootChallenge(m, i),
            // 列表条目：静态玻璃（blur 0）
            blur: 0,
            elevated: false,
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    m.root.root.toUpperCase().substring(0, 1),
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${m.root.root} · ${m.root.meaning}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${m.words.length} 个词 · ${m.words.take(3).join(' / ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                MasteryBadge(level: rm),
                const SizedBox(width: 8),
                GlassButton(
                  onPressed: () => _startRootChallenge(m, i),
                  label: '测试',
                  blur: 0,
                  height: 46,
                  radius: 14,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startRootChallenge(RootMatch match, int index) async {
    // v2.2.0 需求3：payload 传 matches+index，挑战页结果可「下一词根」连续测试
    // await 返回后显式重载（双保险），词根熟悉度变化立即反映
    await context.push('/root-challenge', extra: {
      'match': match,
      'matches': _rootMatches,
      'index': index,
    });
    if (mounted) _load();
  }
}

