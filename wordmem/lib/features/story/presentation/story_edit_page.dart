import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/story.dart';
import '../../../domain/models/story_quiz.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import 'widgets/story_tappable_text.dart';

/// 短文详情页：点词释义（默认只读，避免与点词冲突）+ 独立「编辑」按钮。
/// 返回修改后的 Story；删除由调用方处理。
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 玻璃卡。
class StoryEditPage extends ConsumerStatefulWidget {
  final Story story;

  const StoryEditPage({super.key, required this.story});

  @override
  ConsumerState<StoryEditPage> createState() => _StoryEditPageState();
}

class _StoryEditPageState extends ConsumerState<StoryEditPage> {
  bool _editing = false;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _transCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.story.title);
    _contentCtrl = TextEditingController(text: widget.story.content);
    _transCtrl = TextEditingController(text: widget.story.translation);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _transCtrl.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      _editing = !_editing;
      if (_editing) {
        // 进入编辑态时同步当前内容
        _titleCtrl.text = widget.story.title;
        _contentCtrl.text = widget.story.content;
        _transCtrl.text = widget.story.translation;
      }
    });
  }

  void _save() {
    final updated = widget.story.copyWith(
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      translation: _transCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );
    setState(() => _editing = false);
    Navigator.of(context).pop(updated);
  }

  /// 正文词数（英文单词数）
  int get _wordCount =>
      RegExp(r"[A-Za-z][A-Za-z'-]*").allMatches(widget.story.content).length;

  /// 选择测试模式并进入答题页
  Future<void> _startQuiz() async {
    final story = widget.story;
    final mode = await showModalBottomSheet<StoryQuizMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择测试模式', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...StoryQuizMode.values.map((m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (m) {
                      StoryQuizMode.review => Icons.touch_app_outlined,
                      StoryQuizMode.consolidate => Icons.keyboard_outlined,
                      StoryQuizMode.extend => Icons.edit_note,
                    }),
                    title: Text(m.label),
                    subtitle: Text(m.desc),
                    onTap: () => Navigator.pop(ctx, m),
                  )),
            ],
          ),
        ),
      ),
    );
    if (mode != null && mounted) {
      context.push('/story-quiz/${story.id}/${mode.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = widget.story;
    final sourceLabel = switch (story.source) {
      StorySource.ai => 'AI 生成',
      StorySource.manual => '手动导入',
      StorySource.template => '模板生成',
    };
    // 测试历史（有 id 才查询）
    final quizRecords = story.id == null
        ? <StoryQuizRecord>[]
        : ref.watch(storyQuizDaoProvider).getByStory(story.id!);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('短文详情'),
        actions: [
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除短文'),
                  content: const Text('确定删除这篇短文吗？'),
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
              if (ok == true && context.mounted) {
                Navigator.of(context).pop(story); // 由调用方删除
              }
            },
          ),
          TextButton(
            onPressed: _editing ? _save : _toggleEdit,
            child: Text(_editing ? '保存' : '编辑'),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('标题', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (_editing)
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            )
          else
            Text(
              story.title.isEmpty ? '未命名短文' : story.title,
              style: theme.textTheme.titleMedium,
            ),
          const SizedBox(height: 16),
          Text('英文正文', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (_editing)
            TextField(
              controller: _contentCtrl,
              maxLines: 10,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            )
          else ...[
            StoryTappableText(
              text: story.content,
              highlightWords: story.words.toSet(),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.notes,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '共 $_wordCount 词',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('中文对照', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (_editing)
            TextField(
              controller: _transCtrl,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            )
          else
            GlassContainer(
              blur: 0,
              padding: const EdgeInsets.all(12),
              child: Text(
                story.translation.isEmpty ? '（无中文对照）' : story.translation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '来源: $sourceLabel · 归档于 ${story.createdAt.year}年${story.createdAt.month}月${story.createdAt.day}日'
            '\n提示：点击正文中的单词可查看释义',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // 开始测试入口
          GlassButton(
            onPressed: _startQuiz,
            icon: Icons.quiz_outlined,
            label: '测试',
            tinted: true,
          ),
          // 测试历史
          if (quizRecords.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('测试历史', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            GlassContainer(
              blur: 0,
              elevated: false,
              radius: 14,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: quizRecords.take(10).map((r) {
                  final correctRate =
                      r.total == 0 ? 0 : (r.correct / r.total * 100).round();
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (r.mode) {
                      StoryQuizMode.review => Icons.touch_app_outlined,
                      StoryQuizMode.consolidate => Icons.keyboard_outlined,
                      StoryQuizMode.extend => Icons.edit_note,
                    }, size: 20),
                    title: Text(
                      '${r.mode.label} · $correctRate%',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      '${r.correct}/${r.total} · ${r.createdAt.toLocal().month}月${r.createdAt.toLocal().day}日 '
                      '${r.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${r.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
        ),
      ],
    ),
    );
  }
}
