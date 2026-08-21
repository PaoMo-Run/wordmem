// 短文记忆测试 - 领域模型

/// 测试模式（三档难度）
enum StoryQuizMode {
  /// 复习：仅重点词挖空，4 选 1
  review('复习', '仅重点词挖空，点击空格选择'),
  /// 巩固：仅重点词挖空，手动输入
  consolidate('巩固', '重点词挖空，手动填写单词'),
  /// 拓展：所有实词挖空，手动默写
  extend('拓展', '所有实词挖空，完整默写');

  final String label;
  final String desc;
  const StoryQuizMode(this.label, this.desc);

  static StoryQuizMode fromName(String? name) {
    return switch (name) {
      'consolidate' => StoryQuizMode.consolidate,
      'extend' => StoryQuizMode.extend,
      _ => StoryQuizMode.review,
    };
  }
}

/// 一道挖空题（一个空格）
class QuizBlank {
  final String word; // 正确答案（原文形态）
  final String sentence; // 所在句子（供上下文展示/出处）
  final List<String> options; // 复习模式 4 选 1 选项（空表示非选择题）

  const QuizBlank({
    required this.word,
    required this.sentence,
    this.options = const [],
  });
}

/// 一次测试的错题明细
class WrongBlank {
  final String word;
  final String userAnswer;
  final String correctAnswer;

  const WrongBlank({
    required this.word,
    required this.userAnswer,
    required this.correctAnswer,
  });
}

/// 一次测试记录（持久化）
class StoryQuizRecord {
  final int? id;
  final int storyId;
  final StoryQuizMode mode;
  final int total;
  final int correct;
  final List<WrongBlank> wrongBlanks;
  final DateTime createdAt;

  const StoryQuizRecord({
    this.id,
    required this.storyId,
    required this.mode,
    required this.total,
    required this.correct,
    this.wrongBlanks = const [],
    required this.createdAt,
  });

  factory StoryQuizRecord.fromMap(Map<String, dynamic> m) {
    final wrongStr = (m['wrong_blanks'] as String?) ?? '';
    final wrongBlanks = wrongStr.isEmpty
        ? <WrongBlank>[]
        : wrongStr.split(';').where((s) => s.isNotEmpty).map((s) {
            final parts = s.split(':');
            return WrongBlank(
              word: parts.isNotEmpty ? parts[0] : '',
              userAnswer: parts.length > 1 ? parts[1] : '',
              correctAnswer: parts.length > 2 ? parts[2] : '',
            );
          }).toList();
    return StoryQuizRecord(
      id: m['id'] as int,
      storyId: m['story_id'] as int,
      mode: StoryQuizMode.fromName(m['mode'] as String?),
      total: m['total'] as int,
      correct: m['correct'] as int,
      wrongBlanks: wrongBlanks,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
