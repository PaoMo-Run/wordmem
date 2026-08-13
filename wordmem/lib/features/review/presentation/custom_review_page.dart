import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../domain/models/review_rating.dart';
import '../../../core/theme/colors.dart';
import 'widgets/quiz_cards.dart';

/// 自选复习页面
///
/// 按"添加日期"筛选词汇，采用与今日复习一致的三段式测验：
/// 英译汉翻卡 → 四选一 → 默写。纯练习，不更新 FSRS 排程。
class CustomReviewPage extends ConsumerStatefulWidget {
  const CustomReviewPage({super.key});

  @override
  ConsumerState<CustomReviewPage> createState() => _CustomReviewPageState();
}

class _CustomReviewPageState extends ConsumerState<CustomReviewPage> {
  _Phase _phase = _Phase.setup;

  // —— 设置 ——
  int _preset = 5; // 默认"全部"
  bool _useCustom = false;
  DateTimeRange? _customRange;

  // —— 测验 ——
  List<Map<String, dynamic>> _queue = [];
  int _index = 0;
  _QuizStage _stage = _QuizStage.enToZh;

  // —— 统计 ——
  int _enToZhCorrect = 0;
  int _chooseCorrect = 0;
  int _dictationCorrect = 0;

  final Map<int, List<String>> _optionsCache = {};

  String _rangeLabel = '';

  static const _presetLabels = ['今天', '昨天', '近3天', '近7天', '近30天', '全部'];

  // ============================================================
  //  日期范围
  // ============================================================

