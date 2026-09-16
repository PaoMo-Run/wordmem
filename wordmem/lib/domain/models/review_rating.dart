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

/// 熟练度档位（UI 展示用，v2.1.6：按 T0–T7 节点映射，1~4 递增）
enum MasteryStatus {
  level1('小试牛刀'),
  level2('初出茅庐'),
  level3('炉火纯青'),
  level4('登峰造极');

  final String label;
  const MasteryStatus(this.label);

  /// 由节点进度派生熟练度档位（1~4）。
  ///
  /// - **未跳过路径**：每 2 个节点升 1 档 → `[1,1,2,2,3,3,4,4]`
  /// - **已跳过 T2**（`skipState >= 1`）→ `[1,2,2,3,3,4]`，即 T1 起就升到 2 档。
  ///   若 T3 未全对，调度层会把 `skipState` 撤销为 0（回到上表）。
  ///
  /// `completed` = 已完成的测验次数 = `reps - skipState`。
  static int levelOf({required int reps, required int skipState}) {
    final completed = reps - skipState;
    if (completed <= 0) return 1;
    final table = skipState >= 1
        ? const [1, 2, 2, 3, 3, 4]
        : const [1, 1, 2, 2, 3, 3, 4, 4];
    return table[(completed - 1).clamp(0, table.length - 1)];
  }

  static MasteryStatus fromLevel(int level) => switch (level) {
        1 => MasteryStatus.level1,
        2 => MasteryStatus.level2,
        3 => MasteryStatus.level3,
        _ => MasteryStatus.level4,
      };

  /// 由卡片数据派生（`difficulty` 在未掌握时承载跳过加速态）
  static MasteryStatus fromCardData({
    required int reps,
    double difficulty = 0,
  }) =>
      fromLevel(levelOf(reps: reps, skipState: difficulty.toInt()));
}
