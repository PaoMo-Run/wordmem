import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/story.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import 'story_edit_page.dart';

/// 短文记忆库：浏览已归档短文，支持查看 / 编辑 / 删除 / 取消归档
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 静态玻璃列表条目（blur 0）。
class StoryMemoryPage extends ConsumerStatefulWidget {
  const StoryMemoryPage({super.key});

  @override
  ConsumerState<StoryMemoryPage> createState() => _StoryMemoryPageState();
}

class _StoryMemoryPageState extends ConsumerState<StoryMemoryPage> {
  List<Story> _stories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(storyRepositoryProvider);
      final stories = repo.getAll(archived: true);
      if (mounted) {
        setState(() {
          _stories = stories;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openStory(Story story) async {
    final updated = await Navigator.of(context).push<Story?>(
      MaterialPageRoute(builder: (_) => StoryEditPage(story: story)),
    );
    if (updated != null) {
      await _save(updated);
    } else if (mounted) {
      _reload();
    }
  }

  Future<void> _save(Story story) async {
    try {
      final repo = ref.read(storyRepositoryProvider);
      if (story.id == null) {
        repo.save(story.copyWith(archived: true));
      } else {
        repo.update(story.copyWith(archived: true));
      }
      ref.read(storyVersionProvider.notifier).state++;
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(Story story) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除短文'),
        content: const Text('确定删除这篇短文吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final repo = ref.read(storyRepositoryProvider);
      repo.delete(story.id!);
      ref.read(storyVersionProvider.notifier).state++;
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _unarchive(Story story) async {
    try {
      final repo = ref.read(storyRepositoryProvider);
      repo.setArchived(story.id!, false);
      ref.read(storyVersionProvider.notifier).state++;
      if (mounted) _reload();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 短文保存/测验记录后自动刷新（从测验页返回、其他入口变更等）—— 必须在 build 中调用
    ref.listen(storyVersionProvider, (_, __) => _reload());
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('短文记忆库'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          // push 页面自带 aurora 背景（MainShell 只包 tab 页）
          const AppBackground(),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _stories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 56,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '记忆库还是空的',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '在「今日短文」中生成并存入记忆库的短文会显示在这里',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _stories.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final story = _stories[i];
                          final sourceLabel = switch (story.source) {
                            StorySource.ai => 'AI',
                            StorySource.manual => '导入',
                            StorySource.template => '模板',
                          };
                          final sourceColor = switch (story.source) {
                            StorySource.ai => theme.colorScheme.primary,
                            StorySource.manual => theme.colorScheme.tertiary,
                            StorySource.template => theme.colorScheme.outline,
                          };
                          return GlassContainer(
                            onTap: () => _openStory(story),
                            // 列表条目：静态玻璃（blur 0）避免滚动掉帧
                            blur: 0,
                            elevated: false,
                            radius: 14,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        story.title.isEmpty
                                            ? '未命名短文'
                                            : story.title,
                                        style: theme.textTheme.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: sourceColor
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        sourceLabel,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(color: sourceColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  story.content,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(height: 1.5),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      '${story.words.length} 词 · '
                                      '${story.updatedAt.month}月${story.updatedAt.day}日',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: theme.colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: '取消归档',
                                      icon: const Icon(
                                          Icons.bookmark_remove_outlined,
                                          size: 18),
                                      onPressed: () => _unarchive(story),
                                    ),
                                    IconButton(
                                      tooltip: '删除',
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18),
                                      onPressed: () =>
                                          _confirmDelete(story),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}
