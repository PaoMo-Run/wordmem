import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import 'widgets/quiz_cards.dart';

/// 熟练词抽检页面（v2.1.6）
///
/// 从「已掌握」词中抽取若干词做默写测验，检测是否真的还记得。
/// 与常规复习的区别：
/// - **只做默写**一个环节（抽检目的是"查有没有忘"，不必走完整流程）
/// - 每题作答后**立即回写**（答对 due+15 天；答错保留 mastered、due+3 天）
/// - 完成后把**答错的词返回给调用方**，汇入本轮错词池一起重测
class MasteredQuizPage extends ConsumerStatefulWidget {
  const MasteredQuizPage({super.key, required this.words});

  /// 本轮抽检的词（由 ReviewRepository.pickMasteredQuizWords 产出）
  final List<Map<String, dynamic>> words;

  @override
  ConsumerState<MasteredQuizPage> createState() => _MasteredQuizPageState();
}

class _MasteredQuizPageState extends ConsumerState<MasteredQuizPage> {
  int _index = 0;
  int _correctCount = 0;
  final List<int> _wrongIds = [];
  bool _finished = false;

  Map<String, dynamic> get _word => widget.words[_index];
  int get _total => widget.words.length;

  void _onAnswered(bool correct) {
    final id = _word['id'] as int;
    // 逐题立即回写：中途退出也不丢已完成的抽检结果
    ref.read(reviewRepositoryProvider).submitMasteredQuiz(id, correct: correct);
    if (correct) {
      _correctCount++;
    } else {
      _wrongIds.add(id);
    }
  }

  void _advance() {
    if (_index < _total - 1) {
      setState(() => _index++);
    } else {
      setState(() => _finished = true);
    }
  }

  /// 关闭并回传答错的词（供调用方汇入错词池）
  void _close() => Navigator.of(context).pop(_wrongIds);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_finished ? '抽检完成' : '熟练词抽检 ${_index + 1} / $_total'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ),
      body: _finished ? _buildResult() : _buildQuiz(),
    );
  }

  Widget _buildQuiz() {
    final audioEnabled = ref.watch(wordAudioEnabledProvider);
    final definition = ((_word['custom_def'] as String?) ?? '').trim();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: DictationCard(
          key: ValueKey('mq-${_word['id']}'),
          word: _word['word'] as String,
          definition: definition,
          showHint: true,
          onAnswered: _onAnswered,
          onNext: _advance,
          onSkip: _advance,
          isLast: _index == _total - 1,
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
        ),
      ),
    );
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    final wrong = widget.words
        .where((w) => _wrongIds.contains(w['id'] as int))
        .toList();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _wrongIds.isEmpty
                  ? Icons.verified_outlined
                  : Icons.school_outlined,
              size: 64,
              color: _wrongIds.isEmpty
                  ? AppColors.ratingGood
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '抽检完成：$_correctCount / $_total 正确',
              style: theme.textTheme.titleMedium,
            ),
            if (wrong.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '这 ${wrong.length} 个词会在本轮「重做错题」里再来一次；'
                '若重测仍答错，将退回复习队列（从 T3 重新走周期）。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              ...wrong.map(
                (w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    w['word'] as String,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _close,
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
