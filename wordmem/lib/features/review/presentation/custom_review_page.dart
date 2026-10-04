import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/quiz_countdown.dart';
import '../../../domain/models/word_option.dart';
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

  // ═══════════ v2.1.8：与今日复习同步的流程（乱序 / 本组统计 / 每组重测） ═══════════

  /// 临时存档格式版本（v2 = 带 stageSeq）
  static const int _saveVersion = 2;

  /// 出题顺序：`_queue` 的下标排列。三环节各自洗牌，避免位置记忆。
  List<int> _stageSeq = [];

  /// 本组统计快照（含重测追加行）
  _GroupOutcome? _groupOutcome;
  /// 重测期间暂存的本组统计
  _GroupOutcome? _retryOutcome;
  /// 本组是否已走完 `_endOfGroup()` 编排
  bool _groupFinalized = false;

  // 重测期间的正式结果快照（结束后还原，保证统计页是"练习前"口径）
  Map<int, bool>? _snapEn;
  Map<int, bool>? _snapChoose;
  Map<int, bool>? _snapDict;
  List<Map<String, dynamic>>? _snapAllQueue;
  List<Map<String, dynamic>>? _snapQueue;

  /// 三环节各词是否超时（v2.1.8 评分用；自选复习为纯练习，分数只在统计页展示）
  final Map<int, bool> _enToZhTimeouts = {};
  final Map<int, bool> _chooseTimeouts = {};
  final Map<int, bool> _dictTimeouts = {};

  /// 作答倒计时状态句柄
  final _cdKey = GlobalKey<QuizCountdownState>();

  @override
  void initState() {
    super.initState();
    // v2.1.5：进入页面即检测临时存档，有则询问是否继续上次进度
    _maybeOfferResume();
  }

  int get _groupCount => (_allQueue.length / _groupSize).ceil();

  /// **唯一口径（v2.1.8）**：本组词的 id 集合。
  /// 统计 / 错题集合全部基于它，**禁止按 `_queue` 下标切片**（乱序后下标与词不对应）。
  Set<int> get _groupIds => {for (final w in _queue) w['id'] as int};

  /// 出题顺序取值（空 = 恒等序，兼容旧存档）
  int _seqAt(int i) {
    if (_stageSeq.isEmpty) return i;
    if (i < 0 || i >= _stageSeq.length) return i;
    return _stageSeq[i];
  }

  /// 生成一份洗牌后的出题顺序
  static List<int> _buildSeq(int n) {
    final seq = List<int>.generate(n, (i) => i);
    seq.shuffle();
    return seq;
  }

  // —— 统计（v2.1.5：改为按词记录 + 派生，支持左滑返回重答） ——
  final Map<int, bool> _enToZhResults = {};
  final Map<int, bool> _chooseResults = {};
  final Map<int, bool> _dictResults = {};

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
      // v2.1.8：分组顺序不变，只重洗组内三环节的出题次序
      _stageSeq = _buildSeq(_queue.length);
      _groupFinalized = false;
      _groupOutcome = null;
    });
    _prepareStages(_queue);
    _skipUnavailableEnToZh();
  }

  /// 熟练词抽检（v2.1.6）：独立入口——从已掌握词中随机抽取做默写
  /// （数量由学习节奏配置决定，默认 10 个）。
  /// 与自选复习的纯练习不同，抽检结果会回写卡片状态（答对 due+10 天、
  /// 答错保留 mastered 并 due+2 天）。
  ///
  /// v2.2.0 需求2 阶段①：与复习页编排对齐——答错的词**当场询问重测一次**，
  /// 结算走同一套 [ReviewRepository.settleMasteredQuizRetries]：
  /// 重测通过不洗白（推后 2 天复检窗口），仍错打回 T5 重新走周期。
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
    final wrongIds = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => MasteredQuizPage(words: words)),
    );
    if (!mounted || wrongIds == null || wrongIds.isEmpty) return;

    final wrongRows = words
        .where((w) => wrongIds.contains(w['id'] as int))
        .toList();
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('当场重测错词？'),
        content: Text(
          '抽检答错 ${wrongRows.length} 个词。重测通过只推后复检窗口（不洗白）；'
          '重测仍答错会退回复习队列（从 T5 重新走周期）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不重测'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始重测'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (retry != true) {
      // 未重测：与复习页「未重测结算」同语义——推入 2 天复检窗口
      repo.settleMasteredQuizRetries(wrongIds, failedIds: const <int>{});
      return;
    }
    // 重测：逐题仍会 submitMasteredQuiz 落库；结算按返回的错词集合统一覆盖
    //（重测答对 → hold 不洗白；仍错 → 打回 T5）。中途退出只带回已答错的子集，
    // 未答到的词推入复检窗口，不误伤。
    final stillWrong = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => MasteredQuizPage(words: wrongRows)),
    );
    if (!mounted) return;
    repo.settleMasteredQuizRetries(
      wrongIds,
      failedIds: (stillWrong ?? const <int>[]).toSet(),
    );
    _toast('重测结算完成');
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

  /// 跳过无中文释义的词（英译汉环节无法出题）。
  /// v2.1.8：按 `_stageSeq` 取词——第 k 题是 `_queue[_seqAt(k)]`。
  void _skipUnavailableEnToZh() {
    while (_index < _stageSeq.length &&
        !(_enToZhAvailable[_queue[_seqAt(_index)]['id'] as int] ?? false)) {
      _index++;
    }
    if (_index >= _stageSeq.length && _phase == _Phase.quiz) {
      _enterChooseWord();
    }
  }

  /// 进入「选单词」环节：重洗一份出题顺序（v2.1.8）
  void _enterChooseWord() {
    setState(() {
      _index = 0;
      _stage = _QuizStage.chooseWord;
      _stageSeq = _buildSeq(_queue.length);
    });
    _autoSave();
  }

  /// 当前词。v2.1.8：经 `_stageSeq` 映射，`_index` 是"第几题"而非 `_queue` 下标。
  Map<String, dynamic> get _word => _queue[_seqAt(_index)];
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
    final id = _word['id'] as int;
    setState(() {
      _enToZhResults[id] = correct;
      _enToZhTimeouts[id] = _cdKey.currentState?.isOvertime ?? false;
    });
    _autoSave();
  }

  void _advanceEnToZh() {
    if (_index < _stageSeq.length - 1) {
      setState(() => _index++);
      _skipUnavailableEnToZh();
      if (_index >= _stageSeq.length) _enterChooseWord();
    } else {
      _enterChooseWord();
    }
    _autoSave();
  }

  void _chooseAnswered(bool correct) {
    final id = _word['id'] as int;
    setState(() {
      _chooseResults[id] = correct;
      _chooseTimeouts[id] = _cdKey.currentState?.isOvertime ?? false;
    });
    _autoSave();
  }

  void _advanceChoose() {
    if (_index < _stageSeq.length - 1) {
      setState(() => _index++);
    } else {
      // 进入「默写」环节：再洗一次出题顺序（v2.1.8）
      setState(() {
        _index = 0;
        _stage = _QuizStage.dictation;
        _stageSeq = _buildSeq(_queue.length);
      });
    }
    _autoSave();
  }

  void _dictationAnswered(bool correct) {
    final id = _word['id'] as int;
    setState(() {
      _dictResults[id] = correct;
      _dictTimeouts[id] = _cdKey.currentState?.isOvertime ?? false;
    });
    _autoSave();
  }

  Future<void> _advanceDictation() async {
    if (_index < _stageSeq.length - 1) {
      setState(() => _index++);
      _autoSave();
      return;
    }
    if (_isRetryMode) {
      // 错题检验（纯练习）走完 → 回到本组统计页
      _finishRetry();
      return;
    }
    _clearTempSave(); // 本组已完成，清临时存档
    await _endOfGroup();
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
        'saveVersion': _saveVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'allQueueIds': _allQueue.map((w) => w['id'] as int).toList(),
        'groupIndex': _groupIndex,
        'index': _index,
        'stage': _stage.name,
        'rangeLabel': _rangeLabel,
        // v2.1.8：出题顺序与 index 必须成对还原
        'stageSeq': _stageSeq,
        'groupFinalized': _groupFinalized,
        'enToZh': _enToZhResults.map((k, v) => MapEntry('$k', v)),
        'choose': _chooseResults.map((k, v) => MapEntry('$k', v)),
        'dict': _dictResults.map((k, v) => MapEntry('$k', v)),
        'enToZhOt': _enToZhTimeouts.map((k, v) => MapEntry('$k', v)),
        'chooseOt': _chooseTimeouts.map((k, v) => MapEntry('$k', v)),
        'dictOt': _dictTimeouts.map((k, v) => MapEntry('$k', v)),
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
        // v2.1.8：先还原 stageSeq、再定 index（`_index` 是 `_stageSeq` 的下标）。
        // 旧档无 stageSeq → 恒等序 + 保留 index（旧版没洗牌，语义等价，不丢进度）。
        _stageSeq = _decodeSeq(saved['stageSeq'], queue.length);
        _groupFinalized = saved['groupFinalized'] == true;
        _enToZhResults
          ..clear()
          ..addAll(_decodeBoolMap(saved['enToZh']));
        _chooseResults
          ..clear()
          ..addAll(_decodeBoolMap(saved['choose']));
        _dictResults
          ..clear()
          ..addAll(_decodeBoolMap(saved['dict']));
        _enToZhTimeouts
          ..clear()
          ..addAll(_decodeBoolMap(saved['enToZhOt']));
        _chooseTimeouts
          ..clear()
          ..addAll(_decodeBoolMap(saved['chooseOt']));
        _dictTimeouts
          ..clear()
          ..addAll(_decodeBoolMap(saved['dictOt']));
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

  /// 还原出题顺序：缺失 / 长度不符 / 不是排列 → 恒等序（旧档兼容：不崩、不洗牌）
  static List<int> _decodeSeq(dynamic raw, int n) {
    final identity = List<int>.generate(n, (i) => i);
    if (raw is! List || raw.length != n) return identity;
    final out = <int>[];
    final seen = <int>{};
    for (final e in raw) {
      final v = e is int ? e : int.tryParse('$e');
      if (v == null || v < 0 || v >= n || !seen.add(v)) return identity;
      out.add(v);
    }
    return out;
  }

  // ============================================================
  //  构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.setup => _buildSetup(),
      // v2.1.8：本组统计页（每组末都出现）取代原来的整轮结果页
      _Phase.quiz => _stage == _QuizStage.groupStats
          ? _buildGroupStats()
          : _buildQuiz(),
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
        // v2.1.8：下标须经 _stageSeq 映射（第 k 题是 _queue[_seqAt(k)]）
        for (var i = _index - 1; i >= 0; i--) {
          if (_enToZhAvailable[_queue[_seqAt(i)]['id'] as int] ?? false) {
            return true;
          }
        }
        return false;
      case _QuizStage.chooseWord:
      case _QuizStage.dictation:
        return _index > 0;
      case _QuizStage.groupStats:
        return false;
    }
  }

  void _goBackInStage() {
    switch (_stage) {
      case _QuizStage.enToZh:
        var i = _index - 1;
        while (i >= 0 &&
            !(_enToZhAvailable[_queue[_seqAt(i)]['id'] as int] ?? false)) {
          i--;
        }
        if (i < 0) return;
        setState(() {
          _index = i;
          final id = _queue[_seqAt(i)]['id'] as int;
          _enToZhResults.remove(id);
          _enToZhTimeouts.remove(id); // 重答时重新计时
        });
        _autoSave();
      case _QuizStage.chooseWord:
        if (_index == 0) return;
        setState(() {
          _index--;
          final id = _queue[_seqAt(_index)]['id'] as int;
          _chooseResults.remove(id);
          _chooseTimeouts.remove(id);
        });
        _autoSave();
      case _QuizStage.dictation:
        if (_index == 0) return;
        setState(() {
          _index--;
          final id = _queue[_seqAt(_index)]['id'] as int;
          _dictResults.remove(id);
          _dictTimeouts.remove(id);
        });
        _autoSave();
      case _QuizStage.groupStats:
        break;
    }
  }

  /// 右上角「下一题」：与「跳过」同义（未作答即跳过，按答错计分）
  void _advanceCurrent() {
    _recordSkipTimeout();
    switch (_stage) {
      case _QuizStage.enToZh:
        _advanceEnToZh();
      case _QuizStage.chooseWord:
        _advanceChoose();
      case _QuizStage.dictation:
        _advanceDictation();
      case _QuizStage.groupStats:
        break;
    }
  }

  /// 未作答就前进时补记超时（跳过路径不经过卡片回调，漏记会少扣那 1 分）
  void _recordSkipTimeout() {
    if (_stage == _QuizStage.groupStats) return;
    if (_currentAnswered) return;
    final id = _word['id'] as int;
    final overtime = _cdKey.currentState?.isOvertime ?? false;
    switch (_stage) {
      case _QuizStage.enToZh:
        _enToZhTimeouts[id] = overtime;
      case _QuizStage.chooseWord:
        _chooseTimeouts[id] = overtime;
      case _QuizStage.dictation:
        _dictTimeouts[id] = overtime;
      case _QuizStage.groupStats:
        break;
    }
  }

  /// 当前题是否已作答（v2.1.8：卡片内「跳过」按钮已删，未作答时强调「下一题」）
  bool get _currentAnswered {
    final id = _word['id'] as int;
    switch (_stage) {
      case _QuizStage.enToZh:
        return _enToZhResults.containsKey(id);
      case _QuizStage.chooseWord:
        return _chooseResults.containsKey(id);
      case _QuizStage.dictation:
        return _dictResults.containsKey(id);
      case _QuizStage.groupStats:
        // 统计页没有"当前题"，此处只为穷尽枚举；调用点也不会在统计页触发
        return true;
    }
  }

  /// 题目导航行（v2.1.5）：左「上一题」/ 中「自动保存」标记 / 右「下一题」。
  /// 进度在每步作答后自动落盘，不再需要手动点「存档」。
  /// v2.1.8：未作答时把「下一题」染成主色——它是当前唯一的"不会就跳过"入口。
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
          style: _currentAnswered
              ? null
              : TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
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
          isLast: _index == total - 1,
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
        );
      case _QuizStage.groupStats:
        title = '';
        card = const SizedBox.shrink();
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
                              // v2.1.8：题干上方的作答倒计时（默写 8s、其余 5s）
                              QuizCountdown(
                                key: _cdKey,
                                limit: _stage == _QuizStage.dictation
                                    ? AppConstants.quizTimeLimitDictation
                                    : AppConstants.quizTimeLimitChoice,
                                questionKey:
                                    '${_stage.name}-$_index-${_word['id']}',
                                frozen: _currentAnswered,
                              ),
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

  /// 错题集：三环节中任一答错即算错题（跳过的环节不计），保持**本组队列**原顺序。
  ///
  /// v2.1.8：① 按 `_groupIds` 切片（只算本组的词）；② 遍历 `_queue` 而不是 `_allQueue`
  /// （后者是整轮全量，会带出别的组的错词）。
  List<int> get _wrongIds {
    final groupIds = _groupIds;
    final ids = <int>{};
    for (final m in [_enToZhResults, _chooseResults, _dictResults]) {
      m.forEach((id, ok) {
        if (!ok && groupIds.contains(id)) ids.add(id);
      });
    }
    return [
      for (final w in _queue)
        if (ids.contains(w['id'] as int)) w['id'] as int,
    ];
  }

  /// 本轮该词的得分（0–6）。自选复习是**纯练习**，分数只在统计页展示、不写库。
  int _scoreFor(int wordId) {
    var score = AppConstants.quizMaxScore;
    void judge(bool? correct, bool? overtime) {
      if (correct != true) score -= 1; // 答错 / 未作答（跳过）都扣
      if (overtime == true) score -= 1;
    }

    judge(_enToZhResults[wordId], _enToZhTimeouts[wordId]);
    judge(_chooseResults[wordId], _chooseTimeouts[wordId]);
    judge(_dictResults[wordId], _dictTimeouts[wordId]);
    return score.clamp(0, AppConstants.quizMaxScore);
  }

  // ============================================================
  //  组结束编排（v2.1.8，与今日复习同一套）
  // ============================================================

  /// 本组结束的**唯一**编排入口：统计 →（有错题才）重测询问 → 本组统计页。
  ///
  /// 自选复习是**纯练习**（不写 FSRS、不写复习历史），因此这里**不做**
  /// 「抽检询问」与「上传进度」——抽检会回写排期且已有独立入口（设置页那个按钮），
  /// 上传在纯练习之后也没有任何数据变化可传。
  Future<void> _endOfGroup() async {
    if (_groupFinalized) return;
    final outcome = _collectGroupOutcome();

    if (outcome.wrongCount > 0) {
      final started = await _maybeOfferGroupRetry(outcome);
      if (!mounted) return;
      if (started) return; // 重测结束后由 _finishRetry() 回到统计页
    }
    _showGroupStats(outcome);
  }

  /// 呈现本组统计页
  void _showGroupStats(_GroupOutcome outcome) {
    setState(() {
      _groupOutcome = outcome;
      _groupFinalized = true;
      _stage = _QuizStage.groupStats;
    });
    _autoSave(); // 断点：在统计页退出后重进能回到统计页
  }

  /// 本组口径统计快照（全部按 wordId + `_groupIds` 切片，与出题顺序无关）
  _GroupOutcome _collectGroupOutcome() {
    final ids = _groupIds;
    int correctIn(Map<int, bool> m) =>
        m.entries.where((e) => ids.contains(e.key) && e.value).length;
    int answeredIn(Map<int, bool> m) => m.keys.where(ids.contains).length;
    final wrong = <int>{};
    for (final m in [_enToZhResults, _chooseResults, _dictResults]) {
      m.forEach((id, ok) {
        if (ids.contains(id) && !ok) wrong.add(id);
      });
    }
    var scoreSum = 0;
    for (final w in _queue) {
      scoreSum += _scoreFor(w['id'] as int);
    }
    return _GroupOutcome(
      groupNo: _groupIndex + 1,
      total: _queue.length,
      enToZhCorrect: correctIn(_enToZhResults),
      enToZhAnswered: answeredIn(_enToZhResults),
      chooseCorrect: correctIn(_chooseResults),
      dictCorrect: correctIn(_dictResults),
      wrongIds: [
        for (final w in _queue)
          if (wrong.contains(w['id'] as int)) w['id'] as int,
      ],
      scoreSum: scoreSum,
      scoreMax: _queue.length * AppConstants.quizMaxScore,
    );
  }

  /// 询问是否重测本组错题。返回 true = 已进入重测（调用方**必须直接返回**，
  /// 由 `_finishRetry()` 负责回到统计页，不得再走一遍编排）
  Future<bool> _maybeOfferGroupRetry(_GroupOutcome outcome) async {
    final rows = _retryRowsFor(outcome);
    if (rows.isEmpty) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重测本组错题？'),
        content: Text('本组有 ${outcome.wrongCount} 个词答错过了。'
            '自选复习本就是纯练习，重测只为加深记忆。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('不测'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('测验错题'),
          ),
        ],
      ),
    );
    if (!mounted || go != true) return false;

    // 快照本组正式结果：重测复用同一批 map，结束后还原，
    // 保证统计页数字仍是「重测前」的口径（重测只作为附加行展示）
    _snapEn = Map<int, bool>.from(_enToZhResults);
    _snapChoose = Map<int, bool>.from(_chooseResults);
    _snapDict = Map<int, bool>.from(_dictResults);
    _snapAllQueue = _allQueue;
    _snapQueue = _queue;
    _retryOutcome = outcome;

    setState(() {
      _allQueue = rows;
      // 重测**不再按 50 词切分**，整批一次走完
      _queue = rows;
      _index = 0;
      _stage = _QuizStage.enToZh;
      _stageSeq = _buildSeq(_queue.length);
      _isRetryMode = true;
      _phase = _Phase.quiz;
      _enToZhResults.clear();
      _chooseResults.clear();
      _dictResults.clear();
      _enToZhTimeouts.clear();
      _chooseTimeouts.clear();
      _dictTimeouts.clear();
    });
    _prepareStages(_queue);
    _skipUnavailableEnToZh();
    return true;
  }

  /// 重测用词：本组复习错词（保持队列原顺序）
  List<Map<String, dynamic>> _retryRowsFor(_GroupOutcome outcome) {
    final byId = <int, Map<String, dynamic>>{
      for (final w in _queue) w['id'] as int: w,
    };
    return [
      for (final id in outcome.wrongIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 重测走完：还原正式结果 → 回到本组统计页
  void _finishRetry() {
    final outcome = _retryOutcome;
    if (outcome != null) {
      // 重测成绩只作为附加行（不覆盖原统计）
      outcome.retryTotal = _queue.length;
      outcome.retryCorrect = _queue.length - _wrongIds.length;
    }
    _retryOutcome = null;

    _enToZhResults
      ..clear()
      ..addAll(_snapEn ?? const {});
    _chooseResults
      ..clear()
      ..addAll(_snapChoose ?? const {});
    _dictResults
      ..clear()
      ..addAll(_snapDict ?? const {});
    _allQueue = _snapAllQueue ?? _allQueue;
    _queue = _snapQueue ?? _queue;
    _snapEn = null;
    _snapChoose = null;
    _snapDict = null;
    _snapAllQueue = null;
    _snapQueue = null;
    _isRetryMode = false;
    _index = 0;
    _stageSeq = _buildSeq(_queue.length);

    if (outcome != null) {
      _showGroupStats(outcome);
    } else {
      setState(() => _stage = _QuizStage.groupStats);
    }
  }

  /// 下一组（本组最后一题已答完，直接开新组）
  void _goNextGroup() {
    if (_groupIndex >= _groupCount - 1) return;
    _startGroup(_groupIndex + 1);
  }

  /// 完成：清临时存档 + **回到范围选择页**（用户拍板）。
  /// 与今日复习的「回首页」不同——自选复习是从设置页进来的，回去重选一批更顺手。
  void _finishSession() {
    _clearTempSave();
    setState(() {
      _phase = _Phase.setup;
      _stage = _QuizStage.enToZh;
      _stageSeq = [];
      _groupOutcome = null;
      _groupFinalized = false;
      _isRetryMode = false;
      _enToZhResults.clear();
      _chooseResults.clear();
      _dictResults.clear();
      _enToZhTimeouts.clear();
      _chooseTimeouts.clear();
      _dictTimeouts.clear();
      _queue = [];
      _allQueue = [];
      _index = 0;
      _groupIndex = 0;
    });
  }

  /// 本组统计页（v2.1.8）：**每组结束都出现**，取代原来只在整轮末出现的结果页。
  /// 数字全部是本组口径（按 wordId 切片）；重测成绩只追加一行，不覆盖原统计。
  Widget _buildGroupStats() {
    final theme = Theme.of(context);
    final o = _groupOutcome ?? _collectGroupOutcome();
    final total = o.total;
    final wrongCount = o.wrongCount;
    // 综合得分率（本组得分 / 本组满分）
    final percent = o.scoreMax > 0 ? (o.scoreSum * 100 ~/ o.scoreMax) : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('第 ${o.groupNo}/$_groupCount 组完成'),
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
                        Text('本组自选复习完成',
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
                          '本组得分 ${o.scoreSum} / ${o.scoreMax}（$percent%）',
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
                            '${o.enToZhCorrect} / ${o.enToZhAnswered}',
                            Icons.translate, AppColors.primary),
                        const SizedBox(height: 8),
                        _resultRow(theme, '选单词', '${o.chooseCorrect} / $total',
                            Icons.checklist, AppColors.ratingEasy),
                        const SizedBox(height: 8),
                        _resultRow(theme, '默写', '${o.dictCorrect} / $total',
                            Icons.edit_note, AppColors.ratingHard),
                        // 重测成绩只追加，不覆盖上面的口径数字
                        if (o.retryTotal != null) ...[
                          const SizedBox(height: 8),
                          _resultRow(
                              theme,
                              '本轮重测',
                              '${o.retryCorrect ?? 0} / ${o.retryTotal}',
                              Icons.replay,
                              theme.colorScheme.outline),
                        ],
                        const SizedBox(height: 32),
                        if (_groupIndex < _groupCount - 1) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _goNextGroup,
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: Text(
                                  '下一组（第 ${_groupIndex + 2}/$_groupCount 组）',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: _groupIndex < _groupCount - 1
                              ? OutlinedButton(
                                  onPressed: _finishSession,
                                  child: const Text('完成'),
                                )
                              : FilledButton(
                                  onPressed: _finishSession,
                                  child: const Text('完成',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
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

/// 页面阶段（v2.1.8：`result` 已移除——整轮结果页被"每组统计页"取代）
enum _Phase { setup, quiz }

/// 环节（v2.1.8 新增 `groupStats`：本组统计页）
enum _QuizStage { enToZh, chooseWord, dictation, groupStats }

/// 本组统计快照（v2.1.8）。
///
/// 与今日复习的 `_GroupOutcome` 同构，差别是本页为纯练习、没有抽检错词。
/// 重测结果只作为附加行写在它上面，**不回写**三环节结果 map。
class _GroupOutcome {
  _GroupOutcome({
    required this.groupNo,
    required this.total,
    required this.enToZhCorrect,
    required this.enToZhAnswered,
    required this.chooseCorrect,
    required this.dictCorrect,
    required this.wrongIds,
    this.scoreSum = 0,
    this.scoreMax = 0,
  });

  /// 1 起的组号
  final int groupNo;
  /// 本组词数
  final int total;
  final int enToZhCorrect;
  final int enToZhAnswered;
  final int chooseCorrect;
  final int dictCorrect;
  /// 本组错词（wordId）
  final List<int> wrongIds;

  /// 本组得分合计与满分（0–6 分制：满分 = 词数 × 6）
  final int scoreSum;
  final int scoreMax;

  /// 重测结果（未重测时保持 null）
  int? retryTotal;
  int? retryCorrect;

  int get wrongCount => wrongIds.length;
}
