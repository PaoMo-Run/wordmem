import 'dart:math';

import '../database/app_database.dart';
import '../database/word_dao.dart';
import '../database/review_dao.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/review_rating.dart';
import '../../domain/services/fsrs_service.dart';

/// 复习仓库 - FSRS 排程 + 事务写入
class ReviewRepository {
  final AppDatabase _db;
  final WordDao _wordDao;
  final ReviewDao _reviewDao;
  final FsrsService _fsrs;

  ReviewRepository(this._db, this._wordDao, this._reviewDao, this._fsrs);

  /// 获取待复习列表（新词 + 到期词）。
  ///
  /// v2.1.6：**按添加时间由近到远**排序 —— 用户拖延导致一轮待复习词过多时，
  /// 优先复习最新添加学习的词（记忆最浅、最需要及时巩固），更早的词随后。
  ///
  /// SQL 层也用同一排序取数，保证 `limit` 截断时保留的是最新的一批。
  List<Map<String, dynamic>> getReviewQueue({int limit = 100}) {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = <Map<String, dynamic>>[
      // 到期词（非新词）
      ..._db.vocab
          .select(
            '''SELECT * FROM user_words
           WHERE due <= ? AND card_state NOT IN ('new', 'mastered')
           ORDER BY created_at DESC LIMIT ?''',
            [now, limit],
          )
          .map((r) => r as Map<String, dynamic>),
      // 新词（立即可学）
      ..._db.vocab
          .select(
            """SELECT * FROM user_words
           WHERE card_state = 'new' AND due <= ?
           ORDER BY created_at DESC LIMIT ?""",
            [now, limit],
          )
          .map((r) => r as Map<String, dynamic>),
    ];
    rows.sort(
      (a, b) => ((b['created_at'] as String?) ?? '')
          .compareTo((a['created_at'] as String?) ?? ''),
    );
    return rows;
  }

  /// 待复习数量
  int get pendingCount {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = _db.vocab.select(
      'SELECT COUNT(*) as c FROM user_words WHERE due <= ?',
      [now],
    ).first;
    return row['c'] as int;
  }

  /// 提交评分（事务操作）
  void submitReview(int userWordId, ReviewRating rating) {
    _db.transaction(() {
      // 1. 读取当前卡片状态
      final word = _wordDao.getById(userWordId);
      if (word == null) throw Exception('单词不存在');

      // 2. 构建 FSRS 卡片
      final card = FsrsCard.fromDbMap(word);

      // 3. 计算新状态
      final now = DateTime.now().toUtc();
      final result = _fsrs.review(card, rating, now);
      final newCard = result.card;

      // 4. 更新 user_words 卡片状态
      _wordDao.updateCardState(
        userWordId,
        cardState: newCard.state.value,
        stability: newCard.stability,
        difficulty: newCard.difficulty,
        reps: newCard.reps,
        lapses: newCard.lapses,
        due: newCard.due!.toIso8601String(),
        lastReview: now.toIso8601String(),
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
      );

      // 5. 插入复习记录
      _reviewDao.insert(
        userWordId: userWordId,
        rating: rating.value,
        state: card.state.value,
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
        reviewedAt: now.toIso8601String(),
      );
    });
  }

  /// 获取单词复习历史
  List<Map<String, dynamic>> getReviewHistory(int wordId) {
    return _reviewDao.getHistory(wordId);
  }

  /// 降级单词熟悉度（翻卡主观"很轻松"但后续选单词/默写出错时调用）。
  /// 用 again 评分重新排程（回退间隔 + 遗忘次数 +1），但不写复习历史，
  /// 避免与正式评分记录混淆。
  void demoteWord(int userWordId) {
    _db.transaction(() {
      final word = _wordDao.getById(userWordId);
      if (word == null) return;
      final card = FsrsCard.fromDbMap(word);
      final now = DateTime.now().toUtc();
      final result = _fsrs.review(card, ReviewRating.again, now);
      final newCard = result.card;
      _wordDao.updateCardState(
        userWordId,
        cardState: newCard.state.value,
        stability: newCard.stability,
        difficulty: newCard.difficulty,
        reps: newCard.reps,
        lapses: newCard.lapses,
        due: newCard.due!.toIso8601String(),
        lastReview: now.toIso8601String(),
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
      );
    });
  }

  // ═════════════════════ 熟练词抽检（v2.1.6） ═════════════════════

  /// 从候选中随机抽取 [count] 个（纯函数，便于单测）。
  ///
  /// 只负责「随机 + 去重」；**公平性由候选的排序保证**——调用方先按
  /// 「最久未抽」升序截取窗口，随机只发生在窗口内，因此不会有词被跳过。
  static List<Map<String, dynamic>> pickRandom(
    List<Map<String, dynamic>> candidates, {
    required int count,
    Random? random,
  }) {
    if (candidates.isEmpty || count <= 0) return const [];
    final pool = [...candidates]..shuffle(random);
    return pool.take(count).toList();
  }

  /// 抽检通过后的下次可抽检时间
  static DateTime dueAfterCorrect(DateTime now) =>
      now.add(const Duration(days: AppConstants.masteredQuizCorrectDays));

