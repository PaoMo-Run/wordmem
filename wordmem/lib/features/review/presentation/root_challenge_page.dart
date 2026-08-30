import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../domain/services/root_matcher.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';

/// 词根挑战页
/// 流程：词根卡片（弹层）→ 逐题（≤5 题，词根加粗，4 选 1 释义）→ 汇总
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 玻璃卡。
class RootChallengePage extends ConsumerStatefulWidget {
  final RootMatch match;
  const RootChallengePage({super.key, required this.match});

  @override
  ConsumerState<RootChallengePage> createState() =>
      _RootChallengePageState();
}

class _Question {
  final String word;
  final List<String> options; // 4 个选项
  final int correctIndex;

  const _Question({
    required this.word,
    required this.options,
    required this.correctIndex,
  });
}

class _RootChallengePageState extends ConsumerState<RootChallengePage> {
  // 阶段：intro(词根卡片) → quiz(逐题) → result(汇总)
  String _phase = 'intro';

  List<_Question> _questions = [];
  int _index = 0;
  int? _selected;
  bool _submitted = false;
  int _correct = 0;
  bool _passedThisRound = false;
  int _masteryAfter = 0;

  final List<_AnswerRecord> _records = [];

  RootMatch get match => widget.match;

  /// 深浅模式自适应的语义色（深色模式取亮化版本，保证对比度）
  Color _semantic(ThemeData theme, Color light, Color dark) =>
      theme.brightness == Brightness.dark ? dark : light;

