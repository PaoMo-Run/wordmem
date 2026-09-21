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
  /// 出题顺序 = **时间权重 0.5 的混合打分**（v2.1.7）：
  /// 一半倾向「最新添加的词」（保留 v2.1.6 针对拖延积压的设计意图），
  /// 一半纯随机（恢复 v2.1.5 的随机出题体验）。
  ///
  /// 历史：v2.1.5 是「到期词按 due + 新词随机打乱」；v2.1.6 为了让拖延积压时优先
  /// 复习最新添加的词，整条改成 `created_at DESC` 硬排序，**顺带把随机化全删了**，
  /// 用户实际看到的就是「永远按添加顺序出题」。本版把两者合并成软权重：
  /// 时间倾向保留一半振幅，随机恢复一半。
  ///
  /// SQL 层仍按 `created_at DESC` 取数：`limit` 截断时保留的仍是最新的一批，
  /// 随机化只作用于已取回这批词的**顺序**。
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
    // 添加越晚越优先（保留 v2.1.6 的意图），但只占一半权重
    return blendByTimeWeight(
      rows,
      timeOf: (r) => epochMillisOf(r['created_at']),
      ascending: false,
    );
  }

  /// 待处理词数（新词 + 待复习，与复习队列同口径）
  ///
  /// v2.1.7：改走 [WordDao.countPendingQueue]。原实现是裸的 `due <= now`，
  /// **把已掌握词也算了进来**——已掌握词的 due 语义是「下次可抽检时间」，
  /// 于是通知文案会出现「你有 N 个单词待复习」而复习队列是空的
  /// （2026-09-17 真机反馈：自愈把 52 个已掌握词的 due 拉到当前后凭空多出 52）。
  int get pendingCount => _wordDao.countPendingQueue();

  /// 提交一轮测验（事务操作）。
  ///
  /// v2.1.8：排期已与评分**解耦**（固定走满 T0–T7 八个节点，取消跳过），
  /// 因此入参改为**测验得分**：
  /// - [score]：0–6 分（三环节 × 2 分的扣分制，见 `AppConstants.quizMaxScore`）
  /// - [timeouts]：本轮超时的环节数 0–3
  ///
  /// 写库时把得分档位映射回旧的 `rating` 列，让沿用旧字段的统计
  /// （如「今日忘记的词」= rating again）继续可用。
  void submitReview(int userWordId, {required int score, int timeouts = 0}) {
    final band = ScoreBand.of(score);
    _db.transaction(() {
      // 1. 读取当前卡片状态
      final word = _wordDao.getById(userWordId);
      if (word == null) throw Exception('单词不存在');

      // 2. 构建 FSRS 卡片
      final card = FsrsCard.fromDbMap(word);

      // 3. 计算新状态
      final now = DateTime.now().toUtc();
      final result = _fsrs.review(card, band.rating, now);
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

      // 5. 插入复习记录（含得分与超时数，供「单词详情 → 复习历史」展示）
      _reviewDao.insert(
        userWordId: userWordId,
        rating: band.rating.value,
        state: card.state.value,
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
        reviewedAt: now.toIso8601String(),
        score: score,
        timeouts: timeouts,
      );
    });
  }

  /// 熟练词抽检结果写历史（v2.1.8，`kind = quiz`）。
  ///
  /// 此前抽检**完全不写历史**，用户在单词详情页看不到任何抽查记录；
  /// 现在统一入 `review_logs`，详情页按 `kind` 显示「抽查正确 / 抽查失败」。
  /// 答错用 `again` 记账 —— 它确实属于「今日忘记的词」，应被 AI 上下文捞到。
  void logMasteredQuiz(int userWordId, {required bool correct}) {
    _reviewDao.insert(
      userWordId: userWordId,
      rating: correct ? ReviewRating.good.value : ReviewRating.again.value,
      state: CardState.mastered.value,
      reviewedAt: DateTime.now().toUtc().toIso8601String(),
      kind: ReviewKind.quiz,
    );
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

  /// ISO 时间字符串 → epoch 毫秒（纯函数，便于单测）。
  /// 缺失或不可解析的值排到最后（[double.maxFinite]），
  /// 免得脏数据把某个词顶到队首。
  static double epochMillisOf(Object? iso) {
    final t = DateTime.tryParse((iso as String?) ?? '');
    return t?.millisecondsSinceEpoch.toDouble() ?? double.maxFinite;
  }

  /// **时间权重混合打分排序**（纯函数，便于单测）。
  ///
  /// 每个词得分 = `w × 时间名次 + (1 − w) × 随机数`，按得分升序返回。
  /// - 时间名次：把 [timeOf] 排好序后归一化到 `[0, 1]`，`0` = 最优先
  /// - [ascending]：`true` = timeOf 越小越优先；`false` = 越大越优先
  ///   （如「添加越晚越优先」传 false，**不要靠给 timeOf 取负**，见下）
  /// - `w = 1.0` → 完全按时间（= v2.1.6 的行为，等价于原先的硬排序）
  /// - `w = 0.0` → 完全随机
  /// - `w = 0.5` → 时间倾向与随机**振幅相等**（当前取值）
  ///
  /// 不可解析的时间（按约定用 [double.maxFinite] 表达）**一律排到最后，
  /// 且与 [ascending] 无关**：取负会把 maxFinite 变成 -maxFinite（最优先），
  /// 脏数据反而被顶到队首。
  ///
  /// 为什么用软权重而不是「硬窗口内随机」：硬窗口（只从最优先的前 N 个里抽）
  /// 会让窗口外的词永远排不上队——数学上就等价于时间权重 1.0，正是 v2.1.6
  /// 抽检退化成"永远同一批"的另一半原因。软权重下时间早的词只是**更容易**
  /// 排在前面，靠后的词仍有机会；而一旦某个词被抽中，它的 timeOf 被推后就会
  /// 自然沉到队尾，池子始终在轮换（不会被漏掉）。
  static List<Map<String, dynamic>> blendByTimeWeight(
    List<Map<String, dynamic>> rows, {
    required double Function(Map<String, dynamic>) timeOf,
    double timeWeight = AppConstants.orderTimeWeight,
    bool ascending = true,
    Random? random,
  }) {
    if (rows.length <= 1) return [...rows];

    final valid = <Map<String, dynamic>>[];
    final invalid = <Map<String, dynamic>>[];
    for (final r in rows) {
      (timeOf(r) >= double.maxFinite ? invalid : valid).add(r);
    }
    final byTime = [...valid]..sort((a, b) {
        final c = timeOf(a).compareTo(timeOf(b));
        return ascending ? c : -c;
      });
    final ordered = [...byTime, ...invalid];

    if (timeWeight >= 1.0) return ordered;

    final rnd = random ?? Random();
    final n = ordered.length;
    final scored = <(Map<String, dynamic>, double)>[
      for (var i = 0; i < n; i++)
        (
          ordered[i],
          timeWeight * (i / (n - 1)) + (1 - timeWeight) * rnd.nextDouble(),
        ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in scored) e.$1];
  }

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

  /// 该候选词是否已过冷却期（纯函数，便于单测）。
  ///
  /// **这是抽检公平性的唯一基石**：被抽中的词会把 due 推后（答对 15 天 /
  /// 答错 3 天 / 跳过 7 天）。一旦放行冷却期内的词，池子小的用户就会每一轮
  /// 都抽到同一批——v2.1.7 修的就是这条不变量被 fallback 打破。
  static bool isQuizReady(Map<String, dynamic> word, {required DateTime now}) {
    final due = DateTime.tryParse((word['due'] as String?) ?? '');
    if (due == null) return false;
    return !due.isAfter(now.toUtc());
  }

  /// 只保留冷却期已过的词（纯函数，便于单测）
  static List<Map<String, dynamic>> filterQuizReady(
    List<Map<String, dynamic>> words, {
    required DateTime now,
  }) =>
      words.where((w) => isQuizReady(w, now: now)).toList();

  /// 抽取待抽检的已掌握词。
  ///
  /// v2.1.7 起改用**时间权重 0.5 的混合打分**（时间 = due 最早优先），
  /// 取代 v2.1.6 的「硬窗口（5×3）+ 窗口内纯随机」：
  /// - 硬窗口让窗口外的词永远排不上队，池子一大就等于把时间权重钉在 1.0
  /// - 软权重下时间最早的一批**更容易**被抽到，靠后的词也仍有机会
  ///
  /// 候选**只含冷却期已过**的词（DAO 的 SQL 已保证），这里再用
  /// [filterQuizReady] 兜一层——任何未来改动放宽 SQL 条件都不会让同一批词
  /// 反复出现。冷却期内无词可用时返回空，本次不抽检（调用方已有空值兜底）。
  List<Map<String, dynamic>> pickMasteredQuizWords({
    int count = AppConstants.masteredQuizCount,
  }) {
    final candidates = filterQuizReady(
      _wordDao.pickMasteredQuizCandidates(),
      now: DateTime.now(),
    );
    if (candidates.isEmpty || count <= 0) return const [];
    final ranked = blendByTimeWeight(
      candidates,
      timeOf: (r) => epochMillisOf(r['due']),
    );
    return ranked.take(count).toList();
  }

  /// 抽检答对后的冷却间隔（纯函数，便于单测）。
  ///
  /// 池子 ≥ 单次抽检量时用 15 天；**池子不足时缩短到 7 天**（v2.1.7 用户定值）——
  /// 已掌握词 < 5 个时一轮抽检就覆盖全池，再用 15 天会让抽检断档半个月。
  static Duration cooldownAfterCorrect({required int masteredPoolSize}) =>
      masteredPoolSize >= AppConstants.masteredQuizCount
          ? const Duration(days: AppConstants.masteredQuizCorrectDays)
          : AppConstants.masteredQuizShortCooldown;

  /// 提交单条抽检结果（逐词提交，中途退出也不丢已完成的部分）。
  ///
  /// - **答对**：失败计数清零（洗白），due 推后 15 天（池子不足 5 个时缩短为 7 天）
  /// - **答错（第 1 次）**：保留 mastered，失败计数 = 1，due 推后 3 天尽快复检
  /// - **答错（第 2 次）**：判定确实遗忘 → 退回 T3 重走周期
  void submitMasteredQuiz(int userWordId, {required bool correct}) {
    final now = DateTime.now().toUtc();
    // v2.1.8：抽检结果写进复习历史（kind = quiz），详情页显示为「抽查正确/失败」
    logMasteredQuiz(userWordId, correct: correct);
    if (correct) {
      // v2.1.7：冷却期按池子大小自适应 —— 池子不足单次抽检量时缩到 7 天，
      // 否则池子小的用户一轮抽完就要干等 15 天，抽检形同消失
      _wordDao.updateMasteredQuizState(
        userWordId,
        due: now
            .add(cooldownAfterCorrect(
                masteredPoolSize: _wordDao.countMastered()))
            .toIso8601String(),
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
