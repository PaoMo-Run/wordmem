/// 近义词选择题
class SynonymQuiz {
  /// 题目单词
  final String word;

  /// 正确近义词
  final String correct;

  /// 四个选项（已打乱，含正确项）
  final List<String> options;

  SynonymQuiz({
    required this.word,
    required this.correct,
    required this.options,
  });

  /// 正确选项在 options 中的索引
  int get correctIndex => options.indexOf(correct);
}
