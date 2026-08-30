import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../core/utils/tag_utils.dart';
import '../../../domain/models/word.dart';

/// 添加单词页面
///
/// 设计约定（2026-08-30 液体玻璃改版）：aurora 背景 + 玻璃卡；
/// 保存按钮用 tinted GlassButton，收藏行用玻璃分组卡。
class AddWordPage extends ConsumerStatefulWidget {
  /// 预填的单词（从词库词典搜索结果跳转时传入，自动搜索匹配）
  final String? initialWord;
  const AddWordPage({super.key, this.initialWord});

  @override
  ConsumerState<AddWordPage> createState() => _AddWordPageState();
}

class _AddWordPageState extends ConsumerState<AddWordPage> {
  final _wordController = TextEditingController();
  final _customDefController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _isFavorite = false;

  DictMatchResult? _matchResult;
  bool _searched = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final w = widget.initialWord?.trim();
    if (w != null && w.isNotEmpty) {
      _wordController.text = w;
      // 首帧后自动搜索匹配（首帧前 setState 非法）
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _wordController.dispose();
    _customDefController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _search() {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;

    setState(() => _searched = true);
    try {
      final repo = ref.read(wordRepositoryProvider);
      final result = repo.matchWord(word);
      setState(() {
        _matchResult = result;
        if (result != null) {
          final dict = result.dictWord;
          if (_customDefController.text.isEmpty && dict.translation != null) {
            _customDefController.text = dict.translation!;
          }
          // 自动填充标签：将 ECDICT 编码转为友好标签
          if (_tagsController.text.isEmpty &&
              dict.tag != null &&
              dict.tag!.isNotEmpty) {
            _tagsController.text = TagUtils.convertTags(dict.tag);
          }
        }
      });
    } catch (e) {
      setState(() => _matchResult = null);
    }
  }

  void _save() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;

    setState(() => _saving = true);

    try {
      final repo = ref.read(wordRepositoryProvider);

      // 检查是否已存在
      if (repo.exists(word)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$word" 已在词库中')),
          );
        }
        setState(() => _saving = false);
        return;
      }

      repo.addWord(
        word: word,
        customDef: _customDefController.text.trim().isNotEmpty
            ? _customDefController.text.trim()
            : null,
        note: _noteController.text.trim(),
        tags: _tagsController.text.trim(),
        isFavorite: _isFavorite,
      );

      // 触发词库列表刷新
      ref.read(wordListVersionProvider.notifier).state++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$word" 已添加到词库')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }

    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('添加单词'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          // push 页面自带 aurora 背景（MainShell 只包 tab 页）
          const AppBackground(),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 单词输入
                TextField(
                  controller: _wordController,
                  decoration: InputDecoration(
                    labelText: '单词',
                    hintText: '输入英文单词',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                ),
                const SizedBox(height: 16),

                // 词典匹配结果
                if (_searched) _buildMatchResult(theme),

                const SizedBox(height: 16),

                // 自定义释义
                TextField(
                  controller: _customDefController,
                  decoration: const InputDecoration(
                    labelText: '释义',
                    hintText: '自定义释义（覆盖词典默认释义）',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // 备注
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '个人记忆笔记、例句等',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // 标签
                TextField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    hintText: '用逗号分隔，如: 考研, 动词, 易混淆',
                  ),
                ),
                const SizedBox(height: 12),

                // 收藏（玻璃分组卡）
                GlassSection(
                  children: [
                    SwitchListTile(
                      title: const Text('收藏'),
                      value: _isFavorite,
                      onChanged: (v) => setState(() => _isFavorite = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 保存按钮（tinted glass 主 CTA）
                GlassButton(
                  onPressed: _saving ? null : _save,
                  icon: Icons.add,
                  label: _saving ? '保存中...' : '添加到词库',
                  tinted: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchResult(ThemeData theme) {
    if (_matchResult == null) {
      return GlassContainer(
        blur: 16,
        child: Column(
          children: [
            Icon(Icons.search_off, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text('未在词典中找到该单词',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 4),
            Text('你可以手动填写释义后添加',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      );
    }

    final dict = _matchResult!.dictWord;
    final relation = _matchResult!.exchangeRelation;

    return GlassContainer(
      blur: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                dict.word,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (dict.phonetic != null && dict.phonetic!.isNotEmpty)
                Text(
                  '/${dict.phonetic}/',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (relation != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '输入的词是 "${dict.word}" 的$relation',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
          if (dict.pos != null && dict.pos!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(dict.pos!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
          if (dict.translation != null && dict.translation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(dict.translation!,
                style: theme.textTheme.bodyMedium),
          ],
          if (dict.tag != null && dict.tag!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: TagUtils.convertTagList(dict.tag)
                  .map((t) => Chip(
                        label: Text(t, style: theme.textTheme.labelSmall),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
