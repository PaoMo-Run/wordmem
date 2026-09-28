import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/quiz_countdown.dart';
import '../../../data/repositories/sync_repository.dart';
import '../../../infra/sync/webdav_client.dart';
import '../../../domain/models/word_option.dart';
import '../../../core/theme/colors.dart';
import 'mastered_quiz_page.dart';
import 'widgets/quiz_cards.dart';

/// 今日复习页面（原"开始复习"）
///
/// 统一的三段式测验流程（与自选复习一致）：
/// 1. 英译汉（翻卡 + FSRS 四档评分）
/// 2. 选单词（看中文释义四选一）
/// 3. 默写（看释义/首字母拼写）
class ReviewPage extends ConsumerStatefulWidget {
  /// v2.1.11：**提前背**模式 —— 只复习「未来 3 小时内到期」的词。
  /// 由首页「提前背」按钮经 `/review?mode=early` 进入。
  ///
  /// 与普通模式共用同一套三环节 / 分组 / 统计页 / 抽检流程，
  /// 差别只在**队列来源**与**临时存档键**（两者不能互相覆盖，见 [_tempSaveKey]）。
  final bool early;

  const ReviewPage({super.key, this.early = false});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  // 当前组队列（v2.1.5：全部待复习词按 50 词一组分测，防止长队列中途丢进度）
  List<Map<String, dynamic>> _queue = [];
  // 全部待复习词（分组前的完整队列）
  List<Map<String, dynamic>> _allQueue = [];
  int _groupIndex = 0;
  static const int _groupSize = 50;
  /// 临时存档键。
  ///
  /// v2.1.11：**提前背用独立的存档键** —— 两种模式的队列完全不同，
  /// 如果共用一个键，用户在普通复习做到一半时去点「提前背」，就会把
  /// 普通复习的存档覆盖掉（回来后进度全丢）。
  String get _tempSaveKey =>
      widget.early ? 'review_temp_save_v1_early' : 'review_temp_save_v1';
  /// v2.1.8：临时存档格式版本。旧档（无该字段）= v1，按「不洗牌」兼容读取。
  static const int _saveVersion = 2;

  int _index = 0;
  bool _loading = true;
  _Stage _stage = _Stage.enToZh;
  // v2.1.5：错题加练模式——纯练习，不重复提交 FSRS 排程、不写临时存档
  bool _isRetryMode = false;

  /// v2.1.8 出题顺序：`_queue` 的下标排列。
  /// 三个环节各自独立洗牌，避免"第 k 位永远是同一个词"形成位置记忆。
  /// 空表示恒等序（旧存档恢复时的兼容路径）。
  List<int> _stageSeq = [];

  /// v2.1.8：本组结束后的统计快照（抽检/重测结果都记在它上面，不回写结果 map）。
  _GroupOutcome? _groupOutcome;
  /// 各组摘要（当前无整轮总览页，留档备用）
  final List<_GroupOutcome> _groupSummaries = [];
  /// 本组是否已走完 `_endOfGroup()` 编排（防重测返回后二次触发抽检询问）
  bool _groupFinalized = false;
  /// 是否已配置 WebDAV（三者齐备）——决定统计页「上传进度」按钮是否置灰
  bool _davConfigured = false;

  // 重测期间的正式结果快照（重测复用同一批 map，结束后还原，保证统计口径不被污染）
  Map<int, bool>? _snapEn;
  Map<int, bool>? _snapChoose;
  Map<int, bool>? _snapDict;
  List<Map<String, dynamic>>? _snapAllQueue;
  List<Map<String, dynamic>>? _snapQueue;
  /// 重测期间暂存的本组统计（重测结束由 `_finishRetry()` 落到 `_groupOutcome`）
  _GroupOutcome? _retryOutcome;

  // 统计（v2.1.5：改为按作答结果派生，左滑返回上一题重答后计数不漂移）
  // v2.1.8：本组口径统计改由 `_GroupOutcome` 承载，这里只留「本轮是否答过题」的判据
  int get _reviewedCount => _enToZhResults.length;

  // 三环节各词作答结果（wordId -> 是否正确；null=跳过/未作答）
  final Map<int, bool> _enToZhResults = {};
  final Map<int, bool> _chooseResults = {};
  final Map<int, bool> _dictResults = {};

  // 三环节各词是否超时（wordId -> 是否超过限时；v2.1.8 评分用）
  final Map<int, bool> _enToZhTimeouts = {};
  final Map<int, bool> _chooseTimeouts = {};
  final Map<int, bool> _dictTimeouts = {};

  /// 作答倒计时的状态句柄（v2.1.8）：作答/跳过那一刻从这里取「本题是否超时」
  final _cdKey = GlobalKey<QuizCountdownState>();

  // v2.1.6：本轮熟练词抽检中答错的词（保留完整数据，用于汇入错词重测）
  final List<Map<String, dynamic>> _quizWrongWords = [];

  // 四选一选项缓存（wordId -> options）
  final Map<int, List<WordOption>> _optionsCache = {};
  // 英译汉选择题选项缓存（wordId -> 中文释义选项）
  final Map<int, List<WordOption>> _enToZhOptionsCache = {};
  // 该词是否有可用中文释义（无则跳过英译汉环节）
  final Map<int, bool> _enToZhAvailable = {};

