import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../core/utils/string_utils.dart';
import '../../../domain/models/review_rating.dart';

/// 单词详情页面
class WordDetailPage extends ConsumerStatefulWidget {
  final int wordId;
  const WordDetailPage({super.key, required this.wordId});

  @override
  ConsumerState<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends ConsumerState<WordDetailPage> {
  Map<String, dynamic>? _word;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _synonyms = [];
  bool _editing = false;

  final _customDefController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      final wordRepo = ref.read(wordRepositoryProvider);
      final reviewRepo = ref.read(reviewRepositoryProvider);

      final word = wordRepo.getWord(widget.wordId);
      if (word != null) {
        _customDefController.text = (word['custom_def'] as String?) ?? '';
        _noteController.text = (word['note'] as String?) ?? '';
        _tagsController.text = (word['tags'] as String?) ?? '';
      }

      setState(() {
        _word = word;
        _history = reviewRepo.getReviewHistory(widget.wordId);
        _synonyms = wordRepo.findSynonyms(widget.wordId);
      });
    } catch (e) {
      // ignore
    }
  }

  void _save() {
    try {
      final repo = ref.read(wordRepositoryProvider);
      repo.updateWord(
        widget.wordId,
        customDef: _customDefController.text.trim(),
        note: _noteController.text.trim(),
        tags: _tagsController.text.trim(),
      );
      setState(() => _editing = false);
      _loadData();
      // 触发词库列表刷新
      ref.read(wordListVersionProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  void _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除单词'),
        content: Text('确定要删除 "${_word?['word']}" 吗？\n复习记录也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final repo = ref.read(wordRepositoryProvider);
      repo.deleteWord(widget.wordId);
      // 触发词库列表刷新
      ref.read(wordListVersionProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  void _blockSynonym(String word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除近义词'),
        content: Text('确定要将 "$word" 从近义词中移除吗？\n移除后将不再推荐该词作为近义词。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final repo = ref.read(wordRepositoryProvider);
    repo.blockSynonym(widget.wordId, word);
    _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除 "$word"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_word == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: '单词不存在'),
      );
    }

    final word = _word!;
    final isFavorite = (word['is_favorite'] as int?) == 1;
    final cardState = word['card_state'] as String? ?? 'new';
    final reps = (word['reps'] as int?) ?? 0;
    final lapses = (word['lapses'] as int?) ?? 0;
    final stability = (word['stability'] as num?)?.toDouble() ?? 0;
    final due = word['due'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(word['word'] as String),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? Colors.amber : null),
            onPressed: () {
              final repo = ref.read(wordRepositoryProvider);
              repo.updateWord(widget.wordId, isFavorite: !isFavorite);
              // 触发词库列表刷新
              ref.read(wordListVersionProvider.notifier).state++;
              _loadData();
            },
          ),
          PopupMenuButton(
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'delete', child: Text('删除单词')),
            ],
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片信息
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(word['word'] as String,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                        if ((word['sense_id'] as int?) != 0) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('义项 ${word['sense_id']}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_editing) ...[
                      // 编辑模式
                      TextField(
                        controller: _customDefController,
                        decoration: const InputDecoration(labelText: '释义'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteController,
                        decoration: const InputDecoration(labelText: '备注'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tagsController,
                        decoration: const InputDecoration(labelText: '标签'),
                      ),
                    ] else ...[
                      // 查看模式
                      if ((word['custom_def'] as String?)?.isNotEmpty == true)
                        _InfoRow(label: '释义', value: word['custom_def'] as String),
                      if ((word['note'] as String?)?.isNotEmpty == true)
                        _InfoRow(label: '备注', value: word['note'] as String),
                      if ((word['tags'] as String?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: (word['tags'] as String)
                              .split(',')
                              .where((t) => t.trim().isNotEmpty)
                              .map((t) => Chip(
                                    label: Text(t.trim(),
                                        style: const TextStyle(fontSize: 11)),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 近义词
            if (_synonyms.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.hub_outlined,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('近义词 (${_synonyms.length})',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                          const Spacer(),
                          Text('点 × 移除错词',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _synonyms.map((s) {
                          return InputChip(
                            label: Text(s['word'] as String),
                            onPressed: () =>
                                context.push('/word/${s['id']}'),
                            onDeleted: () => _blockSynonym(s['word'] as String),
                            deleteIcon: const Icon(Icons.close, size: 16),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // FSRS 状态
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('学习状态',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 12),
                    _InfoRow(label: '状态', value: _stateLabel(cardState)),
                    _InfoRow(label: '复习次数', value: '$reps'),
                    _InfoRow(label: '遗忘次数', value: '$lapses'),
                    _InfoRow(
                        label: '稳定性',
                      value: stability > 0 ? '${stability.toStringAsFixed(1)} 天' : '-'),
                    if (due != null)
                      _InfoRow(
                        label: '下次复习',
                        value: StringUtils.formatDue(DateTime.tryParse(due))),
                    _InfoRow(
                      label: '添加时间',
                      value: StringUtils.relativeTime(
                          DateTime.parse(word['created_at'] as String))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 复习历史
            if (_history.isNotEmpty) ...[
              Text('复习历史 (${_history.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 8),
              ...(_history.take(20).map((h) {
                final rating = ReviewRating.fromValue(h['rating'] as int);
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 6,
                    backgroundColor: switch (rating) {
                      ReviewRating.again => const Color(0xFFE53935),
                      ReviewRating.hard => const Color(0xFFFFA726),
                      ReviewRating.good => const Color(0xFF43A047),
                      ReviewRating.easy => const Color(0xFF1E88E5),
                    },
                  ),
                  title: Text(rating.label),
                  subtitle: Text(StringUtils.relativeTime(
                      DateTime.parse(h['reviewed_at'] as String))),
                );
              })),
            ],
          ],
        ),
      ),
    );
  }

  String _stateLabel(String state) {
    return switch (state) {
      'new' => '新词',
      'learning' => '学习中',
      'review' => '复习中',
      'relearning' => '重新学习',
      _ => state,
    };
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                )),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
