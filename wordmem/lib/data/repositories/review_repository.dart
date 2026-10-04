import 'dart:math';

import '../database/app_database.dart';
import '../database/word_dao.dart';
import '../database/review_dao.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/review_rating.dart';
import '../../domain/services/fsrs_service.dart';
import '../../domain/services/schedule_tuning.dart';

/// 复习仓库 - FSRS 排程 + 事务写入
class ReviewRepository {
  final AppDatabase _db;
  final WordDao _wordDao;
  final ReviewDao _reviewDao;
  final FsrsService _fsrs;
  final ScheduleTuning _tuning;

  /// [tuning] 可选（不传 = 默认档/编译期常量）：生产侧由
  /// `app_providers.dart` 传入 `scheduleTuningProvider` 的当前值；
  /// 测试里全部走静态方法或省略该参数，行为与旧版完全一致。
  ReviewRepository(this._db, this._wordDao, this._reviewDao, this._fsrs,
      [ScheduleTuning? tuning])
      : _tuning = tuning ?? ScheduleTuning.defaults();

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

  /// 「提前背」队列（v2.1.11）：只取**未来 [window] 内到期**的词。
  ///
  /// 场景：用户预知接下来几小时没法复习（要开会、赶车、断网），想把马上要到期的
  /// 词先推一轮。复习结果按**正常流程**提交（推进 T 节点、写复习记录），
  /// 因此之后它们不会再出现在今天的待复习里。
  ///
  /// 与 [getReviewQueue] 的三点差别：
  /// - **不含已到期词**（那些属于正常复习队列，用户可以直接做）；
  /// - **不做时间权重打乱**：提前背的价值就在于"按到期先后一口气推完"，
  ///   谁最快要到期本身就是要传达的信息，打乱反而无从判断；
  /// - 窗口与首页提示共用「提前背窗口」（`ScheduleTuning.upcomingHours`，
  ///   可在学习节奏里调整；未配置时 = 默认 3 小时），
  ///   且 DAO 侧 WHERE 条件与计数查询严格一致（不会"数字对不上"）。
  ///
  /// ⚠️ Dart 语法约束：默认值必须是编译期常量，读配置只能用
  /// 「可空参数 + 体内兜底」，不能写成 `Duration window = <运行时值>`。
  List<Map<String, dynamic>> getUpcomingQueue({
    Duration? window,
    int limit = 100,
  }) {
    final w =
        window ?? Duration(hours: _tuning.upcomingHours);
    return _wordDao.getDueWithin(w, limit: limit);
  }

  /// 提交一轮测验（事务操作）。
  ///
  /// v2.1.8：排期已与评分**解耦**（固定走满 T0–T8 九个节点，取消跳过），
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

  /// 抽检答错后的复检时间（不区分首次，一律 2 天；可注入配置）
  static DateTime dueAfterWrong(DateTime now, {ScheduleTuning? t}) =>
      now.add(Duration(days: (t ?? ScheduleTuning.defaults()).quizWrongDays));

  /// 用户跳过后重新进入候选池的时间
  static DateTime dueAfterSkip(DateTime now, {ScheduleTuning? t}) =>
      now.add(Duration(days: (t ?? ScheduleTuning.defaults()).quizSkipDays));

  /// 抽检答错的处置判定（纯函数，便于单测）：
  /// - 此前未错过（0）→ 只标记一次，进入 2 天复检窗口
  /// - 此前已错过一次（≥1）→ 判定确实遗忘，打回复习列表并从 T5 重新走周期
  static bool shouldDemoteOnQuizWrong(double prevFailCount) =>
      prevFailCount >= 1;

