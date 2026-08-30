import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/mastery_badge.dart';
import '../../../core/theme/colors.dart';

/// 近义词群专属挑战页
///
/// 从「词群记忆 - 近义词群」进入：按群依次出题，
/// 每题题干为该群核心中文释义，8 个单词选项（组内近义词 + 干扰项），
/// 答对 ≥ 3 个（组内正确项不足 3 个时须全对）即通过；
/// 通过后该群熟悉度 +1（封顶 4），并询问是否测下一个词条。
class SynonymGroupChallengePage extends ConsumerStatefulWidget {
  /// 待测词群列表（按展示顺序），每项含 def / words / id
  final List<Map<String, dynamic>> groups;
  /// 从第几个词群开始测（默认 0）
  final int startIndex;

  const SynonymGroupChallengePage({
    super.key,
    required this.groups,
    this.startIndex = 0,
  });

  @override
  ConsumerState<SynonymGroupChallengePage> createState() =>
      _SynonymGroupChallengePageState();
}

class _SynonymGroupChallengePageState
    extends ConsumerState<SynonymGroupChallengePage> {
  late int _index;
  final Set<String> _selected = {};
  bool _submitted = false;
  bool _passed = false;
  int _mastery = 0;

  Map<String, dynamic>? _challenge;

  /// 选项释义缓存（提交后展示，懒加载）
  final Map<String, String> _defs = {};

  /// 获取单词释义（词典首行，供提交后展示）
  String _defOf(String word) {
    return _defs.putIfAbsent(word, () {
      final dict = ref.read(dictSourceProvider);
      final w = dict.lookup(word);
      final t = w?.translation?.trim() ?? '';
      if (t.isEmpty) return '暂无释义';
      final first = t.split('\n').first.trim();
      return first.length > 60 ? '${first.substring(0, 60)}…' : first;
    });
  }

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex.clamp(0, widget.groups.length - 1);
    _loadMastery();
    _buildChallenge();
  }

  Map<String, dynamic> get _group => widget.groups[_index];
  int get _requiredCorrect => (_challenge?['requiredCorrect'] as int?) ?? 3;

  void _loadMastery() {
    final repo = ref.read(wordRepositoryProvider);
    _mastery = repo.getSynonymGroupMastery()[_group['id'] as String? ?? ''] ?? 0;
  }

  void _buildChallenge() {
    final repo = ref.read(wordRepositoryProvider);
    _challenge =
        repo.buildGroupChallenge((_group['words'] as List).cast<String>());
  }

  int get _correctSelected => _selected
      .where((w) => (_challenge!['correct'] as List).contains(w))
      .length;
  bool get _passedCurrent => _correctSelected >= _requiredCorrect;

  void _toggle(String word) {
    if (_submitted) return;
    setState(() {
      if (_selected.contains(word)) {
        _selected.remove(word);
      } else {
        _selected.add(word);
      }
    });
  }

  void _submit() {
    setState(() {
      _submitted = true;
      _passed = _passedCurrent;
    });
    if (_passed) {
      final repo = ref.read(wordRepositoryProvider);
      _mastery =
          repo.bumpSynonymGroupMastery(_group['id'] as String? ?? '');
      // 通知词群记忆页刷新熟悉度
      ref.read(groupVersionProvider.notifier).state++;
    }
    // 提交后立即弹出通过反馈对话框，关闭后停留在作答详情
    _showFeedback();
  }

  /// 通过反馈对话框（纯反馈，继续操作走页面下方"下一题/完成"按钮）
  Future<void> _showFeedback() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_passed ? '本群通过！' : '本群未通过'),
        content: Text(
          _passed
              ? '熟悉度 +1（${(_mastery - 1).clamp(0, 4)} → $_mastery / 4）'
              : '正确 $_correctSelected/$_requiredCorrect，未达通过线；'
                  '已展示作答详情，可以再测一次巩固。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 进入下一个词群（最后一个则返回列表页）
  void _nextGroup() {
    if (_index < widget.groups.length - 1) {
      setState(() {
        _index++;
        _selected.clear();
        _submitted = false;
        _passed = false;
      });
      _loadMastery();
      _buildChallenge();
    } else {
      context.pop();
    }
  }

  /// 人工复核：提交后点击选项单词，跳转对应单词详情页（可手动移出词林/词根）
  void _openWordDetail(String w) {
    final row = ref.read(wordDaoProvider).getByWord(w);
    final id = row?['id'] as int?;
    if (id == null) return;
    context.push('/word/$id');
  }

  @override
  Widget build(BuildContext context) {
    if (_challenge == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('近义词群挑战'),
          backgroundColor: Colors.transparent,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('该群无法出题'),
                  const SizedBox(height: 12),
                  GlassButton(
                    onPressed: () => context.pop(),
                    label: '返回',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _buildQuiz();
  }

  // 深浅自适应的评分色（dark 亮化版）
  Color get _goodColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingGoodDark
      : AppColors.ratingGood;
  Color get _againColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingAgainDark
      : AppColors.ratingAgain;

  Widget _buildQuiz() {
    final theme = Theme.of(context);
    final total = widget.groups.length;
    final challenge = _challenge!;
    final correct = (challenge['correct'] as List).cast<String>();
    final options = (challenge['options'] as List).cast<String>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('近义词群 ${_index + 1} / $total'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              LinearProgressIndicator(
                  value: (_index + 1) / total, minHeight: 3),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '选出含有该释义的近义词（至少选 $_requiredCorrect 个）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MasteryBadge(level: _mastery),
                          const SizedBox(width: 6),
                          Text(
                            '第 $_mastery / 4 级',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 核心中文释义（玻璃卡）
                      GlassContainer(
                        blur: 0,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _group['def'] as String? ?? '',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  const SizedBox(height: 24),
                  // 单词选项（横屏/宽屏自动换行，宽屏可用网格）
                  LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth > 600;
                    if (wide) {
                      return GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: _submitted ? 1.9 : 3.2,
                        children:
                            options.map((w) => _buildOptionChip(theme, w)).toList(),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children:
                          options.map((w) => _buildOptionChip(theme, w)).toList(),
                    );
                  }),
                  const SizedBox(height: 24),
                  if (_submitted) ...[
                    Text(
                      _passed
                          ? '通过！选对 $_correctSelected 个近义词'
                          : '未通过（需选对 $_requiredCorrect 个，当前选对 $_correctSelected 个）',
                      style: TextStyle(
                        color: _passed ? _goodColor : _againColor,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // 正确答案展示
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: correct.map((w) {
                        final hit = _selected.contains(w);
                        return Chip(
                          label: Text(w),
                          avatar: Icon(
                            hit
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: hit
                                ? _goodColor
                                : theme.colorScheme.outline,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      onPressed: _nextGroup,
                      label: _index < widget.groups.length - 1 ? '下一题' : '完成',
                      tinted: true,
                      height: 48,
                      blur: 0,
                    ),
                  ] else
                    GlassButton(
                      onPressed: _selected.length >= _requiredCorrect
                          ? _submit
                          : null,
                      label: _selected.length >= _requiredCorrect
                          ? '提交（已选 ${_selected.length} 个）'
                          : '至少选择 $_requiredCorrect 个单词',
                      tinted: true,
                      height: 48,
                      blur: 0,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      ],
    ),
    );
  }

  Widget _buildOptionChip(ThemeData theme, String word) {
    final selected = _selected.contains(word);
    final isCorrect =
        (_challenge!['correct'] as List).contains(word);

    Color? bg;
    Color? border;
    Color fg = theme.colorScheme.onSurface;

    if (_submitted) {
      if (isCorrect) {
        bg = _goodColor.withValues(alpha: 0.15);
        border = _goodColor;
        fg = _goodColor;
      } else if (selected) {
        bg = _againColor.withValues(alpha: 0.15);
        border = _againColor;
        fg = _againColor;
      }
    } else if (selected) {
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.4);
      border = theme.colorScheme.primary;
      fg = theme.colorScheme.primary;
    }

    return InkWell(
      // 提交后：点击选项跳转对应单词详情页（人工复核：可手动移出词林/词根）
      onTap: _submitted ? () => _openWordDetail(word) : () => _toggle(word),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border ?? theme.dividerColor, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: fg),
            ),
            if (_submitted) ...[
              const SizedBox(height: 3),
              Text(
                _defOf(word),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  height: 1.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
