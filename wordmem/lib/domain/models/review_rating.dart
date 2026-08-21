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

/// 掌握状态（UI 展示用，由 card_state + reps 推导）
enum MasteryStatus {
  newWord('新词'),
  learning('学习中'),
  familiar('熟悉'),
  mastered('已掌握');

  final String label;
  const MasteryStatus(this.label);

  static MasteryStatus fromCardData({
    required String cardState,
    required int reps,
    required int lapses,
  }) {
    final state = CardState.fromString(cardState);
    if (state == CardState.mastered) return MasteryStatus.mastered;
    if (state == CardState.newCard && reps == 0) return MasteryStatus.newWord;
    if (state == CardState.learning || state == CardState.relearning) {
      return MasteryStatus.learning;
    }
    // 7 周期方案：review 状态的词尚未完成全部周期，归为熟悉
    return MasteryStatus.familiar;
  }
}
