import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass.dart';
import '../../../domain/models/synonym_challenge.dart';
import '../../../core/theme/colors.dart';

/// 近义词挑战页面
///
/// 每道题：上方中文释义，下方 8 个单词（2~4 个正确近义词）。
/// 用户至少选出 2 个正确答案即为通过。支持跳过。
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 玻璃卡 + 评分色深浅自适应。
class SynonymChallengePage extends ConsumerStatefulWidget {
  const SynonymChallengePage({super.key});

  @override
  ConsumerState<SynonymChallengePage> createState() =>
      _SynonymChallengePageState();
}

class _SynonymChallengePageState extends ConsumerState<SynonymChallengePage> {
  List<SynonymChallenge> _challenges = [];
  int _index = 0;
  int _passed = 0;
  bool _loading = true;
  bool _finished = false;

  final Set<String> _selected = {};
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    Future.microtask(() {
      final repo = ref.read(wordRepositoryProvider);
      final challenges = repo.buildSynonymChallenges(count: 10);
      if (!mounted) return;
      setState(() {
        _challenges = challenges;
        _loading = false;
      });
    });
  }

  SynonymChallenge get _challenge => _challenges[_index];

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

  int get _correctSelected =>
      _selected.where((w) => _challenge.correct.contains(w)).length;
  bool get _passedCurrent => _correctSelected >= 2;

  void _submit() {
    setState(() {
      _submitted = true;
      if (_passedCurrent) _passed++;
    });
  }

  void _next() {
    if (_index < _challenges.length - 1) {
      setState(() {
        _index++;
        _selected.clear();
        _submitted = false;
      });
    } else {
      setState(() => _finished = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('近义词挑战'),
          backgroundColor: Colors.transparent,
        ),
        body: const Stack(
          fit: StackFit.expand,
          children: [
            LoadingIndicator(message: '生成挑战题目...'),
          ],
        ),
      );
    }
    if (_finished) return _buildResult();
    if (_challenges.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('近义词挑战'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Stack(
          fit: StackFit.expand,
          children: [
            EmptyState(
              icon: Icons.hub_outlined,
              title: '暂无可挑战的近义词',
              subtitle: '词库中近义词不足，请先添加更多单词',
            ),
          ],
        ),
      );
    }
    return _buildQuiz();
  }

  // 深浅自适应的评分色（dark 亮化版，保证对比度）
  Color get _goodColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingGoodDark
      : AppColors.ratingGood;
  Color get _againColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingAgainDark
      : AppColors.ratingAgain;

  Widget _buildQuiz() {
    final theme = Theme.of(context);
    final challenge = _challenge;
    final total = _challenges.length;
    final progress = _index / total;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('近义词挑战 ${_index + 1} / $total'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              LinearProgressIndicator(value: progress, minHeight: 3),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '选出与下列释义对应的近义词（至少选 2 个）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // 释义（玻璃卡）
                      GlassContainer(
                        blur: 0,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          challenge.definition,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 8 个单词选项
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: challenge.options.map((word) {
                          return _buildOptionChip(theme, word, challenge);
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      if (_submitted) ...[
                        Text(
                          _passedCurrent
                              ? '通过！选对 $_correctSelected 个近义词'
                              : '未通过（至少需选 2 个，当前选对 $_correctSelected 个）',
                          style: TextStyle(
                            color: _passedCurrent
                                ? _goodColor
                                : _againColor,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        // 漏选 / 错选单词的释义
                        ..._buildReviewDefinitions(challenge),
                        const SizedBox(height: 16),
                        GlassButton(
                          onPressed: _next,
                          label: _index < total - 1 ? '下一题' : '完成',
                          tinted: true,
                          height: 48,
                          blur: 0,
                        ),
                      ] else
                        GlassButton(
                          onPressed: _selected.length >= 2 ? _submit : null,
                          label: _selected.length >= 2
                              ? '提交（已选 ${_selected.length} 个）'
                              : '至少选择 2 个单词',
                          tinted: true,
                          height: 48,
                          blur: 0,
                        ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _next,
                        icon: const Icon(Icons.skip_next, size: 18),
                        label: const Text('跳过'),
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

  /// 提交后生成漏选 / 错选单词的释义卡片
  List<Widget> _buildReviewDefinitions(SynonymChallenge challenge) {
    final dict = ref.read(dictSourceProvider);
    final widgets = <Widget>[];
    // 漏选：正确答案里没被选中的
    for (final w in challenge.correct) {
      if (_selected.contains(w)) continue;
      final d = dict.lookup(w);
      if (d != null && (d.translation?.isNotEmpty ?? false)) {
        widgets.add(_defRow(w, d.translation!, missed: true));
      }
    }
    // 错选：选中但不是正确答案的
    for (final w in _selected) {
      if (challenge.correct.contains(w)) continue;
      final d = dict.lookup(w);
      if (d != null && (d.translation?.isNotEmpty ?? false)) {
        widgets.add(_defRow(w, d.translation!, missed: false));
      }
    }
    return widgets;
  }

  Widget _defRow(String word, String definition, {required bool missed}) {
    final theme = Theme.of(context);
    final color = missed ? _againColor : AppColors.ratingHard;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${missed ? '漏选' : '错选'} · $word',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            definition,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(
      ThemeData theme, String word, SynonymChallenge challenge) {
    final selected = _selected.contains(word);
    final isCorrect = challenge.correct.contains(word);

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
      onTap: _submitted ? null : () => _toggle(word),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border ?? theme.dividerColor, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          word,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    final total = _challenges.length;
    final percent = total > 0 ? (_passed * 100 ~/ total) : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('挑战完成'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    percent >= 60 ? Icons.emoji_events : Icons.hub_outlined,
                    size: 72,
                    color: percent >= 60
                        ? AppColors.ratingEasy
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text('近义词挑战完成',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    '通过 $_passed / $total 题',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '通过率 $percent%',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: percent >= 60 ? _goodColor : _againColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  GlassButton(
                    onPressed: () => context.pop(),
                    label: '完成',
                    tinted: true,
                    height: 48,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
