import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/review_rating.dart';
import '../../../domain/models/word_option.dart';
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

  // 三环节各词作答结果（wordId -> 是否正确；null=跳过/未作答）
  final Map<int, bool> _enToZhResults = {};
  final Map<int, bool> _chooseResults = {};
  final Map<int, bool> _dictResults = {};

  // 四选一选项缓存（wordId -> options）
  final Map<int, List<WordOption>> _optionsCache = {};
  // 英译汉选择题选项缓存（wordId -> 中文释义选项）
  final Map<int, List<WordOption>> _enToZhOptionsCache = {};
  // 该词是否有可用中文释义（无则跳过英译汉环节）
  final Map<int, bool> _enToZhAvailable = {};

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
      _prepareStages();
      _skipUnavailableEnToZh();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// 跳过无中文释义的词（英译汉环节无法出题，不计对错）
  void _skipUnavailableEnToZh() {
    while (_index < _queue.length &&
        !(_enToZhAvailable[_word['id'] as int] ?? false)) {
      _index++;
    }
    if (_index >= _queue.length) {
      _enterChooseWord();
    }
  }

  /// 预生成两个环节的选项：
  /// - 四选一（选单词）：看中文选英文
  /// - 英译汉选择题：看英文选中文（正确项 = 该词释义；干扰项 = 其它词释义）
  /// 释义来源：自定义释义优先，缺失时回退词典 translation；两者皆空则跳过英译汉环节。
  void _prepareStages() {
    _optionsCache.clear();
    _enToZhOptionsCache.clear();
    _enToZhAvailable.clear();
    final repo = ref.read(wordRepositoryProvider);
    final dict = ref.read(dictSourceProvider);

    final defs = <int, String>{};
    for (final w in _queue) {
      var def = ((w['custom_def'] as String?) ?? '').trim();
      if (def.isEmpty) {
        final d = dict.lookup(w['word'] as String);
        def = (d?.translation ?? '').trim();
      }
      defs[w['id'] as int] = def;
      _enToZhAvailable[w['id'] as int] = def.isNotEmpty;
    }

    for (final w in _queue) {
      final id = w['id'] as int;
      _optionsCache[id] = repo.buildWordOptions(
        w['word'] as String,
        4,
        correctDef: (w['custom_def'] as String?) ?? '',
      );

      final correctDef = defs[id] ?? '';
      if (correctDef.isEmpty) {
        _enToZhOptionsCache[id] = const [];
        continue;
      }
      final correctWord = w['word'] as String;
      final options = <WordOption>[
        WordOption(word: correctWord, definition: correctDef),
      ];
      final seenDefs = <String>{correctDef};
      for (final other in _queue) {
        if (options.length >= 4) break;
        final oid = other['id'] as int;
        if (oid == id) continue;
        final odef = defs[oid] ?? '';
        if (odef.isEmpty || !seenDefs.add(odef)) continue;
        options.add(WordOption(word: other['word'] as String, definition: odef));
      }
      _enToZhOptionsCache[id] = options..shuffle();
    }
  }

  // ============================================================
  //  当前词信息
  // ============================================================

  Map<String, dynamic> get _word => _queue[_index];
  String get _currentWord => _word['word'] as String;
  String get _currentDef => ((_word['custom_def'] as String?) ?? '').trim();

  // 三环节统计（作答过才计数，跳过的环节不计）
  int get _enToZhCorrect => _enToZhResults.values.where((v) => v).length;
  int get _enToZhAnsweredCount => _enToZhResults.length;

  // ============================================================
  //  阶段1：英译汉（选择题，记录对错，不立即提交）
  // ============================================================

  void _enToZhAnswered(bool correct) {
    _enToZhResults[_word['id'] as int] = correct;
    setState(() => _reviewedCount++);
  }

  void _advanceFromEnToZh() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
      _skipUnavailableEnToZh();
      if (_index >= _queue.length) _enterChooseWord();
    } else {
      _enterChooseWord();
    }
  }

  void _enterChooseWord() {
    setState(() {
      _index = 0;
      _chooseCorrect = 0;
      _stage = _Stage.chooseWord;
    });
  }

  // ============================================================
  //  阶段2：四选一
  // ============================================================

  List<WordOption> get _currentOptions =>
      _optionsCache[_word['id'] as int] ??
      [WordOption(word: _currentWord, definition: _currentDef)];

  void _chooseAnswered(bool correct) {
    _chooseResults[_word['id'] as int] = correct;
    if (correct) {
      setState(() => _chooseCorrect++);
    }
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
    _dictResults[_word['id'] as int] = correct;
    if (correct) {
      setState(() => _dictationCorrect++);
    }
  }

  void _advanceFromDictation() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      _commitAllReviews();
      setState(() => _stage = _Stage.done);
    }
  }

  /// 三环节全部结束后，按"各环节正确率"一次性写入 FSRS：
  /// 全部正确 → easy（最高）；2/3 → good；1/3 → hard；全错 → again（最低）。
  /// 跳过的环节不计入分母。
  void _commitAllReviews() {
    try {
      final repo = ref.read(reviewRepositoryProvider);
      for (final w in _queue) {
        repo.submitReview(w['id'] as int, _ratingFor(w['id'] as int));
      }
      ref.read(wordListVersionProvider.notifier).state++;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存复习结果失败: $e')),
        );
      }
    }
  }

  ReviewRating _ratingFor(int wordId) {
    final results = [
      _enToZhResults[wordId],
      _chooseResults[wordId],
      _dictResults[wordId],
    ].where((r) => r != null).toList();
    if (results.isEmpty) return ReviewRating.good; // 全部跳过 → 中性
    final correct = results.where((r) => r!).length;
    final ratio = correct / results.length;
    if (ratio >= 1.0) return ReviewRating.easy;
    if (ratio >= 2.0 / 3.0) return ReviewRating.good;
    if (ratio >= 1.0 / 3.0) return ReviewRating.hard;
    return ReviewRating.again;
  }

  // ============================================================
  //  构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('今日复习'),
          backgroundColor: Colors.transparent,
        ),
        body: const Stack(
          fit: StackFit.expand,
          children: [
            LoadingIndicator(message: '加载复习队列...'),
          ],
        ),
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
    final audioEnabled = ref.watch(wordAudioEnabledProvider);

    final Widget card;
    final String title;
    switch (_stage) {
      case _Stage.enToZh:
        title = '英译汉 ${_index + 1} / $total';
        card = EnToZhChoiceCard(
          key: ValueKey('en2zh-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          options: _enToZhOptionsCache[_word['id'] as int] ?? const [],
          onAnswered: _enToZhAnswered,
          onNext: _advanceFromEnToZh,
          onSkip: _advanceFromEnToZh,
          isLast: _index == total - 1,
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
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
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
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
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
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
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: card,
              ),
            ),
          ),
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
              _resultRow(theme, '英译汉', '$_enToZhCorrect / $_enToZhAnsweredCount',
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
