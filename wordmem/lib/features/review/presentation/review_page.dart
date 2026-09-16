import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../data/repositories/sync_repository.dart';
import '../../../infra/sync/webdav_client.dart';
import '../../../domain/models/review_rating.dart';
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
  const ReviewPage({super.key});

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
  static const String _tempSaveKey = 'review_temp_save_v1';

  int _index = 0;
  bool _loading = true;
  _Stage _stage = _Stage.enToZh;
  // v2.1.5：错题加练模式——纯练习，不重复提交 FSRS 排程、不写临时存档
  bool _isRetryMode = false;

  // 统计（v2.1.5：改为按作答结果派生，左滑返回上一题重答后计数不漂移）
  int get _reviewedCount => _enToZhResults.length;
  int get _chooseCorrect => _chooseResults.values.where((v) => v).length;
  int get _dictationCorrect => _dictResults.values.where((v) => v).length;

  // 三环节各词作答结果（wordId -> 是否正确；null=跳过/未作答）
  final Map<int, bool> _enToZhResults = {};
  final Map<int, bool> _chooseResults = {};
  final Map<int, bool> _dictResults = {};

  // v2.1.6：本轮熟练词抽检中答错的词（保留完整数据，用于汇入错词重测）
  final List<Map<String, dynamic>> _quizWrongWords = [];

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

  int get _groupCount => (_allQueue.length / _groupSize).ceil();

  Future<void> _loadQueue() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(reviewRepositoryProvider);
      _allQueue = repo.getReviewQueue(limit: 500);

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
  void _startGroup(int gi) {
    final start = gi * _groupSize;
    var end = (gi + 1) * _groupSize;
    if (end > _allQueue.length) end = _allQueue.length;
    setState(() {
      _groupIndex = gi;
      _queue = _allQueue.sublist(start, end);
      _index = 0;
      _stage = _Stage.enToZh;
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
      'savedAt': DateTime.now().toIso8601String(),
      'allQueueIds': _allQueue.map((w) => w['id'] as int).toList(),
      'groupIndex': _groupIndex,
      'index': _index,
      'stage': _stage.name,
      'enToZh': _enToZhResults.map((k, v) => MapEntry('$k', v)),
      'choose': _chooseResults.map((k, v) => MapEntry('$k', v)),
      'dict': _dictResults.map((k, v) => MapEntry('$k', v)),
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
        _index = ((saved['index'] as int?) ?? 0)
            .clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
        _stage = _Stage.values.firstWhere(
          (s) => s.name == (saved['stage'] as String? ?? 'enToZh'),
          orElse: () => _Stage.enToZh,
        );
        _enToZhResults.clear();
        _chooseResults.clear();
        _dictResults.clear();
        _enToZhResults.addAll(_decodeBoolMap(saved['enToZh']));
        _chooseResults.addAll(_decodeBoolMap(saved['choose']));
        _dictResults.addAll(_decodeBoolMap(saved['dict']));
      });
      _prepareStages();
      if (_stage == _Stage.enToZh) _skipUnavailableEnToZh();
    } catch (_) {
      _startGroup(0);
    }
  }

  static Map<int, bool> _decodeBoolMap(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(int.tryParse('$k') ?? -1, v == true))
      ..remove(-1);
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
    setState(() => _enToZhResults[_word['id'] as int] = correct);
    _autoSave();
  }

  void _advanceFromEnToZh() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
      _skipUnavailableEnToZh();
      if (_index >= _queue.length) _enterChooseWord();
      _autoSave();
    } else {
      _enterChooseWord();
    }
  }

  void _enterChooseWord() {
    setState(() {
      _index = 0;
      _stage = _Stage.chooseWord;
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
    setState(() => _chooseResults[_word['id'] as int] = correct);
    _autoSave();
  }

  void _advanceFromChoose() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
    } else {
      setState(() {
        _index = 0;
        _stage = _Stage.dictation;
      });
    }
    _autoSave();
  }

  // ============================================================
  //  阶段3：默写
  // ============================================================

  void _dictationAnswered(bool correct) {
    setState(() => _dictResults[_word['id'] as int] = correct);
    _autoSave();
  }

  void _advanceFromDictation() {
    if (_index < _queue.length - 1) {
      setState(() => _index++);
      _autoSave();
    } else {
      // 错题加练为纯练习：不重复提交复习排程
      if (!_isRetryMode) _commitAllReviews();
      _clearTempSave(); // 本组已完成，清临时存档
      _finishGroup();
    }
  }

  /// 本组收尾（v2.1.6）：抽检询问 → 上传询问 → 进入下一组 / 结束整轮。
  ///
  /// 上传询问以**每个 50 词组结束为节点**（末尾不足 50 的单组也算）；
  /// 用户若选择继续抽检，抽检结束后同样会回到这里追问一次。
  /// 错题重测为纯练习，不重复询问上传。
  Future<void> _finishGroup() async {
    // 1) 询问是否抽检已掌握词（含"暂不"时的记账处理）
    await _maybeOfferMasteredQuiz();
    if (!mounted) return;

    // 2) 每组结束后询问是否上传学习数据（仅在已配置 WebDAV 时弹出）
    if (!_isRetryMode) {
      await _maybePromptUpload();
      if (!mounted) return;
    }

    // 3) 进入下一组 / 结束整轮
    if (_groupIndex < _groupCount - 1) {
      _startGroup(_groupIndex + 1);
    } else {
      setState(() => _stage = _Stage.done);
      if (_isRetryMode) {
        // 错词重测收尾：抽检错词若仍答错 → 第 2 次失败 → 退回 T3
        _applyQuizRetryOutcome();
      }
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
          '从已掌握的词里随机抽了 ${words.length} 个做默写，检测是否还记得。'
          '答错的词会进入本轮错词重测。',
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

  /// 复习完成后询问是否上传学习数据（仅在已配置 WebDAV 时弹出）。
  /// 复用 sync_page 的上传管线（含防呆检查：需确认时二次弹窗）。
  Future<void> _maybePromptUpload() async {
    try {
      final store = ref.read(syncSettingsStoreProvider);
      final url = await store.read(SyncSettingKeys.davUrl);
      final user = await store.read(SyncSettingKeys.davUser);
      final password = await store.read(SyncSettingKeys.davPassword);
      if (url == null || url.isEmpty || !mounted) return;

      final wantsUpload = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('上传学习数据？'),
          content: const Text('本次复习已完成，可将最新学习进度备份到云端。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('暂不'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('上传'),
            ),
          ],
        ),
      );
      if (wantsUpload != true || !mounted) return;

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
        for (var i = _index - 1; i >= 0; i--) {
          if (_enToZhAvailable[_queue[i]['id'] as int] ?? false) return true;
        }
        return false;
      case _Stage.chooseWord:
      case _Stage.dictation:
        return _index > 0;
      case _Stage.done:
        return false;
    }
  }

  void _goBackInStage() {
    switch (_stage) {
      case _Stage.enToZh:
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
      case _Stage.chooseWord:
        if (_index == 0) return;
        setState(() {
          _index--;
          _chooseResults.remove(_queue[_index]['id'] as int);
        });
        _autoSave();
      case _Stage.dictation:
        if (_index == 0) return;
        setState(() {
          _index--;
          _dictResults.remove(_queue[_index]['id'] as int);
        });
        _autoSave();
      case _Stage.done:
        break;
    }
  }

  /// 右上角「下一题」：与「跳过」同义（未作答即跳过，不计对错）
  void _advanceCurrent() {
    switch (_stage) {
      case _Stage.enToZh:
        _advanceFromEnToZh();
      case _Stage.chooseWord:
        _advanceFromChoose();
      case _Stage.dictation:
        _advanceFromDictation();
      case _Stage.done:
        break;
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

  /// 三环节全部结束后，按"各环节正确率"一次性写入 FSRS：
  /// 全部正确 → easy（最高）；2/3 → good；1/3 → hard；全错 → again（最低）。
  /// 跳过的环节不计入分母。
  void _commitAllReviews() {    try {
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

  /// 重做全部错题：以错题重建队列从头再来一轮。
  /// v2.1.6 起同时并入**熟练词抽检**中答错的词。
  /// 纯加练——不重复提交复习排程，也不写临时存档。
  void _retryWrong() {
    final stageWrong = _wrongIds;
    final quizWrong =
        _quizWrongWords.map((w) => w['id'] as int).toList();
    final byId = {
      for (final w in _allQueue) w['id'] as int: w,
      // 抽检错词不在 _allQueue（它们是 mastered 词），单独并入
      for (final w in _quizWrongWords) w['id'] as int: w,
    };
    final rows = [
      for (final id in stageWrong)
        if (byId[id] != null) byId[id]!,
      for (final id in quizWrong)
        if (!stageWrong.contains(id) && byId[id] != null) byId[id]!,
    ];
    if (rows.isEmpty) return;
    setState(() {
      _allQueue = rows;
      _isRetryMode = true;
      _stage = _Stage.enToZh;
    });
    _clearTempSave();
    _startGroup(0);
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

  Widget _buildDone() {
    final theme = Theme.of(context);
    // v2.1.5：分组后统计整轮（全部组）
    final total = _allQueue.length;
    // v2.1.6：错词数 = 三环节错词 + 熟练词抽检错词
    final wrongCount = _wrongIds.length + _quizWrongWords.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isRetryMode ? '错题加练完成' : '复习完成'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      // v2.1.5：结果页同样可滚动，避免小屏溢出
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
                      wrongCount == 0
                          ? Icons.check_circle_outline
                          : Icons.school_outlined,
                      size: 72,
                      color: wrongCount == 0
                          ? AppColors.ratingGood
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isRetryMode ? '错题加练完成' : '今日复习全部完成',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (wrongCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '本轮有 $wrongCount 个词答错过',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _resultRow(
                        theme, '英译汉', '$_enToZhCorrect / $_enToZhAnsweredCount',
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
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('完成'),
                        ),
                      ),
                    ] else
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