  /// **熟练词抽检的复合抽取权重排序**（纯函数，便于单测；v2.2.0 需求2）。
  ///
  /// 需求：随机抽取引入权重——**添加时间最早、距最近一次复习最久远**的词优先。
  /// 两者是两个独立的时间维度，单维度的 [blendByTimeWeight] 表达不了，
  /// 故为抽检池新增三项线性复合（复习队列继续用单维度 due 混合，互不影响）：
  ///
  ///   score = wDue × rank(due) + wCreated × rank(created_at) + wRandom × 随机数
  ///
  /// - `rank`：该维度升序名次归一化到 `[0,1]`，`0` = 最优先
  ///   （due 最早 = 距上次毕业最久；created_at 最早 = 添加最早）
  /// - ⚠️ 权重取 0.45/0.15/0.40 而非对半：due 随抽中轮换（自愈维度）可担主权重；
  ///   created_at 是永不轮换的固定维度，权重过大（实测 ≥0.2）会让添加较晚的词
  ///   长期低于抽取线、违反「不漏词」不变量（蒙特卡洛验证见常量注释）
  /// - 同分并列共享同一名次；脏时间（[double.maxFinite] 哨兵）该维度一律垫尾
  ///   （rank=1），与 [blendByTimeWeight] 的约定一致
  /// - 不漏词、不重复、不改元素个数；单元素原样返回
  static List<Map<String, dynamic>> blendMasteryQuizWeights(
    List<Map<String, dynamic>> rows, {
    required double Function(Map<String, dynamic>) dueOf,
    required double Function(Map<String, dynamic>) createdAtOf,
    double weightDue = AppConstants.masteryQuizWeightDue,
    double weightCreated = AppConstants.masteryQuizWeightCreated,
    double weightRandom = AppConstants.masteryQuizWeightRandom,
    Random? random,
  }) {
    if (rows.length <= 1) return [...rows];

    double rankOf(List<double> sortedValues, double v) {
      if (v >= double.maxFinite) return 1.0; // 脏数据垫尾
      var i = 0;
      while (i < sortedValues.length && sortedValues[i] < v) {
        i++;
      }
      final n = sortedValues.length;
      return n <= 1 ? 0.0 : i / (n - 1);
    }

    final dueValues = rows.map(dueOf).toList()..sort();
    final createdValues = rows.map(createdAtOf).toList()..sort();
    final rnd = random ?? Random();
    final scored = <(Map<String, dynamic>, double)>[
      for (final r in rows)
        (
          r,
          weightDue * rankOf(dueValues, dueOf(r)) +
              weightCreated * rankOf(createdValues, createdAtOf(r)) +
              weightRandom * rnd.nextDouble(),
        ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in scored) e.$1];
  }

  /// 该候选词是否已过冷却期（纯函数，便于单测）。
  ///
  /// **这是抽检公平性的唯一基石**：被抽中的词会把 due 推后（答对 10 天 /
  /// 答错 2 天 / 跳过 7 天）。一旦放行冷却期内的词，池子小的用户就会每一轮
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
  /// v2.2.0 需求2 起改用**复合抽取权重**（0.45×due 名次 + 0.15×created_at 名次
  /// + 0.40×随机）：添加最早、距最近一次复习最久远的词优先被抽中，同时保留
  /// 足够的随机性避免头部词垄断。v2.1.7 的冷却期不变量原样保留：
  /// 候选**只含冷却期已过**的词（DAO 的 SQL 已保证），这里再用
  /// [filterQuizReady] 兜一层——任何未来改动放宽 SQL 条件都不会让同一批词
  /// 反复出现。冷却期内无词可用时返回空，本次不抽检（调用方已有空值兜底）。
  List<Map<String, dynamic>> pickMasteredQuizWords({int? count}) {
    // 单次抽检量：显式传参优先；否则读当前配置档（未配置 = 默认档）
    final c = count ?? _tuning.quizCount;
    final candidates = filterQuizReady(
      _wordDao.pickMasteredQuizCandidates(),
      now: DateTime.now(),
    );
    if (candidates.isEmpty || c <= 0) return const [];
    final ranked = blendMasteryQuizWeights(
      candidates,
      dueOf: (r) => epochMillisOf(r['due']),
      createdAtOf: (r) => epochMillisOf(r['created_at']),
    );
    return ranked.take(c).toList();
  }

  /// 抽检答对后的冷却间隔（纯函数，便于单测）。
  ///
  /// 池子 ≥ 单次抽检量时用全额冷却（默认 10 天）；**池子不足时缩短到 7 天**
  /// （v2.1.7 用户定值）——已掌握词不足一轮抽检量时一轮抽检就覆盖全池，
  /// 再用全额冷却会让抽检断档。阈值与冷却值都跟随配置档（与
  /// [ScheduleTuning] 的 quizCount/quizCorrectDays/quizShortCooldownDays 一致），
  /// 不传 [t] = 默认档（编译期常量）。
  static Duration cooldownAfterCorrect(
      {required int masteredPoolSize, ScheduleTuning? t}) {
    final cfg = t ?? ScheduleTuning.defaults();
    return masteredPoolSize >= cfg.quizCount
        ? Duration(days: cfg.quizCorrectDays)
        : Duration(days: cfg.quizShortCooldownDays);
  }

