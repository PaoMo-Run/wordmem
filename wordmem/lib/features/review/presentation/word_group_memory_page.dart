import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/mastery_badge.dart';
import '../../../domain/services/root_matcher.dart';
import '../../../domain/services/word_root_dict.dart';

/// 词群记忆（B 方案复习中心 → 自由练习）
/// Tab 1 近义词群：按近义词聚类；Tab 2 词根群：按词根聚合
/// 选择具体词群后进入对应挑战
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
      final words = repo.getAllWords(limit: 100000);
      final groups = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final w in words.take(40)) {
        final syns = repo.findSynonyms(w['id'] as int);
        if (syns.length < 2) continue;
        final members = <String>[
          w['word'] as String,
          ...syns.map((s) => s['word'] as String),
        ];
        // 群 ID 使用语义核心词（稳定）：成员/种子变化不影响 ID，熟悉度不丢
        final id = repo.coreDefinition(
            w['custom_def'] as String?, w['word'] as String);
        if (seen.contains(id) || groups.length >= 30) continue;
        seen.add(id);
        groups.add({
          'id': id,
          'seed': w['word'],
          'words': members,
          'def': id,
        });
      }
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
        appBar: AppBar(
          title: const Text('词群记忆'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.hub_outlined), text: '近义词群'),
              Tab(icon: Icon(Icons.spa_outlined), text: '词根群'),
            ],
          ),
        ),
        body: AdaptiveContent(
          child: TabBarView(
            children: [
              _buildSynonymTab(theme),
              _buildRootTab(theme),
            ],
          ),
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
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
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
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      MasteryBadge(level: m),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _startSynonymChallenge(g, i),
                  child: const Text('开始测试'),
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
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                m.root.root.toUpperCase().substring(0, 1),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w800),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.root.root} · ${m.root.meaning}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                MasteryBadge(level: rm),
              ],
            ),
            subtitle: Text('${m.words.length} 个词 · ${m.words.take(3).join(' / ')}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: FilledButton.tonal(
              onPressed: () => _startRootChallenge(m),
              child: const Text('开始测试'),
            ),
            onTap: () => _startRootChallenge(m),
          ),
        );
      },
    );
  }

  Future<void> _startRootChallenge(RootMatch match) async {
    // await 返回后显式重载（双保险），词根熟悉度变化立即反映
    await context.push('/root-challenge', extra: match);
    if (mounted) _load();
  }
}

