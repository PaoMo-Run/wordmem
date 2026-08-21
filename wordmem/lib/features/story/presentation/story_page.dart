import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/story.dart';
import '../../../domain/models/story_quiz.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../infra/ai/ai_exception.dart';
import 'story_word_picker_sheet.dart';
import 'widgets/story_tappable_text.dart';

/// 选词来源
enum StoryWordSource {
  /// 今日所学（新增 ∪ 复习）
  today,
  /// 指定日期范围（新增的单词）
  dateRange,
  /// 指定单词（词库多选）
  specific,
}

/// 今日短文页：自选单词 → 生成（AI 优先，模板兜底）→ 展示/编辑/归档
class StoryPage extends ConsumerStatefulWidget {
  const StoryPage({super.key});

  @override
  ConsumerState<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends ConsumerState<StoryPage> {
  StoryWordSource _source = StoryWordSource.today;
  List<String> _selectedWords = [];
  DateTimeRange? _dateRange;
  bool _loadingWords = false;
  bool _generating = false;

  Story? _story;
  bool _generationFailed = false;

  @override
  void initState() {
    super.initState();
    _loadTodayWords();
  }

  Future<void> _loadTodayWords() async {
    setState(() => _loadingWords = true);
    try {
      final repo = ref.read(storyRepositoryProvider);
      final words = repo.getWordsStudiedToday();
      if (mounted) {
        setState(() {
          _selectedWords = words.take(25).toList();
          _loadingWords = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingWords = false);
    }
  }

  Future<void> _loadRangeWords() async {
    final range = _dateRange;
    if (range == null) return;
    setState(() => _loadingWords = true);
    try {
      final repo = ref.read(storyRepositoryProvider);
      // 日期范围：当日 00:00 至次日 00:00
      final end = range.end.add(const Duration(days: 1));
      final words = repo.getWordsAddedBetween(range.start, end);
      if (mounted) {
        setState(() {
          _selectedWords = words.take(25).toList();
          _loadingWords = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingWords = false);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateRange,
      helpText: '选择单词添加日期范围',
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    await _loadRangeWords();
  }

  Future<void> _pickSpecificWords() async {
    final repo = ref.read(storyRepositoryProvider);
    final allWords = repo.getAllWords();
    if (!mounted) return;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StoryWordPickerSheet(
        allWords: allWords,
        initialSelected: _selectedWords.toSet(),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedWords = picked);
    }
  }

  Future<void> _generate() async {
    if (_selectedWords.isEmpty) return;
    setState(() {
      _generating = true;
      _generationFailed = false;
    });
    try {
      final repo = ref.read(storyRepositoryProvider);
      final enriched = repo.enrich(_selectedWords);
      final story = await repo.generate(enriched);
      if (mounted) {
        setState(() {
          _story = story;
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() => _generationFailed = true);
        _showClipboardGuide(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generationFailed = true);
        _showClipboardGuide('$e');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 重新生成：对已生成的短文不满意时，换一批内容重新生成
  Future<void> _regenerate() async {
    if (_selectedWords.isEmpty || _generating) return;
    setState(() => _generating = true);
    try {
      final repo = ref.read(storyRepositoryProvider);
      final enriched = repo.enrich(_selectedWords);
      final newStory = await repo.generate(enriched);
      if (mounted) {
        setState(() {
          // 保留原 story 的 id 与归档状态，便于直接覆盖记忆库
          _story = _story?.id != null
              ? newStory.copyWith(id: _story!.id, archived: _story!.archived)
              : newStory;
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        _showClipboardGuide(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showClipboardGuide('$e');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// AI 不可用时引导剪贴板中转：复制提示词 → 其它 AI App 生成 → 粘贴导入
  Future<void> _showClipboardGuide(String reason) async {
    final repo = ref.read(storyRepositoryProvider);
    final enriched = repo.enrich(_selectedWords);
    final prompt = repo.buildClipboardPrompt(enriched);

    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 生成不可用'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('原因：$reason\n\n可以复制下方提示词，到您已安装的 AI App（豆包、DeepSeek 等）中生成，再把结果粘贴回本页导入：'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  prompt,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: prompt));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('提示词已复制，请到 AI App 粘贴生成，再回来「粘贴导入」')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制提示词'),
          ),
        ],
      ),
    );
    if (action == 'import') {
      await _pasteImport();
    }
  }

  /// 查看离线提示词：把发给 AI 的提示词展示出来，可复制到其它 AI App 使用
  Future<void> _showOfflinePrompt() async {
    if (_selectedWords.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择单词，再查看提示词')),
        );
      }
      return;
    }
    final repo = ref.read(storyRepositoryProvider);
    final enriched = repo.enrich(_selectedWords);
    final prompt = repo.buildClipboardPrompt(enriched);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('离线提示词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('这是发给 AI 生成短文的完整提示词。可复制到任何 AI App（豆包、DeepSeek 等）生成，再把结果「粘贴导入」回本页：'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  prompt,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: prompt));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('提示词已复制，请到 AI App 粘贴生成，再回来「粘贴导入」')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制提示词'),
          ),
        ],
      ),
    );
  }

  /// 从剪贴板读取 AI 生成结果并解析导入（一键，无需手动填写）
  Future<void> _pasteImport() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空，请先在 AI App 中复制生成结果')),
        );
      }
      return;
    }
    try {
      final repo = ref.read(storyRepositoryProvider);
      final story = repo.parseImported(text);
      if (mounted) {
        setState(() {
          _story = story;
          _generationFailed = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已从剪贴板导入短文，可编辑后存入记忆库')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入解析失败: $e')),
        );
      }
    }
  }

  /// 保存 / 更新记忆库
  Future<void> _saveToLibrary(Story story) async {
    try {
      final repo = ref.read(storyRepositoryProvider);
      if (story.id == null) {
        repo.save(story.copyWith(archived: true));
      } else {
        repo.update(story.copyWith(archived: true));
      }
      // 通知短文中心 / 记忆库刷新
      ref.read(storyVersionProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到短文记忆库')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _editStory(Story story) async {
    final contentCtrl = TextEditingController(text: story.content);
    final transCtrl = TextEditingController(text: story.translation);
    final titleCtrl = TextEditingController(text: story.title);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑短文'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '英文正文',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: transCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '中文对照',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final updated = story.copyWith(
      title: titleCtrl.text.trim(),
      content: contentCtrl.text.trim(),
      translation: transCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );
    setState(() => _story = updated);
    await _saveToLibrary(updated);
  }

  /// 从短文卡片进入记忆测试（仅已保存的短文）
  Future<void> _startQuiz() async {
    final story = _story;
    if (story == null || story.id == null) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('今日短文')),
      body: AdaptiveContent(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSourceSelector(theme),
          const SizedBox(height: 16),
          _buildWordSection(theme),
          const SizedBox(height: 16),
          _buildGenerateButton(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showOfflinePrompt,
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('查看离线提示词'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generating ? null : _pasteImport,
                  icon: const Icon(Icons.content_paste_go_outlined),
                  label: const Text('粘贴导入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_generationFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'AI 生成失败，可检查「设置 - AI 服务」、重试，或使用剪贴板中转生成。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (_story != null) _buildStoryCard(theme, _story!),
        ],
      ),
      ),
    );
  }

  Widget _buildSourceSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择单词来源', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<StoryWordSource>(
          segments: const [
            ButtonSegment(
              value: StoryWordSource.today,
              label: Text('今日所学'),
              icon: Icon(Icons.today_outlined),
            ),
            ButtonSegment(
              value: StoryWordSource.dateRange,
              label: Text('按日期'),
              icon: Icon(Icons.date_range_outlined),
            ),
            ButtonSegment(
              value: StoryWordSource.specific,
              label: Text('指定单词'),
              icon: Icon(Icons.playlist_add_check),
            ),
          ],
          selected: {_source},
          onSelectionChanged: (s) {
            setState(() => _source = s.first);
            if (_source == StoryWordSource.today) _loadTodayWords();
          },
        ),
        if (_source == StoryWordSource.dateRange) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range),
            label: Text(_dateRange == null
                ? '选择日期范围'
                : '${_fmtDate(_dateRange!.start)} ~ ${_fmtDate(_dateRange!.end)}'),
          ),
        ],
        if (_source == StoryWordSource.specific) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickSpecificWords,
            icon: const Icon(Icons.checklist),
            label: const Text('从词库选择单词'),
          ),
        ],
      ],
    );
  }

  Widget _buildWordSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('已选单词', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (_loadingWords)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_selectedWords.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _selectedWords.clear()),
                child: const Text('清空'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedWords.isEmpty)
          Text(
            _loadingWords ? '正在加载...' : '还没有选择单词',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedWords
                .map((w) => Chip(
                      label: Text(w),
                      onDeleted: () => setState(
                          () => _selectedWords.remove(w)),
                    ))
                .toList(),
          ),
        const SizedBox(height: 4),
        Text(
          '最多取前 25 个单词生成；点「生成」使用所选单词写一篇事实合理的短文。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: (_generating || _selectedWords.isEmpty) ? null : _generate,
        icon: _generating
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: Text(_generating ? '生成中...' : '生成短文'),
      ),
    );
  }

  Widget _buildStoryCard(ThemeData theme, Story story) {
    final sourceLabel = switch (story.source) {
      StorySource.ai => 'AI 生成',
      StorySource.manual => '手动导入',
      StorySource.template => '模板生成',
    };
    final sourceColor = switch (story.source) {
      StorySource.ai => theme.colorScheme.primary,
      StorySource.manual => theme.colorScheme.tertiary,
      StorySource.template => theme.colorScheme.outline,
    };
    // 词数统计（英文单词数）
    final wordCount =
        RegExp(r"[A-Za-z][A-Za-z'-]*").allMatches(story.content).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    story.title.isEmpty ? '未命名短文' : story.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.12),
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
            Row(
              children: [
                Icon(Icons.notes,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '共 $wordCount 词',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StoryTappableText(
              text: story.content,
              highlightWords: story.words.toSet(),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            if (story.translation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  story.translation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (story.id != null) ...[
                  TextButton.icon(
                    onPressed: _generating ? null : _startQuiz,
                    icon: const Icon(Icons.quiz_outlined, size: 18),
                    label: const Text('测试'),
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  onPressed: _generating ? null : _regenerate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新生成'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _editStory(story),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _generating ? null : () => _saveToLibrary(story),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('存入记忆库'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
