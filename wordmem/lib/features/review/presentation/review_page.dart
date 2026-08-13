import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/review_rating.dart';
import '../../../core/theme/colors.dart';
import 'widgets/quiz_cards.dart';

/// 今日复习页面（原"开始复习"）
///
/// 统一的三段式测验流程（与自选复习一致）：
/// 1. 英译汉（翻卡 + FSRS 四档评分）
/// 2. 选单词（看中文释义四选一）
/// 3. 默写（看释义/首字母拼写）
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  List<Map<String, dynamic>> _queue = [];
  int _index = 0;
  bool _loading = true;
  _Stage _stage = _Stage.enToZh;

  // 统计
  int _reviewedCount = 0;
  int _chooseCorrect = 0;
  int _dictationCorrect = 0;

  // 四选一选项缓存（wordId -> options）
  final Map<int, List<String>> _optionsCache = {};

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  void _loadQueue() {
    setState(() => _loading = true);
    try {
      final repo = ref.read(reviewRepositoryProvider);
      final queue = repo.getReviewQueue(limit: 100);
      setState(() {
        _queue = queue;
        _index = 0;
        _loading = false;
        _stage = _Stage.enToZh;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ============================================================
  //  当前词信息
  // ============================================================

  Map<String, dynamic> get _word => _queue[_index];
  String get _currentWord => _word['word'] as String;
  String get _currentDef => ((_word['custom_def'] as String?) ?? '').trim();
  String get _currentNote => (_word['note'] as String?) ?? '';
  bool get _isNewWord =>
      (_word['card_state'] as String? ?? 'new') == 'new' &&
      ((_word['reps'] as int?) ?? 0) == 0;
  int get _lapses => (_word['lapses'] as int?) ?? 0;

  // ============================================================
  //  阶段1：英译汉（FSRS 评分）
  // ============================================================

  void _rate(ReviewRating rating) {
    final wordId = _word['id'] as int;
    try {
      final repo = ref.read(reviewRepositoryProvider);
      repo.submitReview(wordId, rating);
      ref.read(wordListVersionProvider.notifier).state++;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('评分失败: $e')),
      );
      return;
    }
    setState(() => _reviewedCount++);
    _advanceFromEnToZh();
  }

  void _advanceFromEnToZh() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      _enterChooseWord();
    }
  }

  void _enterChooseWord() {
    // 预生成四选一选项
    _optionsCache.clear();
    final repo = ref.read(wordRepositoryProvider);
    for (final w in _queue) {
      _optionsCache[w['id'] as int] =
          repo.buildWordOptions(w['word'] as String, 4);
    }
    setState(() {
      _index = 0;
      _chooseCorrect = 0;
      _stage = _Stage.chooseWord;
    });
  }

  // ============================================================
  //  阶段2：四选一
  // ============================================================

  List<String> get _currentOptions =>
      _optionsCache[_word['id'] as int] ?? [_currentWord];

  void _chooseAnswered(bool correct) {
    if (correct) _chooseCorrect++;
  }

  void _advanceFromChoose() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      setState(() {
        _index = 0;
        _dictationCorrect = 0;
        _stage = _Stage.dictation;
      });
    }
  }

  // ============================================================
  //  阶段3：默写
  // ============================================================

  void _dictationAnswered(bool correct) {
    if (correct) _dictationCorrect++;
  }

  void _advanceFromDictation() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      setState(() => _stage = _Stage.done);
    }
  }

  // ============================================================
  //  构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('今日复习')),
        body: const LoadingIndicator(message: '加载复习队列...'),
      );
    }
    if (_stage == _Stage.done) return _buildDone();
    if (_queue.isEmpty) return _buildEmpty();
    return _buildQuiz();
  }

  Widget _buildEmpty() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日复习'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: EmptyState(
        icon: Icons.check_circle_outline,
        title: _reviewedCount > 0 ? '复习完成！' : '暂无待复习单词',
        subtitle: _reviewedCount > 0 ? '本次复习了 $_reviewedCount 个单词' : '稍后再来看看吧',
        actionLabel: '返回',
        onAction: () => context.pop(),
      ),
    );
  }

  Widget _buildQuiz() {
    final total = _queue.length;
    final progress = _index / total;

    final Widget card;
    final String title;
    switch (_stage) {
      case _Stage.enToZh:
        title = '英译汉 ${_index + 1} / $total';
        card = EnToZhCard(
          key: ValueKey('en2zh-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          note: _currentNote,
          isNew: _isNewWord,
          lapses: _lapses,
          onRate: _rate,
          onSkip: _advanceFromEnToZh,
        );
      case _Stage.chooseWord:
        title = '选单词 ${_index + 1} / $total';
        card = ChooseWordCard(
          key: ValueKey('choose-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          options: _currentOptions,
          onAnswered: _chooseAnswered,
          onNext: _advanceFromChoose,
          onSkip: _advanceFromChoose,
          isLast: _index == total - 1,
        );
      case _Stage.dictation:
        title = '默写 ${_index + 1} / $total';
        card = DictationCard(
          key: ValueKey('dict-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          showHint: true,
          onAnswered: _dictationAnswered,
          onNext: _advanceFromDictation,
          onSkip: _advanceFromDictation,
          isLast: _index == total - 1,
        );
      case _Stage.done:
        title = '';
        card = const SizedBox.shrink();
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

  Widget _buildDone() {
    final theme = Theme.of(context);
    final total = _queue.length;

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
              const Icon(Icons.check_circle_outline,
                  size: 72, color: AppColors.ratingGood),
              const SizedBox(height: 16),
              Text('今日复习全部完成',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  )),
              const SizedBox(height: 24),
              _resultRow(theme, '英译汉', '$_reviewedCount 词', Icons.translate,
                  AppColors.primary),
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
                child: FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('完成',
                      style: TextStyle(fontWeight: FontWeight.w600)),
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

enum _Stage { enToZh, chooseWord, dictation, done }
