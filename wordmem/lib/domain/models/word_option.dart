/// 选单词选项（含释义，用于四选一展示与提交后核对）
class WordOption {
  final String word;
  final String definition;

  /// 该选项对应个人词库的 user_words.id（v2.2.1 新增）。
  /// null = 干扰项来自内置词典、词库里没有这个词 → 作答后不可跳详情页。
  final int? userWordId;

  const WordOption({
    required this.word,
    required this.definition,
    this.userWordId,
  });
}

/// 复习测验两环节的四选一选项（v2.1.5 统一随机化）
class ReviewStageOptions {
  /// 汉译英（看中文选单词）：选项为单词
  final List<WordOption> wordOptions;

  /// 英译汉（看英文选释义）：选项为释义（word 字段存该释义所属词，供提交后核对）
  final List<WordOption> enToZhOptions;

  /// 该词是否有可用中文释义（无则复习流程跳过英译汉环节）
  final bool enToZhAvailable;

  const ReviewStageOptions({
    required this.wordOptions,
    required this.enToZhOptions,
    required this.enToZhAvailable,
  });
}