  /// **唯一口径（v2.1.8）**：本组词的 id 集合。
  /// 统计 / 错题集合 / 抽检错词归属全部基于它，**禁止按 `_queue` 下标切片**——
  /// 三环节乱序后下标与词的对应关系每个环节都不同，按下标算错题必然串组。
  Set<int> get _groupIds => {for (final w in _queue) w['id'] as int};

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  int get _groupCount => (_allQueue.length / _groupSize).ceil();

  /// 出题顺序取值：`_stageSeq` 为空时为恒等序（兼容旧存档）。
  int _seqAt(int i) {
    if (_stageSeq.isEmpty) return i;
    if (i < 0 || i >= _stageSeq.length) return i;
    return _stageSeq[i];
  }

  Future<void> _loadQueue() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(reviewRepositoryProvider);
      // v2.1.11：提前背只取「未来 3 小时内到期」的词（按 due 由近到远）
      _allQueue = widget.early
          ? repo.getUpcomingQueue()
          : repo.getReviewQueue(limit: 500);

      // v2.1.5：存在临时存档时询问是否继续上次进度
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(_tempSaveKey);
      Map<String, dynamic>? saved;
      if (raw != null && raw.isNotEmpty) {
        try {
          saved = (jsonDecode(raw) as Map).cast<String, dynamic>();
        } catch (_) {
          saved = null;
        }
      }
      if (!mounted) return;
      if (saved != null && _allQueue.isNotEmpty) {
        setState(() => _loading = false);
        await _offerResume(saved);
      } else {
        setState(() => _loading = false);
        _startGroup(0);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// 加载指定组（重置组内进度到英译汉第一题）。
  ///
  /// 三环节作答记录跨组累积、只在第 1 组开始时清空——结果页据此统计整轮，
  /// 「重做错题」也才能取到全部组的错题。
  /// 生成一份洗牌后的出题顺序（词集合不变，只改出题次序）。
  static List<int> _buildSeq(int n) {
    final seq = List<int>.generate(n, (i) => i);
    seq.shuffle();
    return seq;
  }

  void _startGroup(int gi) {
    final start = gi * _groupSize;
    var end = (gi + 1) * _groupSize;
    if (end > _allQueue.length) end = _allQueue.length;
    setState(() {
      _groupIndex = gi;
      _queue = _allQueue.sublist(start, end);
      _index = 0;
      _stage = _Stage.enToZh;
      // v2.1.8：分组本身仍是加权随机序，只重洗「组内出题次序」
      _stageSeq = _buildSeq(_queue.length);
      _groupFinalized = false;
      _groupOutcome = null;
      if (gi == 0) {
        _enToZhResults.clear();
        _chooseResults.clear();
        _dictResults.clear();
      }
    });
    _prepareStages();
    _skipUnavailableEnToZh();
    _autoSave();
  }

  // ============================================================
  //  临时存档（v2.1.5）：题目上方「存档退出」按钮，恢复完整测验进度
  // ============================================================

  Future<void> _saveTempProgress() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final data = jsonEncode({
      'saveVersion': _saveVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'allQueueIds': _allQueue.map((w) => w['id'] as int).toList(),
      'groupIndex': _groupIndex,
      'index': _index,
      'stage': _stage.name,
      // v2.1.8：出题顺序与 index 必须成对还原（index 是 _stageSeq 的下标）
      'stageSeq': _stageSeq,
      'groupFinalized': _groupFinalized,
      'enToZh': _enToZhResults.map((k, v) => MapEntry('$k', v)),
      'choose': _chooseResults.map((k, v) => MapEntry('$k', v)),
      'dict': _dictResults.map((k, v) => MapEntry('$k', v)),
      // v2.1.8：超时记录也要存——否则断点续测后的得分会偏高分
      'enToZhOt': _enToZhTimeouts.map((k, v) => MapEntry('$k', v)),
      'chooseOt': _chooseTimeouts.map((k, v) => MapEntry('$k', v)),
      'dictOt': _dictTimeouts.map((k, v) => MapEntry('$k', v)),
    });
    await prefs.setString(_tempSaveKey, data);
  }