  /// 提交单条抽检结果（逐词提交，中途退出也不丢已完成的部分）。
  ///
  /// - **答对**：失败计数清零（洗白），due 推后 10 天（池子不足 10 个时缩短为 7 天）
  /// - **答错（第 1 次）**：保留 mastered，失败计数 = 1，due 推后 2 天尽快复检
  /// - **答错（第 2 次）**：判定确实遗忘 → 打回复习列表，从 T5 重新走周期
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
                masteredPoolSize: _wordDao.countMastered(),
                t: _tuning))
            .toIso8601String(),
        difficulty: 0,
      );
      return;
    }

    final word = _wordDao.getById(userWordId);
    final prevFails = (word?['difficulty'] as num?)?.toDouble() ?? 0;
    if (shouldDemoteOnQuizWrong(prevFails)) {
      // 第 2 次失败：移出 mastered，打回复习列表从 T5 重新走周期
      demoteMasteredToT5(userWordId);
      return;
    }

    _wordDao.updateMasteredQuizState(
      userWordId,
      due: dueAfterWrong(now, t: _tuning).toIso8601String(),
      difficulty: 1,
    );
  }

  /// 重测环节**答对**、但此前抽检已错过一次：**不清零失败标记**（不洗白），
  /// 只把复检窗口推到 2 天后——若复检再错，[submitMasteredQuiz] 会触发降级。
  ///
  /// 设计意图：抽检错过一次的词要经过「2 天复检」这道关卡才算真正过关，
  /// 重测里答对只算"暂缓"，避免用一次侥幸抹掉遗忘信号。
  void holdMasteredQuizWrongMark(int userWordId) {
    final now = DateTime.now().toUtc();
    _wordDao.updateMasteredQuizState(
      userWordId,
      due: dueAfterWrong(now, t: _tuning).toIso8601String(),
      difficulty: 1,
    );
  }

  /// 用户选择「暂不抽检」：仅把 due 推后（记账），卡片状态不变。
  ///
  /// 推后 7 天（短于答对的 10 天），这些词会更快回到候选池——
  /// 既不会被误认为「已测过」而搁置，也不会在同一批里立刻重复出现。
  void skipMasteredQuiz(List<int> userWordIds) {
    if (userWordIds.isEmpty) return;
    final now = DateTime.now().toUtc();
    final due = dueAfterSkip(now, t: _tuning).toIso8601String();
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

  /// 第 2 次抽检失败 → 打回**复习列表**并从 **T5** 重新走周期（移出 mastered）。
  ///
  /// v2.2.0 参数调整：打回目标由 T4 改为 **T5**（1 天后直接测 T5，跳过 T4 测验）。
  /// reps = 5 表示「下次执行 T5 节点」，due 按间隔表第 5 档（默认 1 天，随配置档
  /// 时间线浮动）计算；`difficulty` 清零 —— 打回即开始全新一轮 FSRS 流程，
  /// 残留的抽检失败计数若不清零，该词下次毕业进抽检池后第一次答错就会被
  /// 立即再次打回。
  void demoteMasteredToT5(int userWordId) {
    _db.transaction(() {
      final word = _wordDao.getById(userWordId);
      if (word == null) return;
      final card = FsrsCard.fromDbMap(word);
      final now = DateTime.now().toUtc();
      const reps = 5;
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

  /// 抽检错词的重测结算（v2.2.0 需求2 阶段①：复习页编排与自选页
  /// **共用同一套数据与规则**，避免两处语义漂移）。
  ///
  /// - 重测通过 → **不洗白**：保留失败标记，复检窗口推后 2 天
  ///   （[holdMasteredQuizWrongMark]；2 天后的复检再错仍会触发打回）
  /// - 重测仍错（id 在 [failedIds] 中）→ 打回 T5（[demoteMasteredToT5]）
  /// - 单条失败不影响其余（与页面侧此前的容错语义一致）
  void settleMasteredQuizRetries(
    List<int> userWordIds, {
    required Set<int> failedIds,
  }) {
    for (final id in userWordIds) {
      try {
        if (failedIds.contains(id)) {
          demoteMasteredToT5(id);
        } else {
          holdMasteredQuizWrongMark(id);
        }
      } catch (_) {
        // 单条失败不影响其余
      }
    }
  }
}
