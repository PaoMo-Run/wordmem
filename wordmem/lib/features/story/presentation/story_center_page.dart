import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/story.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';

/// 短文中心（B 方案第 3 个 tab）
/// 今日短文入口卡片 + 记忆库最近列表
///
/// 设计约定（2026-08-30 液体玻璃改版）：背景由 MainShell aurora 提供；
/// 今日入口卡 = tinted glass（primary 调味），记忆库列表 = 静态玻璃（blur 0）。
class StoryCenterPage extends ConsumerStatefulWidget {
  const StoryCenterPage({super.key});

  @override
  ConsumerState<StoryCenterPage> createState() => _StoryCenterPageState();
}

class _StoryCenterPageState extends ConsumerState<StoryCenterPage> {
  List<Story> _stories = [];
  bool _loading = true;
  int _todayWords = 0;

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
      final wordDao = ref.read(wordDaoProvider);
      final todayWords = wordDao.getWordsStudiedToday().length;
      if (mounted) {
        setState(() {
          _stories = stories.take(5).toList();
          _todayWords = todayWords;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 短文保存/编辑/归档/测验后自动刷新记忆库列表（必须在 build 中调用）
    ref.listen(storyVersionProvider, (_, __) => _reload());
    final theme = Theme.of(context);

    return Scaffold(
      // 液体玻璃布局：背景由 MainShell 的 aurora 光斑提供，Scaffold 透明；
      // extendBody 下底部 padding 避开悬浮玻璃 dock（≈116）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('短文'),
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 116),
          children: [
            // 今日短文入口卡片（整卡可点击，tinted glass 主入口）
            GlassContainer(
              onTap: () async {
                // await 返回后显式刷新（双保险：版本号监听 + 返回刷新）
                await context.push('/story');
                if (mounted) _reload();
              },
              tint: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_stories_outlined,
                          color: theme.colorScheme.primary, size: 28),
                      const SizedBox(width: 10),
                      Text('今日短文',
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _todayWords > 0
                        ? 'AI 用你今天学的 $_todayWords 个词生成一篇短文，巩固记忆'
                        : '今天还没有学习新词，先去复习或添加单词吧',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: theme.brightness == Brightness.dark
                              ? 0.28
                              : 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('去生成 / 阅读',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 记忆库
            Row(
              children: [
                Text('记忆库',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await context.push('/story-memory');
                    if (mounted) _reload();
                  },
                  child: const Text('查看全部'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_stories.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.bookmarks_outlined,
                        size: 44,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text('记忆库还是空的',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('在「今日短文」中生成并存入记忆库的短文会显示在这里',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              )
            else
              GlassContainer(
                blur: 0,
                elevated: false,
                radius: 14,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final story in _stories)
                      ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(
                          story.title.isEmpty ? '未命名短文' : story.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${story.words.length} 词 · ${_fmtDate(story.createdAt)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await context.push('/story-memory');
                          if (mounted) _reload();
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