  Future<void> _clearTempSave() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.remove(_tempSaveKey);
  }

  /// v2.1.5：每完成一步（作答 / 前进 / 后退 / 切换环节 / 切换组）自动落盘，
  /// 用户无需手动点「存档」，中途退出即为「已保存」状态。
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

  /// 进入复习页时检测到临时存档 → 询问继续或重新开始
  Future<void> _offerResume(Map<String, dynamic> saved) async {
    final gi = (((saved['groupIndex'] as int?) ?? 0) + 1)
        .clamp(1, _groupCount == 0 ? 1 : _groupCount);
    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('继续上次复习进度？'),
        content: Text('检测到未完成的临时存档（第 $gi/$_groupCount 组），'
            '可从中断处继续，或放弃存档重新开始。'),
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
      _startGroup(0);
    }
  }

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
        _startGroup(0);
        return;
      }
      setState(() {
        _allQueue = rows;
        _groupIndex = (((saved['groupIndex'] as int?) ?? 0))
            .clamp(0, _groupCount - 1);
        _queue = _allQueue.sublist(
          _groupIndex * _groupSize,
          (_groupIndex + 1) * _groupSize > _allQueue.length
              ? _allQueue.length
              : (_groupIndex + 1) * _groupSize,
        );
        _stage = _stageFromName(saved['stage'] as String?);
        // v2.1.8：先还原 stageSeq、再定 index —— `_index` 是 `_stageSeq` 的下标，
        // 两者必须成对还原，否则断点续测会落到另一个词上。
        // 旧档（无 saveVersion / 无 stageSeq）→ 恒等序（旧版本本就没洗牌，语义等价，
        // 因此保留 index 不丢进度，比"回到本组开头"更友好）。
        _stageSeq = _decodeSeq(saved['stageSeq'], _queue.length);
        _groupFinalized = saved['groupFinalized'] == true;
        _index = ((saved['index'] as int?) ?? 0)
            .clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
        _groupOutcome = null;
        _enToZhResults.clear();
        _chooseResults.clear();
        _dictResults.clear();
        _enToZhTimeouts.clear();
        _chooseTimeouts.clear();
        _dictTimeouts.clear();
        _enToZhResults.addAll(_decodeBoolMap(saved['enToZh']));
        _chooseResults.addAll(_decodeBoolMap(saved['choose']));
        _dictResults.addAll(_decodeBoolMap(saved['dict']));
        // 旧档没有这三项 → 视为「都没超时」（宁宽松不误扣）
        _enToZhTimeouts.addAll(_decodeBoolMap(saved['enToZhOt']));
        _chooseTimeouts.addAll(_decodeBoolMap(saved['chooseOt']));
        _dictTimeouts.addAll(_decodeBoolMap(saved['dictOt']));
      });
      _prepareStages();
      if (_stage == _Stage.enToZh) {
        _skipUnavailableEnToZh();
      } else if (_stage == _Stage.groupStats) {
        _refreshDavConfigured();
      }
    } catch (_) {
      _startGroup(0);
    }
  }

  /// 阶段名 → 枚举。容错**未知阶段值**（将来再改阶段也不会崩）；
  /// v1 旧档的 `done`（整轮结束页）已废弃 → 归到本组统计页。
  static _Stage _stageFromName(String? name) {
    final n = name ?? _Stage.enToZh.name;
    if (n == 'done') return _Stage.groupStats;
    return _Stage.values.firstWhere(
      (s) => s.name == n,
      orElse: () => _Stage.enToZh,
    );
  }

  /// 还原出题顺序：缺失 / 长度不符 / 不是排列 → 恒等序（旧档兼容：不崩、不洗牌）。
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

  static Map<int, bool> _decodeBoolMap(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(int.tryParse('$k') ?? -1, v == true))
      ..remove(-1);
  }

  /// 跳过无中文释义的词（英译汉环节无法出题，不计对错）。
  /// v2.1.8：按 `_stageSeq` 取词——第 k 题是 `_queue[_seqAt(k)]`。
  void _skipUnavailableEnToZh() {
    while (_index < _stageSeq.length &&
        !(_enToZhAvailable[_queue[_seqAt(_index)]['id'] as int] ?? false)) {
      _index++;
    }
    if (_index >= _stageSeq.length) {
      _enterChooseWord();
    }
  }

  /// 预生成两个环节的选项（v2.1.5：统一走 repo.buildReviewStageOptions，
  /// 干扰项在复习词组/个人词库/词典中随机抽选，修复旧逻辑可观察规律 bug）：
  /// - 四选一（选单词）：看中文选英文
  /// - 英译汉选择题：看英文选中文（正确项 = 该词释义）
  void _prepareStages() {
    _optionsCache.clear();
    _enToZhOptionsCache.clear();
    _enToZhAvailable.clear();
    final repo = ref.read(wordRepositoryProvider);

    final stages = repo.buildReviewStageOptions(_queue);
    stages.forEach((id, s) {
      _optionsCache[id] = s.wordOptions;
      _enToZhOptionsCache[id] = s.enToZhAvailable ? s.enToZhOptions : const [];
      _enToZhAvailable[id] = s.enToZhAvailable;
    });
  }

  // ============================================================
  //  当前词信息
  // ============================================================

  /// 当前词。v2.1.8：经 `_stageSeq` 映射，`_index` 是"第几题"而非 `_queue` 下标。
  Map<String, dynamic> get _word => _queue[_seqAt(_index)];
  String get _currentWord => _word['word'] as String;
  String get _currentDef => ((_word['custom_def'] as String?) ?? '').trim();

  // ============================================================
  //  阶段1：英译汉（选择题，记录对错，不立即提交）
  // ============================================================

  void _enToZhAnswered(bool correct) {
    final id = _word['id'] as int;
    setState(() {
      _enToZhResults[id] = correct;
      // v2.1.8：同时记下本题是否超时（评分用）
      _enToZhTimeouts[id] = _cdKey.currentState?.isOvertime ?? false;
    });
    _autoSave();
  }

  void _advanceFromEnToZh() {
    if (_index < _stageSeq.length - 1) {
      setState(() => _index++);
      _skipUnavailableEnToZh();
      if (_index >= _stageSeq.length) _enterChooseWord();
      _autoSave();
    } else {
      _enterChooseWord();
    }
  }

  /// 进入「选单词」环节：重新洗牌一份出题顺序（v2.1.8，避免位置记忆）。
  void _enterChooseWord() {
    setState(() {
      _index = 0;
      _stage = _Stage.chooseWord;
      _stageSeq = _buildSeq(_queue.length);
    });
    _autoSave();
  }

  // ============================================================
  //  阶段2：四选一
  // ============================================================

  List<WordOption> get _currentOptions =>
      _optionsCache[_word['id'] as int] ??
      [WordOption(word: _currentWord, definition: _currentDef)];

  void _chooseAnswered(bool correct) {
    final id = _word['id'] as int;
    setState(() {
      _chooseResults[id] = correct;
      _chooseTimeouts[id] = _cdKey.currentState?.isOvertime ?? false;
    });
    _autoSave();
  }

  void _advanceFromChoose() {
    if (_index < _stageSeq.length - 1) {
      setState(() => _index++);
    } else {
      // 进入「默写」环节：再洗一次出题顺序（v2.1.8）
      setState(() {
        _index = 0;
        _stage = _Stage.dictation;
        _stageSeq = _buildSeq(_queue.length);
      });
    }
    _autoSave();
  }

  // ============================================================
  //  阶段3：默写
  // ============================================================

  void _dictationAnswered(bool correct) {
    final id = _word['id'] as int;
    setState(() {
      _dictResults[id] = correct;
      _dictTimeouts[id] = _cdKey.currentState?.isOvertime ?? false;
    });
    _autoSave();
  }

  Future<void> _advanceFromDictation() async {
    if (_index < _stageSeq.length - 1) {
      setState(() => _index++);
      _autoSave();
      return;
    }
    if (_isRetryMode) {
      // 错题检验（纯练习）走完 → 结算 → 回到本组统计页，不再走组结束编排
      _finishRetry();
      return;
    }
    // 本组三环节走完：提交本组 FSRS（按 wordId，与出题顺序无关）→ 清存档 → 组结束编排
    _commitAllReviews();
    _clearTempSave();
    await _endOfGroup();
  }

  // ============================================================
  //  组结束编排（v2.1.8）：抽检询问 → 本组统计 → 重测询问 → 统计页
  // ============================================================

  /// 本组结束的**唯一**编排入口（替代 v2.1.7 的 `_finishGroup`）。
  ///
  /// 与旧版的差别（本次改造的全部价值）：
  /// - 不再连弹「抽检 + 上传」两个模态框（上传改为统计页上的按钮）；
  /// - 统计页**每组都出现**，而不是只在整轮末；
  /// - 错题重测在本组末询问，结束后**回到本组统计页**（不回首页、不串组）。
  Future<void> _endOfGroup() async {
    if (_groupFinalized) return;

    // ① 抽检询问（池子为空则不弹；选「暂不」也会记账 due +7 天）
    await _maybeOfferMasteredQuiz();
    if (!mounted) return;

    // ② 内部统计：本组复习错题 ∪ 本组抽检错词（纯计算，不弹 UI）
    final outcome = _collectGroupOutcome();

    // ③ 有错题 → 询问是否重测
    if (outcome.wrongCount > 0) {
      final started = await _maybeOfferGroupRetry(outcome);
      if (!mounted) return;
      if (started) return; // 重测结束后由 _finishRetry() 落到统计页
    }
    // 未重测：抽检错词仍要结算（保留 mastered + 推入 3 天复检窗口）
    _settleQuizWrongWithoutRetry();

    _showGroupStats(outcome);
  }

  /// 呈现本组统计页。调用前抽检错词必须已结算完毕。
  void _showGroupStats(_GroupOutcome outcome) {
    _groupSummaries.add(outcome);
    setState(() {
      _groupOutcome = outcome;
      _groupFinalized = true;
      _stage = _Stage.groupStats;
    });
    _refreshDavConfigured();
    _autoSave(); // 断点：在统计页退出后重进能回到统计页
  }

  /// 本组口径统计快照。
  /// **全部按 `wordId` + `_groupIds` 切片**，与出题顺序无关 ——
  /// 这是三环节乱序与流程重梳理共用的地基，按下标算必然串组。
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
      quizWrongIds: [for (final w in _quizWrongWords) w['id'] as int],
      scoreSum: scoreSum,
      scoreMax: _queue.length * AppConstants.quizMaxScore,
    );
  }

  /// 询问是否重测本组错题。
  /// 返回 true = 已进入重测 —— 调用方**必须直接返回**，由 `_finishRetry()`
  /// 负责回到统计页，不得再走一遍编排（否则会二次弹抽检）。
  Future<bool> _maybeOfferGroupRetry(_GroupOutcome outcome) async {
    final rows = _retryRowsFor(outcome);
    if (rows.isEmpty) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重测本组错题？'),
        content: Text('本组有 ${outcome.wrongCount} 个词答错过了。'
            '重测为纯练习，不会改变刚才的复习结果，只为加深记忆。'),
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

    // 快照正式结果：重测复用同一批结果 map，结束后还原，
    // 保证统计页数字仍是 FSRS 口径（重测成绩只作为附加行展示）。
    _snapEn = Map<int, bool>.from(_enToZhResults);
    _snapChoose = Map<int, bool>.from(_chooseResults);
    _snapDict = Map<int, bool>.from(_dictResults);
    _snapAllQueue = _allQueue;
    _snapQueue = _queue;
    _retryOutcome = outcome;

    setState(() {
      _allQueue = rows;
      // 重测**不再按 50 词切分**：整批一次走完。
      // （抽检错词最多 5 个，本组错词最多 50 个，若仍走 _startGroup(0)
      //   切片，第 51 个之后的词会被静默丢掉。）
      _queue = rows;
      _index = 0;
      _stage = _Stage.enToZh;
      _stageSeq = _buildSeq(_queue.length);
      _isRetryMode = true;
      _enToZhResults.clear();
      _chooseResults.clear();
      _dictResults.clear();
    });
    _prepareStages();
    _skipUnavailableEnToZh();
    return true;
  }

  /// 重测用词：本组复习错词 + 抽检错词（保持队列原顺序，去重）
  List<Map<String, dynamic>> _retryRowsFor(_GroupOutcome outcome) {
    final byId = <int, Map<String, dynamic>>{
      for (final w in _queue) w['id'] as int: w,
      // 抽检错词是已掌握词，不在 _queue 里，单独并入
      for (final w in _quizWrongWords) w['id'] as int: w,
    };
    final ids = <int>[...outcome.wrongIds];
    for (final id in outcome.quizWrongIds) {
      if (!ids.contains(id)) ids.add(id);
    }
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 重测走完：结算抽检错词 → 还原本组正式结果 → 回到统计页。
  void _finishRetry() {
    final outcome = _retryOutcome;
    if (outcome != null) {
      // 重测成绩只作为附加行（不覆盖原统计）：口径 = 错题里还剩几个没记住
      outcome.retryTotal = _queue.length;
      outcome.retryCorrect = _queue.length - _wrongIds.length;
    }
    // 抽检错词的第二次失败 → 退回 T3；答对 → 不洗白 + 推入 3 天复检窗口。
    // ⚠️ 必须在还原快照**之前**结算（它读的是重测这一轮的结果）。
    _applyQuizRetryOutcome();
    _retryOutcome = null;

    // 还原正式结果与队列，回到本组统计页
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
      setState(() => _stage = _Stage.groupStats);
    }
  }

  /// 未重测时对抽检错词的结算：保留 mastered（不降级），只推入 3 天复检窗口，
  /// 并**清空错词池** —— 既是 v2.1.6「重做错题无限循环」防线的延续，
  /// 也保证上一组的抽检错词不会混进下一组的归属。
  void _settleQuizWrongWithoutRetry() {
    if (_quizWrongWords.isEmpty) return;
    final repo = ref.read(reviewRepositoryProvider);
    for (final w in _quizWrongWords) {
      try {
        repo.holdMasteredQuizWrongMark(w['id'] as int);
      } catch (_) {
        // 单条失败不影响其余
      }
    }
    _quizWrongWords.clear();
  }

  /// 读一次网盘配置（url / user / password 三者齐备才算已配置）
  Future<void> _refreshDavConfigured() async {
    var ok = false;
    try {
      final store = ref.read(syncSettingsStoreProvider);
      final url = await store.read(SyncSettingKeys.davUrl);
      final user = await store.read(SyncSettingKeys.davUser);
      final password = await store.read(SyncSettingKeys.davPassword);
      ok = (url ?? '').isNotEmpty &&
          (user ?? '').isNotEmpty &&
          (password ?? '').isNotEmpty;
    } catch (_) {
      ok = false;
    }
    if (mounted && ok != _davConfigured) {
      setState(() => _davConfigured = ok);
    }
  }

  /// 询问是否对已掌握词做抽检（v2.1.6）。
  ///
  /// 即使用户选「暂不」，也会把抽到的词**记账**（due 推后 7 天）——
  /// 既避免下次又抽到同一批，也避免它们被误认为「已测过」而长期搁置。
  Future<void> _maybeOfferMasteredQuiz() async {
    if (_isRetryMode) return; // 错题加练环节不抽检
    final repo = ref.read(reviewRepositoryProvider);
    final List<Map<String, dynamic>> words;
    try {
      words = repo.pickMasteredQuizWords();
    } catch (_) {
      return;
    }
    if (words.isEmpty || !mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('抽检已掌握的词？'),
        content: Text(
          '从已走完全部复习周期（T0–T7）的词里随机抽了 ${words.length} 个做默写，'
          '检测是否还记得。答错的词会进入本轮错词重测。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始抽检'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (go != true) {
      // 记账：跳过也推后 due，防止下次重复抽到同一批
      repo.skipMasteredQuiz(words.map((w) => w['id'] as int).toList());
      return;
    }

    final wrongIds = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => MasteredQuizPage(words: words)),
    );
    if (!mounted || wrongIds == null || wrongIds.isEmpty) return;
    setState(() {
      _quizWrongWords.addAll(
        words.where((w) => wrongIds.contains(w['id'] as int)),
      );
    });
  }

  /// 错词重测结束后的抽检词结算（v2.1.6）：
  /// - 重测中仍有环节答错 → 第 2 次失败 → **立即**移出 mastered，退回 T3
  /// - 重测全对 → **不洗白**：保留「一次答错」标记，只把复检窗口推到 3 天后；
  ///   若 3 天后的复检再错，同样会退回 T3
  ///
  /// ⚠️ v2.1.6 修复：结算完成后必须**清空** `_quizWrongWords`。
  /// 否则结果页会把这些抽检错词反复计入「重做错题」，用户点一次就再重测一轮，
  /// 形成「重做错题 → 仍是这几词 → 再重做」的无限循环。
  void _applyQuizRetryOutcome() {
    if (_quizWrongWords.isEmpty) return;
    final repo = ref.read(reviewRepositoryProvider);
    for (final w in _quizWrongWords) {
      final id = w['id'] as int;
      final stillWrong = _enToZhResults[id] == false ||
          _chooseResults[id] == false ||
          _dictResults[id] == false;
      try {
        if (stillWrong) {
          repo.demoteMasteredToT3(id);
        } else {
          repo.holdMasteredQuizWrongMark(id);
        }
      } catch (_) {
        // 单条失败不影响其余
      }
    }
    // 结算完毕即清空——防止结果页再次把它们计入「重做错题」而陷入循环
    if (mounted) setState(() => _quizWrongWords.clear());
  }

  /// 统计页「上传进度」按钮的处理（v2.1.8）。
  ///
  /// 由 `_maybePromptUpload()`（弹窗版）改造而来：**去掉最外层询问框**——
  /// 用户已经用点按钮表达了意愿，不需要再问一次；但
  /// `needsConfirmation` 时的**防呆二次确认必须保留**（确认链不变量）。
  Future<void> _uploadProgressFromStats() async {
    try {
      final store = ref.read(syncSettingsStoreProvider);
      final url = await store.read(SyncSettingKeys.davUrl);
      final user = await store.read(SyncSettingKeys.davUser);
      final password = await store.read(SyncSettingKeys.davPassword);
      if (url == null || url.isEmpty || !mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('正在上传备份...'),
          duration: Duration(minutes: 1),
        ));

      final repo = SyncRepository(
        storage: WebdavSyncStorage(
          url: url,
          user: user ?? '',
          password: password ?? '',
        ),
        settings: store,
        localStats: ref.read(syncLocalStatsProvider),
        backup: ref.read(syncBackupGatewayProvider),
      );
      var result = await repo.upload();
      if (result.needsConfirmation && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认上传'),
            content: Text(result.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续上传'),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('已取消上传')));
          }
          return;
        }
        result = await repo.upload(confirmed: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('上传失败，请稍后在「我的 - 进度同步」中重试')));
      }
    }
  }

  /// 左滑/「上一题」返回当前环节的上一题（v2.1.5，防误点跳过）。
  /// 返回时清除该词在当前环节的作答记录，重答后按新结果计数。
  /// 英译汉环节会跳过无中文释义的词；已在环节第一题时不可回退。
  bool _canGoBackInStage() {
    switch (_stage) {
      case _Stage.enToZh:
        // v2.1.8：下标须经 _stageSeq 映射——第 k 题是 _queue[_seqAt(k)]
        for (var i = _index - 1; i >= 0; i--) {
          if (_enToZhAvailable[_queue[_seqAt(i)]['id'] as int] ?? false) {
            return true;
          }
        }
        return false;
      case _Stage.chooseWord:
      case _Stage.dictation:
        return _index > 0;
      case _Stage.groupStats:
        return false;
    }
  }

  void _goBackInStage() {
    switch (_stage) {
      case _Stage.enToZh:
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
      case _Stage.chooseWord:
        if (_index == 0) return;
        setState(() {
          _index--;
          final id = _queue[_seqAt(_index)]['id'] as int;
          _chooseResults.remove(id);
          _chooseTimeouts.remove(id);
        });
        _autoSave();
      case _Stage.dictation:
        if (_index == 0) return;
        setState(() {
          _index--;
          final id = _queue[_seqAt(_index)]['id'] as int;
          _dictResults.remove(id);
          _dictTimeouts.remove(id);
        });
        _autoSave();
      case _Stage.groupStats:
        break;
    }
  }

  /// 当前题是否已作答（v2.1.8：卡片内「跳过」按钮已删，
  /// 未作答时把「下一题」染成主色，引导"不会就跳过"的视线）
  bool get _currentAnswered {
    final id = _word['id'] as int;
    switch (_stage) {
      case _Stage.enToZh:
        return _enToZhResults.containsKey(id);
      case _Stage.chooseWord:
        return _chooseResults.containsKey(id);
      case _Stage.dictation:
        return _dictResults.containsKey(id);
      case _Stage.groupStats:
        return true;
    }
  }

  /// 右上角「下一题」：与「跳过」同义（未作答即跳过）
  ///
  /// v2.1.8：跳过按**答错**计（由结果 map 里的 null 承担），
  /// 但必须在这里补记「本题是否超时」——跳过路径不经过卡片回调，
  /// 漏记就会少扣那 1 分。
  void _advanceCurrent() {
    _recordSkipTimeout();
    switch (_stage) {
      case _Stage.enToZh:
        _advanceFromEnToZh();
      case _Stage.chooseWord:
        _advanceFromChoose();
      case _Stage.dictation:
        _advanceFromDictation();
      case _Stage.groupStats:
        break;
    }
  }

  /// 未作答就前进时补记超时；已作答的题不覆盖（它的超时在作答那一刻已记下）
  void _recordSkipTimeout() {
    if (_stage == _Stage.groupStats) return;
    if (_currentAnswered) return;
    final id = _word['id'] as int;
    final overtime = _cdKey.currentState?.isOvertime ?? false;
    switch (_stage) {
      case _Stage.enToZh:
        _enToZhTimeouts[id] = overtime;
      case _Stage.chooseWord:
        _chooseTimeouts[id] = overtime;
      case _Stage.dictation:
        _dictTimeouts[id] = overtime;
      case _Stage.groupStats:
        break;
    }
  }

  /// 题目导航行（v2.1.5）：左「上一题」/ 中「自动保存」标记 / 右「下一题」。
  /// 进度在每步作答后自动落盘，不再需要手动点「存档」。
  ///
  /// v2.1.8：卡片内的「跳过」已删，这里未作答时对「下一题」做主色强调——
  /// 三环节与错题检验共用本导航行，强调逻辑天然一致。
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

  /// 三环节全部结束后，一次性提交本组（按 wordId，与出题顺序无关）。
  ///
  /// v2.1.8：提交的是**测验得分**（0–6）。排期与评分已解耦——
  /// `FsrsService.review` 固定走满 T0–T7 八个节点，不再因评分跳档。
  void _commitAllReviews() {
    try {
      final repo = ref.read(reviewRepositoryProvider);
      for (final w in _queue) {
        final id = w['id'] as int;
        repo.submitReview(
          id,
          score: _scoreFor(id),
          timeouts: _timeoutCountFor(id),
        );
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

  /// 本轮该词的得分（0–6）。
  ///
  /// 满分 = 三环节 × 2 分：**每答错一次扣 1 分**（未作答 / 跳过按答错计），
  /// **每环节超过限时再扣 1 分**。三环节全错且全超时 → 0 分；全对且都不超时 → 6 分。
  int _scoreFor(int wordId) {
    var score = AppConstants.quizMaxScore;
    void judge(bool? correct, bool? overtime) {
      if (correct != true) score -= 1;
      if (overtime == true) score -= 1;
    }

    judge(_enToZhResults[wordId], _enToZhTimeouts[wordId]);
    judge(_chooseResults[wordId], _chooseTimeouts[wordId]);
    judge(_dictResults[wordId], _dictTimeouts[wordId]);
    return score.clamp(0, AppConstants.quizMaxScore);
  }

  /// 本轮该词超时的环节数（0–3），随得分一起写进复习历史
  int _timeoutCountFor(int wordId) => [
        _enToZhTimeouts[wordId],
        _chooseTimeouts[wordId],
        _dictTimeouts[wordId],
      ].where((o) => o == true).length;

  // ============================================================
  //  错题加练（v2.1.5）
  // ============================================================

  /// 错题集：三环节中任一答错即算错题（跳过的环节不计），保持**本组队列**原顺序。
  ///
  /// v2.1.8：① 按 `_groupIds` 切片（只算本组的词，不再跨组累积）；
  /// ② 遍历 `_queue` 而不是 `_allQueue`（后者是整轮全量，会带出别的组的错词）。
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

  // ============================================================
  //  构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.early ? '提前背' : '今日复习'),
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
    if (_stage == _Stage.groupStats) return _buildGroupStats();
    if (_queue.isEmpty) return _buildEmpty();
    return _buildQuiz();
  }

  Widget _buildEmpty() {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.early ? '提前背' : '今日复习'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: EmptyState(
        icon: Icons.check_circle_outline,
        title: _reviewedCount > 0
            ? '复习完成！'
            : (widget.early ? '未来 3 小时没有词到期' : '暂无待复习单词'),
        subtitle: _reviewedCount > 0
            ? '本次复习了 $_reviewedCount 个单词'
            : (widget.early ? '这些词还没到复习时间，到点再来' : '稍后再来看看吧'),
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
    String title;
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
          isLast: _index == total - 1,
          onPlayWord: audioEnabled
              ? (w) => ref.read(pronunciationServiceProvider).speak(w)
              : null,
        );
      case _Stage.groupStats:
        title = '';
        card = const SizedBox.shrink();
    }
    // v2.1.5：多组时在标题中显示分组进度
    if (_groupCount > 1) {
      title = '$title · 第 ${_groupIndex + 1}/$_groupCount 组';
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
                              // v2.1.8：题干上方的作答倒计时
                              // （默写 8 秒、英译汉/选单词 5 秒；息屏回来自动重置）
                              QuizCountdown(
                                key: _cdKey,
                                limit: _stage == _Stage.dictation
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
    );
  }

  /// 本组统计页（v2.1.8）：**每组结束都出现**，取代原来"只在整轮末出现"的结果页。
  ///
  /// - 数字全部是**本组口径**（按 `wordId` 切片，与出题顺序无关）；
  /// - 重测成绩**只追加一行**，不覆盖上面的 FSRS 口径数字；
  /// - 页内三个按钮决定下一步：下一组 / 完成 / 上传进度（不再弹窗询问）。
  Widget _buildGroupStats() {
    final theme = Theme.of(context);
    final o = _groupOutcome ?? _collectGroupOutcome();
    final hasNext = _groupIndex < _groupCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${o.groupNo}/$_groupCount 组完成'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      // 结果页同样可滚动，避免小屏溢出
      body: LayoutBuilder(
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
                      o.wrongCount == 0
                          ? Icons.check_circle_outline
                          : Icons.school_outlined,
                      size: 72,
                      color: o.wrongCount == 0
                          ? AppColors.ratingGood
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      o.wrongCount == 0
                          ? '本组全部答对'
                          : '本组有 ${o.wrongCount} 个词答错过',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: o.wrongCount == 0
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.7)
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _resultRow(
                        theme,
                        '英译汉',
                        '${o.enToZhCorrect} / ${o.enToZhAnswered}',
                        Icons.translate,
                        AppColors.primary),
                    const SizedBox(height: 8),
                    _resultRow(theme, '选单词', '${o.chooseCorrect} / ${o.total}',
                        Icons.checklist, AppColors.ratingEasy),
                    const SizedBox(height: 8),
                    _resultRow(theme, '默写', '${o.dictCorrect} / ${o.total}',
                        Icons.edit_note, AppColors.ratingHard),
                    // v2.1.8：本组测验得分（三环节 × 2 分扣分制）
                    if (o.scoreMax > 0) ...[
                      const SizedBox(height: 8),
                      _resultRow(theme, '本组得分',
                          '${o.scoreSum} / ${o.scoreMax}',
                          Icons.percent, AppColors.primary),
                    ],
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
                    if (hasNext) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _goNextGroup,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text('下一组（第 ${_groupIndex + 2}/$_groupCount 组）',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: hasNext
                          ? OutlinedButton(
                              onPressed: _finishSession,
                              child: const Text('完成'),
                            )
                          : FilledButton(
                              onPressed: _finishSession,
                              child: const Text('完成',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        // 未配置网盘：置灰但仍可点，点了给出配置指引（避免"假入口"）
                        onPressed: _davConfigured
                            ? _uploadProgressFromStats
                            : _showDavHint,
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('上传进度'),
                        style: _davConfigured
                            ? null
                            : OutlinedButton.styleFrom(
                                foregroundColor: theme
                                    .colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 下一组：本组词的排期已在 `_commitAllReviews()` 推进，队列层面已不再命中
  void _goNextGroup() {
    if (_groupIndex >= _groupCount - 1) return;
    _startGroup(_groupIndex + 1);
  }

  /// 完成：清临时存档并回首页。
  ///
  /// 当前 50 词的 `due` 已在 `_commitAllReviews()` 沿 T0–T7 推进，
  /// 队列与首页统计层面已自动不再命中 —— 无需额外的"标记完成"动作。
  void _finishSession() {
    _clearTempSave();
    if (mounted) context.pop();
  }

  /// 未配置网盘时点「上传进度」：给出明确的去配置指引
  void _showDavHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('还没配置网盘，请到「我的 - 进度同步」填写 WebDAV 地址与账号'),
      ));
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

/// 复习阶段。
///
/// v2.1.8：新增 `groupStats`（**本组**统计页）；删除旧的 `done`（整轮收尾页）——
/// 「完成」现在直接回首页，不再保留整轮总览页。
/// 旧存档里的 `done` 由 `_stageFromName()` 归一到 `groupStats`，保证不崩。
enum _Stage { enToZh, chooseWord, dictation, groupStats }

/// 本组统计快照（v2.1.8）。
///
/// 每组结算一次；重测结果只作为附加行写在它上面，**不回写**三环节结果 map ——
/// 从而保证统计页数字始终是 FSRS 口径，不被练习结果污染。
class _GroupOutcome {
  _GroupOutcome({
    required this.groupNo,
    required this.total,
    required this.enToZhCorrect,
    required this.enToZhAnswered,
    required this.chooseCorrect,
    required this.dictCorrect,
    required this.wrongIds,
    required this.quizWrongIds,
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
  /// 本组复习错词（wordId）
  final List<int> wrongIds;
  /// 本组抽检错词（wordId）。已掌握词不在 `_queue` 里，故单独记
  final List<int> quizWrongIds;

  /// 本组得分合计与满分（v2.1.8 的 0–6 分制：满分 = 词数 × 6）
  final int scoreSum;
  final int scoreMax;

  /// 重测结果（未重测时保持 null）
  int? retryTotal;
  int? retryCorrect;

  int get wrongCount => wrongIds.length + quizWrongIds.length;
}
