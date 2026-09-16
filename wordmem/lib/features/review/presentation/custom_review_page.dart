import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../domain/models/word_option.dart';
import '../../../core/theme/colors.dart';
import 'mastered_quiz_page.dart';
import 'widgets/quiz_cards.dart';

/// 自选复习页面
///
/// 按"添加日期"筛选词汇，采用与今日复习一致的三段式测验：
/// 英译汉翻卡 → 四选一 → 默写。纯练习，不更新 FSRS 排程。
///
/// 设计约定（2026-08-30 液体玻璃）：三个 phase 均带 aurora 背景 + 玻璃卡。
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

  // —— 测验（v2.1.5：全部待复习词按 50 词一组分测 + 临时存档） ——
  // 当前组队列
  List<Map<String, dynamic>> _queue = [];
  // 分组前的完整队列
  List<Map<String, dynamic>> _allQueue = [];
  int _groupIndex = 0;
  static const int _groupSize = 50;
  static const String _tempSaveKey = 'custom_review_temp_save_v1';
  int _index = 0;
  _QuizStage _stage = _QuizStage.enToZh;
  // v2.1.5：错题加练模式——纯练习，不写临时存档
  bool _isRetryMode = false;

  @override
  void initState() {
    super.initState();
    // v2.1.5：进入页面即检测临时存档，有则询问是否继续上次进度
    _maybeOfferResume();
  }

  int get _groupCount => (_allQueue.length / _groupSize).ceil();

  // —— 统计（v2.1.5：改为按词记录 + 派生，支持左滑返回重答） ——
  final Map<int, bool> _enToZhResults = {};
  final Map<int, bool> _chooseResults = {};
  final Map<int, bool> _dictResults = {};

  int get _enToZhCorrect => _enToZhResults.values.where((v) => v).length;
  int get _enToZhAnsweredCount => _enToZhResults.length;
  int get _chooseCorrect => _chooseResults.values.where((v) => v).length;
  int get _dictationCorrect => _dictResults.values.where((v) => v).length;

  final Map<int, List<WordOption>> _optionsCache = {};
  // 英译汉选择题选项缓存（wordId -> 中文释义选项）
  final Map<int, List<WordOption>> _enToZhOptionsCache = {};
  final Map<int, bool> _enToZhAvailable = {};

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
    setState(() {
      _allQueue = rows;
      _rangeLabel = _label;
      _phase = _Phase.quiz;
      _isRetryMode = false;
      _enToZhResults.clear();
      _chooseResults.clear();
      _dictResults.clear();
    });
    _startGroup(0);
  }

  /// 加载指定组（组内进度重置到英译汉第一题）。
  ///
  /// 三环节作答记录按 wordId 累积、不随切组清空——同一词在本轮只出现一次，
  /// 因此结果页呈现的是整轮（全部组）统计。
  void _startGroup(int gi) {
    final start = gi * _groupSize;
    var end = (gi + 1) * _groupSize;
    if (end > _allQueue.length) end = _allQueue.length;
    setState(() {
      _groupIndex = gi;
      _queue = _allQueue.sublist(start, end);
      _index = 0;
      _stage = _QuizStage.enToZh;
    });
    _prepareStages(_queue);
    _skipUnavailableEnToZh();
  }

  /// 熟练词抽检（v2.1.6）：独立入口——从已掌握词中随机抽 5 个做默写。
  /// 与自选复习的纯练习不同，抽检结果会回写卡片状态（答对 due+15 天、
  /// 答错保留 mastered 并 due+3 天）。
  Future<void> _startMasteredQuiz() async {
    final repo = ref.read(reviewRepositoryProvider);
    final List<Map<String, dynamic>> words;
    try {
      words = repo.pickMasteredQuizWords();
    } catch (err) {
      _toast('读取已掌握词失败: $err');
      return;
    }
    if (words.isEmpty) {
      _toast('还没有已掌握的词，先完成几轮复习吧');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => MasteredQuizPage(words: words)),
    );
  }

  /// 预生成选项：选单词四选一（看中文选英文）+ 英译汉选择题（看英文选中文）
  /// 释义来源：自定义释义优先，缺失回退词典 translation；两者皆空则跳过英译汉环节。
  void _prepareStages(List<Map<String, dynamic>> rows) {
    _optionsCache.clear();
    _enToZhOptionsCache.clear();
    _enToZhAvailable.clear();
    final repo = ref.read(wordRepositoryProvider);

    // v2.1.5：统一走 repo.buildReviewStageOptions，干扰项在复习词组/
    // 个人词库/词典中随机抽选，修复旧逻辑可观察规律 bug
    final stages = repo.buildReviewStageOptions(rows);
    stages.forEach((id, s) {
      _optionsCache[id] = s.wordOptions;
      _enToZhOptionsCache[id] = s.enToZhAvailable ? s.enToZhOptions : const [];
      _enToZhAvailable[id] = s.enToZhAvailable;
    });
  }

  void _skipUnavailableEnToZh() {
    while (_index < _queue.length &&
        !(_enToZhAvailable[_word['id'] as int] ?? false)) {
      _index++;
    }
    if (_index >= _queue.length && _phase == _Phase.quiz) {
      setState(() => _stage = _QuizStage.chooseWord);
    }
  }

  Map<String, dynamic> get _word => _queue[_index];
  String get _currentWord => _word['word'] as String;
  String get _currentDef => ((_word['custom_def'] as String?) ?? '').trim();
  List<WordOption> get _currentOptions =>
      _optionsCache[_word['id'] as int] ??
      [WordOption(word: _currentWord, definition: _currentDef)];

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 英译汉（选择题，自选复习不更新 FSRS，仅统计记住与否）
  // 注意：此处仅记录结果，不前进——前进由卡片「下一题」/「跳过」触发，
  // 保证作答后答案反馈能正常展示（若在此前进，卡片因 ValueKey 变化
  // 被重建，内部反馈态丢失，表现为跳过答案直接进入下一题）。
  void _enToZhAnswered(bool correct) {
    setState(() => _enToZhResults[_word['id'] as int] = correct);
    _autoSave();
  }

  void _advanceEnToZh() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
      _skipUnavailableEnToZh();
      if (_index >= _queue.length && _stage == _QuizStage.enToZh) {
        setState(() => _stage = _QuizStage.chooseWord);
      }
    } else {
      setState(() {
        _index = 0;
        _stage = _QuizStage.chooseWord;
      });
    }
    _autoSave();
  }

  void _chooseAnswered(bool correct) {
    setState(() => _chooseResults[_word['id'] as int] = correct);
    _autoSave();
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
    _autoSave();
  }

  void _dictationAnswered(bool correct) {
    setState(() => _dictResults[_word['id'] as int] = correct);
    _autoSave();
  }

  void _advanceDictation() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
      _autoSave();
    } else {
      _clearTempSave(); // 本组已完成，清临时存档
      if (_groupIndex < _groupCount - 1) {
        _startGroup(_groupIndex + 1);
      } else {
        setState(() => _phase = _Phase.result);
      }
    }
  }

  // ============================================================
  //  临时存档（v2.1.5）：题目导航行「存档」按钮，恢复完整测验进度
  // ============================================================

  /// 进入页面时检测存档；有则询问继续 / 重新开始
  Future<void> _maybeOfferResume() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(_tempSaveKey);
      if (raw == null || raw.isEmpty) return;
      final saved = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (!mounted) return;
      await _offerResume(saved);
    } catch (_) {
      // 存档损坏时静默忽略
    }
  }

  Future<void> _saveTempProgress() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(
      _tempSaveKey,
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'allQueueIds': _allQueue.map((w) => w['id'] as int).toList(),
        'groupIndex': _groupIndex,
        'index': _index,
        'stage': _stage.name,
        'rangeLabel': _rangeLabel,
        'enToZh': _enToZhResults.map((k, v) => MapEntry('$k', v)),
        'choose': _chooseResults.map((k, v) => MapEntry('$k', v)),
        'dict': _dictResults.map((k, v) => MapEntry('$k', v)),
      }),
    );
  }

  Future<void> _clearTempSave() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.remove(_tempSaveKey);
    } catch (_) {
      // 忽略（存档不存在或 prefs 未就绪）
    }
  }

  /// v2.1.5：每完成一步（作答 / 前进 / 后退 / 切换环节 / 切换组）自动落盘，
  /// 无需手动点「存档」，中途退出即为「已保存」状态。
  ///
  /// 无任何作答时不写——避免"打开看一眼就退出"也留下存档，下次误弹恢复提示；
  /// 错题加练为纯练习，同样不写。
  void _autoSave() {
    if (_isRetryMode) return;
    if (_enToZhResults.isEmpty &&
        _chooseResults.isEmpty &&
        _dictResults.isEmpty) {
      return;
    }
    _saveTempProgress().catchError((_) {});
  }

  /// 检测到存档 → 询问继续或重新开始
  Future<void> _offerResume(Map<String, dynamic> saved) async {
    final ids = (saved['allQueueIds'] as List? ?? const [])
        .map((e) => e as int)
        .toList();
    final groupCount = ids.isEmpty ? 1 : (ids.length / _groupSize).ceil();
    final gi = (((saved['groupIndex'] as int?) ?? 0) + 1).clamp(1, groupCount);
    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('继续上次自选复习进度？'),
        content: Text('检测到未完成的临时存档（第 $gi/$groupCount 组），'
            '可从中断处继续，或放弃存档重新选择范围。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('重新开始'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续进度'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      await _restoreTemp(saved);
    } else {
      await _clearTempSave();
    }
  }

  /// 从存档原样恢复：按 id 重建完整队列 → 定位到组/题/环节 → 回填三环节作答
  Future<void> _restoreTemp(Map<String, dynamic> saved) async {
    try {
      final ids = (saved['allQueueIds'] as List? ?? const [])
          .map((e) => e as int)
          .toList();
      final dao = ref.read(wordDaoProvider);
      final rows = <Map<String, dynamic>>[];
      for (final id in ids) {
        final w = dao.getById(id);
        if (w != null) rows.add(w);
      }
      if (rows.isEmpty) {
        await _clearTempSave();
        return;
      }
      final gc = (rows.length / _groupSize).ceil();
      final gi = ((saved['groupIndex'] as int?) ?? 0).clamp(0, gc - 1);
      var end = (gi + 1) * _groupSize;
      if (end > rows.length) end = rows.length;
      final queue = rows.sublist(gi * _groupSize, end);
      setState(() {
        _allQueue = rows;
        _rangeLabel = (saved['rangeLabel'] as String?) ?? '';
        _groupIndex = gi;
        _queue = queue;
        _index = ((saved['index'] as int?) ?? 0)
            .clamp(0, queue.isEmpty ? 0 : queue.length - 1);
        _stage = _QuizStage.values.firstWhere(
          (s) => s.name == (saved['stage'] as String? ?? 'enToZh'),
          orElse: () => _QuizStage.enToZh,
        );
        _enToZhResults
          ..clear()
          ..addAll(_decodeBoolMap(saved['enToZh']));
        _chooseResults
          ..clear()
          ..addAll(_decodeBoolMap(saved['choose']));
        _dictResults
          ..clear()
          ..addAll(_decodeBoolMap(saved['dict']));
        _phase = _Phase.quiz;
      });
      _prepareStages(_queue);
      if (_stage == _QuizStage.enToZh) _skipUnavailableEnToZh();
    } catch (_) {
      await _clearTempSave();
    }
  }

  static Map<int, bool> _decodeBoolMap(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(int.tryParse('$k') ?? -1, v == true))
      ..remove(-1);
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('自选复习'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassContainer(
                blur: 0,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '自选复习为纯练习模式，不影响学习算法排程。包含英译汉、选单词、默写三个环节。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('选择词汇范围',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
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
                label: Text(
                    _useCustom && _customRange != null ? _label : '自定义日期范围'),
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
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              GlassButton(
                onPressed: _startQuiz,
                icon: Icons.play_arrow,
                label: '开始自选复习',
                tinted: true,
              ),
              const SizedBox(height: 16),
              // v2.1.6：熟练词抽检——独立于自选复习的纯练习流程，会回写卡片状态
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _startMasteredQuiz,
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('熟练词抽检'),
                ),
              ),
            ],
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

  /// 「上一题」返回当前环节的上一题（v2.1.5，防误点跳过）。
  /// 返回时清除该词在当前环节的作答记录，重答后按新结果计数。
  /// 英译汉环节会跳过无中文释义的词；已在环节第一题时不可回退。
  bool _canGoBackInStage() {
    switch (_stage) {
      case _QuizStage.enToZh:
        for (var i = _index - 1; i >= 0; i--) {
          if (_enToZhAvailable[_queue[i]['id'] as int] ?? false) return true;
        }
        return false;
      case _QuizStage.chooseWord:
      case _QuizStage.dictation:
        return _index > 0;
    }
  }

  void _goBackInStage() {
    switch (_stage) {
      case _QuizStage.enToZh:
        var i = _index - 1;
        while (i >= 0 && !(_enToZhAvailable[_queue[i]['id'] as int] ?? false)) {
          i--;
        }
        if (i < 0) return;
        setState(() {
          _index = i;
          _enToZhResults.remove(_queue[i]['id'] as int);
        });
        _autoSave();
      case _QuizStage.chooseWord:
        if (_index == 0) return;
        setState(() {
          _index--;
          _chooseResults.remove(_queue[_index]['id'] as int);
        });
        _autoSave();
      case _QuizStage.dictation:
        if (_index == 0) return;
        setState(() {
          _index--;
          _dictResults.remove(_queue[_index]['id'] as int);
        });
        _autoSave();
    }
  }

  /// 右上角「下一题」：与「跳过」同义（未作答即跳过，不计对错）
  void _advanceCurrent() {
    switch (_stage) {
      case _QuizStage.enToZh:
        _advanceEnToZh();
      case _QuizStage.chooseWord:
        _advanceChoose();
      case _QuizStage.dictation:
        _advanceDictation();
    }
  }

  /// 题目导航行（v2.1.5）：左「上一题」/ 中「自动保存」标记 / 右「下一题」。
  /// 进度在每步作答后自动落盘，不再需要手动点「存档」。
  Widget _quizNavRow() {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _canGoBackInStage() ? _goBackInStage : null,
          icon: const Icon(Icons.arrow_back_ios_new, size: 15),
          label: const Text('上一题'),
        ),
        const Spacer(),
        Tooltip(
          message: '进度已自动保存，退出后可继续',
          child: Icon(
            Icons.cloud_done_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _advanceCurrent,
          icon: const Icon(Icons.arrow_forward_ios, size: 15),
          label: const Text('下一题'),
        ),
      ],
    );
  }

  Widget _buildQuiz() {
    final total = _queue.length;
    final progress = _index / total;
    final audioEnabled = ref.watch(wordAudioEnabledProvider);

    final Widget card;
    String title;
    switch (_stage) {
      case _QuizStage.enToZh:
        title = '英译汉 ${_index + 1} / $total';
        card = EnToZhChoiceCard(
          key: ValueKey('en2zh-${_word['id']}'),
          word: _currentWord,
          definition: _currentDef,
          options: _enToZhOptionsCache[_word['id'] as int] ?? const [],
          onAnswered: _enToZhAnswered,
          onNext: _advanceEnToZh,
          onSkip: _advanceEnToZh,
          isLast: _index == total - 1,
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
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
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
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
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
        );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(title),
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
              // v2.1.5：整页可滚动（LayoutBuilder + minHeight 撑满）——
              // 内容超出屏幕时可上下滑动，根治 RenderFlex 溢出；内容少时仍居中。
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          // v2.1.5：题目左上角「上一题」/ 右上角「下一题」导航
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _quizNavRow(),
                              card,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  //  错题加练（v2.1.5）
  // ============================================================

  /// 错题集：三环节中任一答错即算错题（跳过的环节不计），保持队列原顺序
  List<int> get _wrongIds {
    final ids = <int>{};
    _enToZhResults.forEach((id, ok) {
      if (!ok) ids.add(id);
    });
    _chooseResults.forEach((id, ok) {
      if (!ok) ids.add(id);
    });
    _dictResults.forEach((id, ok) {
      if (!ok) ids.add(id);
    });
    return [
      for (final w in _allQueue)
        if (ids.contains(w['id'] as int)) w['id'] as int,
    ];
  }

  /// 重做全部错题：以错题重建队列从头再来一轮（自选复习本就不写数据）
  void _retryWrong() {
    final wrong = _wrongIds;
    if (wrong.isEmpty) return;
    final byId = {for (final w in _allQueue) w['id'] as int: w};
    final rows = [
      for (final id in wrong)
        if (byId[id] != null) byId[id]!,
    ];
    if (rows.isEmpty) return;
    setState(() {
      _allQueue = rows;
      _isRetryMode = true;
      _phase = _Phase.quiz;
      _enToZhResults.clear();
      _chooseResults.clear();
      _dictResults.clear();
    });
    _clearTempSave();
    _startGroup(0);
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    // v2.1.5：分组后结果页统计整轮（全部组）而非最后一组
    final total = _allQueue.length;
    final wrongCount = _wrongIds.length;
    final percent = total > 0
        ? ((_enToZhCorrect + _chooseCorrect + _dictationCorrect) * 100 ~/
            (total * 3))
        : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_isRetryMode ? '错题加练完成' : '复习完成'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      // v2.1.5：结果页同样可滚动，避免小屏溢出
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (ctx, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          percent >= 80
                              ? Icons.emoji_events
                              : Icons.check_circle_outline,
                          size: 72,
                          color: percent >= 80
                              ? AppColors.ratingEasy
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(_isRetryMode ? '本轮错题加练完成' : '本轮自选复习完成',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                        if (wrongCount > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '本轮有 $wrongCount 个词答错过',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '综合正确率 $percent%',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: percent >= 80
                                ? AppColors.ratingGood
                                : AppColors.ratingAgain,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '范围：$_rangeLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _resultRow(theme, '英译汉',
                            '$_enToZhCorrect / $_enToZhAnsweredCount',
                            Icons.translate, AppColors.primary),
                        const SizedBox(height: 8),
                        _resultRow(theme, '选单词', '$_chooseCorrect / $total',
                            Icons.checklist, AppColors.ratingEasy),
                        const SizedBox(height: 8),
                        _resultRow(theme, '默写', '$_dictationCorrect / $total',
                            Icons.edit_note, AppColors.ratingHard),
                        const SizedBox(height: 32),
                        if (wrongCount > 0) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _retryWrong,
                              icon: const Icon(Icons.replay, size: 18),
                              label: Text('重做错题（$wrongCount）',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        GlassButton(
                          onPressed: _startQuiz,
                          icon: Icons.refresh,
                          label: '再来一轮',
                          tinted: true,
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(
      ThemeData theme, String label, String value, IconData icon, Color color) {
    return GlassContainer(
      blur: 0,
      elevated: false,
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