  (DateTime, DateTime) _rangeForPreset(int p) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    switch (p) {
      case 0:
        return (startOfToday, endOfToday);
      case 1:
        return (startOfToday.subtract(const Duration(days: 1)), startOfToday);
      case 2:
        return (startOfToday.subtract(const Duration(days: 2)), endOfToday);
      case 3:
        return (startOfToday.subtract(const Duration(days: 6)), endOfToday);
      case 4:
        return (startOfToday.subtract(const Duration(days: 29)), endOfToday);
      default:
        return (DateTime(2000), DateTime(2100));
    }
  }

  (DateTime, DateTime) _resolveRange() {
    if (_useCustom && _customRange != null) {
      return (_customRange!.start, _customRange!.end.add(const Duration(days: 1)));
    }
    return _rangeForPreset(_preset);
  }

  String get _label {
    if (_useCustom && _customRange != null) {
      final s = _customRange!.start;
      final e = _customRange!.end;
      return '${s.year}/${s.month}/${s.day} ~ ${e.year}/${e.month}/${e.day}';
    }
    return _presetLabels[_preset];
  }

  int _previewCount() {
    try {
      final (s, e) = _resolveRange();
      return ref.read(wordDaoProvider).getWordsAddedBetween(s, e).length;
    } catch (_) {
      return -1;
    }
  }

  // ============================================================
  //  开始 / 测验
  // ============================================================

  void _startQuiz() {
    final (s, e) = _resolveRange();
    final List<Map<String, dynamic>> rows;
    try {
      rows = ref.read(wordDaoProvider).getWordsAddedBetween(s, e);
    } catch (err) {
      _toast('读取词库失败: $err');
      return;
    }
    if (rows.isEmpty) {
      _toast('所选范围内没有单词');
      return;
    }
    rows.shuffle();
    // 预生成四选一选项
    _optionsCache.clear();
    final repo = ref.read(wordRepositoryProvider);
    for (final w in rows) {
      _optionsCache[w['id'] as int] = repo.buildWordOptions(w['word'] as String, 4);
    }
    setState(() {
      _queue = rows;
      _index = 0;
      _stage = _QuizStage.enToZh;
      _enToZhCorrect = 0;
      _chooseCorrect = 0;
      _dictationCorrect = 0;
      _rangeLabel = _label;
      _phase = _Phase.quiz;
    });
  }

  Map<String, dynamic> get _word => _queue[_index];
  String get _currentWord => _word['word'] as String;
  String get _currentDef => ((_word['custom_def'] as String?) ?? '').trim();
  String get _currentNote => (_word['note'] as String?) ?? '';
  List<String> get _currentOptions =>
      _optionsCache[_word['id'] as int] ?? [_currentWord];

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 英译汉（自选复习不更新 FSRS，仅统计记住与否）
  void _rate(ReviewRating rating) {
    if (rating == ReviewRating.good || rating == ReviewRating.easy) {
      _enToZhCorrect++;
    }
    _advanceEnToZh();
  }

  void _advanceEnToZh() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      setState(() {
        _index = 0;
        _stage = _QuizStage.chooseWord;
      });
    }
  }

  void _chooseAnswered(bool correct) {
    if (correct) _chooseCorrect++;
  }

  void _advanceChoose() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      setState(() {
        _index = 0;
        _stage = _QuizStage.dictation;
      });
    }
  }

  void _dictationAnswered(bool correct) {
    if (correct) _dictationCorrect++;
  }

  void _advanceDictation() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      setState(() => _phase = _Phase.result);
    }
  }

  // ============================================================
  //  构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.setup => _buildSetup(),
      _Phase.quiz => _buildQuiz(),
      _Phase.result => _buildResult(),
    };
  }

  Widget _buildSetup() {
    final theme = Theme.of(context);
    final count = _previewCount();

    return Scaffold(
      appBar: AppBar(
        title: const Text('自选复习'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '自选复习为纯练习模式，不影响学习算法排程。包含英译汉、选单词、默写三个环节。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('选择词汇范围',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_presetLabels.length, (i) {
              final selected = !_useCustom && _preset == i;
              return ChoiceChip(
                label: Text(_presetLabels[i]),
                selected: selected,
                onSelected: (_) => setState(() {
                  _useCustom = false;
                  _preset = i;
                }),
              );
            }),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(_useCustom && _customRange != null ? _label : '自定义日期范围'),
            style: _useCustom
                ? OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (count >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                count > 0 ? '共 $count 个单词' : '该范围内暂无单词',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: count > 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _startQuiz,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始自选复习'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: initial,
      helpText: '选择添加日期范围',
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _useCustom = true;
      });
    }
  }

  Widget _buildQuiz() {
    final total = _queue.length;
    final progress = _index / total;

    final Widget card;
    final String title;
    switch (_stage) {
      case _QuizStage.enToZh:
        title = '英译汉 ${_index + 1} / $total';
        card = EnToZhCard(
          key: ValueKey('en2zh-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          note: _currentNote,
          onRate: _rate,
          onSkip: _advanceEnToZh,
        );
      case _QuizStage.chooseWord:
        title = '选单词 ${_index + 1} / $total';
        card = ChooseWordCard(
          key: ValueKey('choose-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          options: _currentOptions,
          onAnswered: _chooseAnswered,
          onNext: _advanceChoose,
          onSkip: _advanceChoose,
          isLast: _index == total - 1,
        );
      case _QuizStage.dictation:
        title = '默写 ${_index + 1} / $total';
        card = DictationCard(
          key: ValueKey('dict-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          showHint: true,
          onAnswered: _dictationAnswered,
          onNext: _advanceDictation,
          onSkip: _advanceDictation,
          isLast: _index == total - 1,
        );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: progress, minHeight: 3),
          Expanded(child: card),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    final total = _queue.length;
    final percent = total > 0
        ? ((_enToZhCorrect + _chooseCorrect + _dictationCorrect) * 100 ~/
            (total * 3))
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('复习完成'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                percent >= 80 ? Icons.emoji_events : Icons.check_circle_outline,
                size: 72,
                color: percent >= 80 ? AppColors.ratingEasy : theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text('本轮自选复习完成',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  )),
              const SizedBox(height: 8),
              Text(
                '综合正确率 $percent%',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: percent >= 80 ? AppColors.ratingGood : AppColors.ratingAgain,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '范围：$_rangeLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              _resultRow(theme, '英译汉', '$_enToZhCorrect / $total',
                  Icons.translate, AppColors.primary),
              const SizedBox(height: 8),
              _resultRow(theme, '选单词', '$_chooseCorrect / $total',
                  Icons.checklist, AppColors.ratingEasy),
              const SizedBox(height: 8),
              _resultRow(theme, '默写', '$_dictationCorrect / $total',
                  Icons.edit_note, AppColors.ratingHard),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _startQuiz,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再来一轮'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(
      ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Phase { setup, quiz, result }
enum _QuizStage { enToZh, chooseWord, dictation }