  /// 抽检答错（第 1 次）后的复检时间
  static DateTime dueAfterWrong(DateTime now) =>
      now.add(AppConstants.masteredQuizWrongDelay);

  /// 用户跳过后重新进入候选池的时间
  static DateTime dueAfterSkip(DateTime now) =>
      now.add(AppConstants.masteredQuizSkipDelay);

  /// 抽检答错的处置判定（纯函数，便于单测）：
  /// - 此前未错过（0）→ 只标记一次，进入 3 天复检窗口
  /// - 此前已错过一次（≥1）→ 判定确实遗忘，降级退回 T3
  static bool shouldDemoteOnQuizWrong(double prevFailCount) =>
      prevFailCount >= 1;

  /// 抽取待抽检的已掌握词（窗口随机）。
  ///
  /// 先取「最久未抽」的前 (count × 窗口倍数) 个作为候选窗口，再在其中随机取 count 个：
  /// - 窗口内随机 → 不会退化成机械轮询
  /// - 固定从最久未抽的头部取窗口 → 每个词都会被轮到，不会被漏掉
  /// - shuffle().take(count) → 同轮内天然不重复
  List<Map<String, dynamic>> pickMasteredQuizWords({
    int count = AppConstants.masteredQuizCount,
  }) {
    final window = count * AppConstants.masteredQuizWindowFactor;
    final candidates = _wordDao.pickMasteredQuizCandidates(
      windowSize: window,
      fallbackLimit: count,
    );
    return pickRandom(candidates, count: count);
  }

  /// 提交单条抽检结果（逐词提交，中途退出也不丢已完成的部分）。
  ///
  /// - **答对**：失败计数清零（洗白），due 推后 15 天
  /// - **答错（第 1 次）**：保留 mastered，失败计数 = 1，due 推后 3 天尽快复检
  /// - **答错（第 2 次）**：判定确实遗忘 → 退回 T3 重走周期
  void submitMasteredQuiz(int userWordId, {required bool correct}) {
    final now = DateTime.now().toUtc();
    if (correct) {
      _wordDao.updateMasteredQuizState(
        userWordId,
        due: dueAfterCorrect(now).toIso8601String(),
        difficulty: 0,
      );
      return;
    }

    final word = _wordDao.getById(userWordId);
    final prevFails = (word?['difficulty'] as num?)?.toDouble() ?? 0;
    if (shouldDemoteOnQuizWrong(prevFails)) {
      // 第 2 次失败：移出 mastered，从 T3 重新走周期
      demoteMasteredToT3(userWordId);
      return;
    }

    _wordDao.updateMasteredQuizState(
      userWordId,
      due: dueAfterWrong(now).toIso8601String(),
      difficulty: 1,
    );
  }

  /// 重测环节**答对**、但此前抽检已错过一次：**不清零失败标记**（不洗白），
  /// 只把复检窗口推到 3 天后——若复检再错，[submitMasteredQuiz] 会触发降级。
  ///
  /// 设计意图：抽检错过一次的词要经过「3 天复检」这道关卡才算真正过关，
  /// 重测里答对只算"暂缓"，避免用一次侥幸抹掉遗忘信号。
  void holdMasteredQuizWrongMark(int userWordId) {
    final now = DateTime.now().toUtc();
    _wordDao.updateMasteredQuizState(
      userWordId,
      due: dueAfterWrong(now).toIso8601String(),
      difficulty: 1,
    );
  }

  /// 用户选择「暂不抽检」：仅把 due 推后（记账），卡片状态不变。
  ///
  /// 推后 7 天（短于答对的 15 天），这些词会更快回到候选池——
  /// 既不会被误认为「已测过」而搁置，也不会在同一批里立刻重复出现。
  void skipMasteredQuiz(List<int> userWordIds) {
    if (userWordIds.isEmpty) return;
    final now = DateTime.now().toUtc();
    final due = dueAfterSkip(now).toIso8601String();
    _db.transaction(() {
      for (final id in userWordIds) {
        final word = _wordDao.getById(id);
        if (word == null) continue;
        _wordDao.updateMasteredQuizState(
          id,
          due: due,
          difficulty: (word['difficulty'] as num?)?.toDouble() ?? 0,
        );
      }
    });
  }

  /// 第 2 次抽检失败 → 退回 **T3** 重新走周期（移出 mastered）。
  ///
  /// reps = 3 表示「下次执行 T3 节点」，due 按当前间隔表的第 3 档计算，
  /// 因此未来切换到 T0–T7 的间隔表后会自动适配，无需再改这里。
  void demoteMasteredToT3(int userWordId) {
    _db.transaction(() {
      final word = _wordDao.getById(userWordId);
      if (word == null) return;
      final card = FsrsCard.fromDbMap(word);
      final now = DateTime.now().toUtc();
      const reps = 3;
      final interval = _fsrs.intervalForReps(reps);
      _wordDao.updateCardState(
        userWordId,
        cardState: CardState.review.value,
        stability: interval.inSeconds / 86400.0,
        difficulty: 0,
        reps: reps,
        lapses: card.lapses,
        due: now.add(interval).toIso8601String(),
        lastReview: now.toIso8601String(),
        elapsedDays: card.elapsedDays,
        scheduledDays: 0,
      );
    });
  }
}
