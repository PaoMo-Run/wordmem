/// 近义词挑战题
class SynonymChallenge {
  /// 中文释义提示
  final String definition;

  /// 正确答案（近义词，含种子词，2~4 个）
  final List<String> correct;

  /// 8 个选项（含正确答案，已打乱）
  final List<String> options;

  SynonymChallenge({
    required this.definition,
    required this.correct,
    required this.options,
  });
}
