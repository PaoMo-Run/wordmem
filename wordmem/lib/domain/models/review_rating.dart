/// 评分枚举 - 对应 FSRS 四档评分
enum ReviewRating {
  /// 没想起来 (Again)
  again(1, '没想起来'),
  /// 想起来但困难 (Hard)
  hard(2, '困难'),
  /// 正确 (Good)
  good(3, '正确'),
  /// 很轻松 (Easy)
  easy(4, '很轻松');

  final int value;
  final String label;
  const ReviewRating(this.value, this.label);

  static ReviewRating fromValue(int v) =>
      ReviewRating.values.firstWhere((e) => e.value == v);
}

/// 卡片状态
enum CardState {
  newCard('new'),
  learning('learning'),
  review('review'),
  relearning('relearning'),
  /// 艾宾浩斯 7 周期全部完成，永久掌握（不再进入复习队列）
  mastered('mastered');

  final String value;
  const CardState(this.value);

  static CardState fromString(String s) =>
      CardState.values.firstWhere((e) => e.value == s,
          orElse: () => CardState.newCard);
}

/// 熟练度档位（UI 展示用，1~4 递增）
///
/// v2.1.8：**取消「熟练跳过」后，本档位只由节点进度决定** ——
/// 不再有 `skipState` 参与（原来跳过档位会让同样 `reps` 直接高一档）。
/// 映射：每 2 个节点升 1 档 → `[1,1,2,2,3,3,4,4]`，
/// `completed` = 已完成的测验次数 = `reps`。
enum MasteryStatus {
  level1('小试牛刀'),
  level2('初出茅庐'),
  level3('炉火纯青'),
  level4('登峰造极');

  final String label;
  const MasteryStatus(this.label);

  /// 由节点进度派生档位（1~4）。
  static int levelOf({required int reps}) {
    if (reps <= 0) return 1;
    const table = [1, 1, 2, 2, 3, 3, 4, 4];
    return table[(reps - 1).clamp(0, table.length - 1)];
  }

  static MasteryStatus fromLevel(int level) => switch (level) {
        1 => MasteryStatus.level1,
        2 => MasteryStatus.level2,
        3 => MasteryStatus.level3,
        _ => MasteryStatus.level4,
      };

  /// 由卡片数据派生
  static MasteryStatus fromCardData({required int reps}) =>
      fromLevel(levelOf(reps: reps));
}

/// 每轮测验得分档（v2.1.8）
///
/// 每轮测验满分 6 分：三环节各 2 分（**答错扣 1 分**、**超时扣 1 分**），
/// 跳过（未作答）按答错计。据此分四档，展示在「单词详情 → 复习历史」里。
///
/// 档位同时给出兼容到旧四档评分的映射（见 [rating]）：`review_logs.rating`
/// 仍在写，让沿用旧字段的统计（如「今日忘记的词」）继续可用。
enum ScoreBand {
  /// 0 分
  unfamiliar('不熟悉'),
  /// 1–2 分
  gettingThere('刚弄懂'),
  /// 3–4 分
  understood('已了解'),
  /// 5–6 分
  clear('很清楚');

  final String label;
  const ScoreBand(this.label);

  static ScoreBand of(int score) {
    if (score <= 0) return ScoreBand.unfamiliar;
    if (score <= 2) return ScoreBand.gettingThere;
    if (score <= 4) return ScoreBand.understood;
    return ScoreBand.clear;
  }

  /// 兼容映射到旧四档评分（`review_logs.rating`）：
  /// 0 → again（"今日忘记"仍能命中）｜1–2 → hard｜3–4 → good｜5–6 → easy
  ReviewRating get rating => switch (this) {
        ScoreBand.unfamiliar => ReviewRating.again,
        ScoreBand.gettingThere => ReviewRating.hard,
        ScoreBand.understood => ReviewRating.good,
        ScoreBand.clear => ReviewRating.easy,
      };
}

/// 复习记录类型（`review_logs.kind`，v2.1.8）
///
/// 熟练词抽检此前**不写任何历史**，用户无法在单词详情页回溯；
/// 现在统一写进 `review_logs`，用 [kind] 区分，详情页据此把抽检行显示为
/// 「抽查正确 / 抽查失败」而不是 0–6 分。
enum ReviewKind {
  /// 常规三环节测验（有 0–6 分）
  review('review'),
  /// 熟练词抽检（只有默写，二元对错）
  quiz('quiz');

  final String value;
  const ReviewKind(this.value);

  static ReviewKind fromString(String? s) => ReviewKind.values.firstWhere(
        (e) => e.value == s,
        orElse: () => ReviewKind.review,
      );
}
