import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../domain/models/stats.dart';

/// 文本批量导入页面
class TextImportPage extends ConsumerStatefulWidget {
  const TextImportPage({super.key});

  @override
  ConsumerState<TextImportPage> createState() => _TextImportPageState();
}

class _TextImportPageState extends ConsumerState<TextImportPage> {
  final _textController = TextEditingController();
  TextImportResult? _result;
  final Set<String> _selectedWords = {};
  bool _processing = false;
  bool _importing = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _analyze() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _processing = true;
      _result = null;
      _selectedWords.clear();
    });

    try {
      final repo = ref.read(importRepositoryProvider);
      final result = await repo.importFromText(text);
      setState(() {
        _result = result;
        _selectedWords.addAll(result.matchedWords);
        _processing = false;
      });
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失败: $e')),
        );
      }
    }
  }

  void _importSelected() async {
    if (_selectedWords.isEmpty) return;

    setState(() => _importing = true);

    try {
      final repo = ref.read(importRepositoryProvider);
      repo.batchAddWords(_selectedWords.toList());

      // 触发词库列表刷新
      ref.read(wordListVersionProvider.notifier).state++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${_selectedWords.length} 个单词')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }

    setState(() => _importing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('文本批量导入')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '粘贴英文文本，自动提取并匹配词典中的单词',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: '粘贴文章、段落或单词列表...',
                alignLabelWithHint: true,
              ),
              maxLines: 10,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _processing ? null : _analyze,
              icon: _processing
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.analytics_outlined),
              label: const Text('分析文本'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              _buildResult(theme),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _result != null && _selectedWords.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _importing ? null : _importSelected,
                  child: _importing
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('导入选中的 ${_selectedWords.length} 个单词'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildResult(ThemeData theme) {
    final result = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 统计
        Row(
          children: [
            _ResultStat(label: '提取', value: result.totalExtracted),
            const SizedBox(width: 12),
            _ResultStat(label: '匹配', value: result.matchedWords.length, color: Colors.green),
            const SizedBox(width: 12),
            _ResultStat(label: '未匹配', value: result.unmatchedWords.length, color: Colors.orange),
          ],
        ),
        const SizedBox(height: 16),

        // 匹配到的单词
        Text('匹配到的单词 (${result.matchedWords.length})',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: result.matchedWords.map((word) {
            final selected = _selectedWords.contains(word);
            return FilterChip(
              label: Text(word),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selectedWords.add(word);
                  } else {
                    _selectedWords.remove(word);
                  }
                });
              },
            );
          }).toList(),
        ),

        // 未匹配的单词
        if (result.unmatchedWords.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('未匹配的单词 (${result.unmatchedWords.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: result.unmatchedWords.map((word) => Chip(
              label: Text(word),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final int value;
  final Color? color;

  const _ResultStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