  @override
  void initState() {
    super.initState();
    _buildQuestions();
    // 页面就绪后自动弹出词根卡片
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase == 'intro') _showRootCard();
    });
  }

  Future<void> _buildQuestions() async {
    // 最多取 5 个匹配词（打乱），构建 4 选 1 题目
    final words = List.of(match.words)..shuffle();
    final picked = words.take(math.min(5, words.length)).toList();

    final dictSource = ref.read(dictSourceProvider);
    final wordDao = ref.read(wordDaoProvider);

    final questions = <_Question>[];
    for (final w in picked) {
      // 释义：优先用户 custom_def，缺失查词典
      String correctDef = '';
      final row = wordDao.getByWord(w);
      final custom = row?['custom_def'] as String?;
      if (custom != null && custom.trim().isNotEmpty) {
        correctDef = custom.trim();
      } else {
        correctDef = dictSource.lookup(w)?.translation ?? '';
      }
      if (correctDef.isEmpty) continue;

      // 干扰项：其他题目的释义 + 词典随机词释义
      final distractors = <String>[];
      for (final other in picked) {
        if (other == w || distractors.length >= 3) continue;
        final otherRow = wordDao.getByWord(other);
        var def = otherRow?['custom_def'] as String?;
        if (def == null || def.trim().isEmpty) {
          def = dictSource.lookup(other)?.translation ?? '';
        }
        if (def.isNotEmpty && def != correctDef) distractors.add(def.trim());
      }
      // 不足 3 个时从词根 examples 的释义补
      var fallbackIdx = 0;
      while (distractors.length < 3 && fallbackIdx < match.root.examples.length) {
        final ex = match.root.examples[fallbackIdx];
        fallbackIdx++;
        if (ex == w) continue;
        final def = dictSource.lookup(ex)?.translation ?? '';
        if (def.isNotEmpty && def != correctDef && !distractors.contains(def)) {
          distractors.add(def);
        }
      }
      if (distractors.length < 3) continue;

      final options = [correctDef, ...distractors]..shuffle();
      questions.add(_Question(
        word: w,
        options: options,
        correctIndex: options.indexOf(correctDef),
      ));
    }

    if (mounted) {
      setState(() {
        _questions = questions;
        // 题目不足 2 题时直接展示空态引导
        if (_questions.length < 2) {
          _phase = 'empty';
        }
      });
    }
  }

  // ---------- 词根卡片 ----------
  void _showRootCard() {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                match.root.root.toUpperCase(),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${match.root.meaning} · ${match.root.meaningEn}',
                style: theme.textTheme.titleMedium,
              ),
              if (match.root.variants.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '变体：${match.root.variants.join(' / ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  match.words.take(4).join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '共 ${match.words.length} 个关联词，做 ${math.min(5, match.words.length)} 题',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _phase = 'quiz');
                  },
                  child: const Text('开始答题'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 逐题 ----------
  void _submit() {
    if (_submitted || _selected == null) return;
    final q = _questions[_index];
    final isCorrect = _selected == q.correctIndex;
    setState(() {
      _submitted = true;
      if (isCorrect) _correct++;
      _records.add(_AnswerRecord(
        word: q.word,
        correctDef: q.options[q.correctIndex],
        userDef: q.options[_selected!],
        isCorrect: isCorrect,
      ));
    });
  }

  void _next() {
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _selected = null;
        _submitted = false;
      });
    } else {
      _commitMastery();
      setState(() => _phase = 'result');
    }
  }

  /// 正确率 ≥ 80% 视为通过：词根熟悉度 +1（封顶 4）
  void _commitMastery() {
    final total = _questions.length;
    if (total == 0) return;
    _passedThisRound = _correct / total >= 0.8;
    if (_passedThisRound) {
      _masteryAfter =
          ref.read(wordRepositoryProvider).bumpRootMastery(match.root.root);
      // 通知词群记忆页刷新熟悉度
      ref.read(groupVersionProvider.notifier).state++;
    }
  }

  /// 人工复核：点击单词跳转对应单词详情页（可手动从词根移出）
  void _openWordDetail(String w) {
    final row = ref.read(wordDaoProvider).getByWord(w);
    final id = row?['id'] as int?;
    if (id == null) return;
    context.push('/word/$id');
  }

  // ---------- 汇总 ----------
  void _retry() {
    setState(() {
      _phase = 'quiz';
      _index = 0;
      _selected = null;
      _submitted = false;
      _correct = 0;
      _records.clear();
    });
    _buildQuestions();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('词根挑战 · ${match.root.root}'),
      ),
      body: Stack(
        children: [
          const AppBackground(),
          switch (_phase) {
            'empty' => Center(
                child: Text(
                    '可出题数量不足（<2），请先添加更多含「${match.root.root}」的单词',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center),
              ),
            'intro' => const SizedBox.shrink(),
            'quiz' => _buildQuiz(theme),
            'result' => _buildResult(theme),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }

  Widget _buildQuiz(ThemeData theme) {
    if (_questions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final q = _questions[_index];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 进度
          LinearProgressIndicator(
            value: (_index + 1) / _questions.length,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text('第 ${_index + 1}/${_questions.length} 题',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),

          // 单词（词根加粗高亮；提交后点击可跳详情页人工复核）
          InkWell(
            onTap: _submitted ? () => _openWordDetail(q.word) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              child: Text.rich(
                _buildWordSpan(q.word, theme),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (_submitted)
            Text(
              '点击单词可查看详情并人工调整词根归属',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          Text('请选出该单词的正确释义',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),

          // 4 选 1（状态色深浅自适应：正确绿 / 错误红 / 选中品牌色）
          ...List.generate(q.options.length, (i) {
            final option = q.options[i];
            final selected = _selected == i;
            final isCorrectOpt = i == q.correctIndex;
            final correctColor = _semantic(
                theme, AppColors.ratingGood, AppColors.ratingGoodDark);
            final wrongColor = _semantic(
                theme, AppColors.ratingAgain, AppColors.ratingAgainDark);
            Color? bg;
            Color? border;
            if (_submitted) {
              if (isCorrectOpt) {
                bg = correctColor.withValues(alpha: 0.14);
                border = correctColor;
              } else if (selected) {
                bg = wrongColor.withValues(alpha: 0.14);
                border = wrongColor;
              }
            } else if (selected) {
              bg = theme.colorScheme.primary.withValues(alpha: 0.12);
              border = theme.colorScheme.primary;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _submitted
                    ? null
                    : () => setState(() => _selected = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(
                        color: border ?? theme.colorScheme.outlineVariant,
                        width: border != null ? 1.6 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(option,
                              style: theme.textTheme.bodyMedium)),
                      if (_submitted && isCorrectOpt)
                        Icon(Icons.check_circle,
                            color: correctColor, size: 20),
                      if (_submitted && selected && !isCorrectOpt)
                        Icon(Icons.cancel,
                            color: wrongColor, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),

          const Spacer(),
          // 提交 / 下一题
          GlassButton(
            onPressed: _submitted
                ? _next
                : (_selected == null ? null : _submit),
            label: _submitted
                ? (_index < _questions.length - 1 ? '下一题' : '查看结果')
                : '提交',
            tinted: true,
          ),
        ],
      ),
    );
  }

  /// 词根加粗高亮：SPECTator
  TextSpan _buildWordSpan(String word, ThemeData theme) {
    final lower = word.toLowerCase();
    // 找到词根出现位置
    int? start;
    String? form;
    for (final f in match.root.forms) {
      if (f.length < 3) continue;
      final idx = lower.indexOf(f);
      if (idx != -1) {
        start = idx;
        form = f;
        break;
      }
    }
    if (start == null || form == null) {
      return TextSpan(text: word);
    }
    return TextSpan(children: [
      TextSpan(text: word.substring(0, start)),
      TextSpan(
        text: word.substring(start, start + form.length),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w900,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
      ),
      TextSpan(text: word.substring(start + form.length)),
    ]);
  }

  Widget _buildResult(ThemeData theme) {
    final total = _records.length;
    final rate = total == 0 ? 0 : (_correct / total * 100).round();
    final correctColor =
        _semantic(theme, AppColors.ratingGood, AppColors.ratingGoodDark);
    final wrongColor =
        _semantic(theme, AppColors.ratingAgain, AppColors.ratingAgainDark);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        Text('作答完成', textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('正确 $_correct/$total · 正确率 $rate%',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _correct == total ? correctColor : theme.colorScheme.primary,
            )),
        if (_passedThisRound) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: correctColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: correctColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              '通过！词根熟悉度 +1（$_masteryAfter / 4）',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: correctColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        ..._records.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassContainer(
                // 列表条目：静态玻璃（blur 0）
                blur: 0,
                elevated: false,
                radius: 14,
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => _openWordDetail(r.word),
                  leading: Icon(
                    r.isCorrect ? Icons.check_circle : Icons.cancel,
                    color: r.isCorrect ? correctColor : wrongColor,
                  ),
                  title: Text.rich(_buildWordSpan(r.word, theme)),
                  subtitle: Text('释义：${r.correctDef}'
                      '${r.isCorrect ? '' : '\n你的选择：${r.userDef}'}'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                ),
              ),
            )),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('再测一次'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassButton(
                onPressed: () => context.pop(),
                icon: Icons.arrow_back,
                label: '返回词群记忆',
                tinted: true,
                height: 48,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnswerRecord {
  final String word;
  final String correctDef;
  final String userDef;
  final bool isCorrect;

  const _AnswerRecord({
    required this.word,
    required this.correctDef,
    required this.userDef,
    required this.isCorrect,
  });
}
