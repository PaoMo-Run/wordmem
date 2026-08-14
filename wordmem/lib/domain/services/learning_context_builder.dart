import '../../data/database/review_dao.dart';
import '../../data/database/stats_dao.dart';
import '../../data/database/word_dao.dart';

/// 每日学习上下文——把用户当天的学习情况整理成 AI 可消费的结构化数据。
///
/// 供未来功能注入 prompt 使用：
/// - 「今日短文」：告诉 AI 今天学了哪些词，生成含这些词的短文
/// - 「AI 陪练」：让 AI 知道用户的薄弱词（今日忘记的）与掌握分布
class DailyLearningContext {
  final DateTime date;
  final List<String> newWords;
  final List<String> reviewedWords;
  final List<String> missedWords;
  final int totalWords;
  final int currentStreak;
  final int newCount;
  final int learningCount;
  final int familiarCount;
  final int masteredCount;

  const DailyLearningContext({
    required this.date,
    this.newWords = const [],
    this.reviewedWords = const [],
    this.missedWords = const [],
    this.totalWords = 0,
    this.currentStreak = 0,
    this.newCount = 0,
    this.learningCount = 0,
    this.familiarCount = 0,
    this.masteredCount = 0,
  });

  /// 今日没有任何学习活动
  bool get isEmpty => newWords.isEmpty && reviewedWords.isEmpty;

  /// 今日接触过的全部单词（新增 ∪ 复习，去重保序）
  List<String> get allWordsToday {
    final seen = <String>{};
    return [...reviewedWords, ...newWords].where(seen.add).toList();
  }

  /// 转为注入 AI prompt 的文本片段（中英混合，AI 友好）
  String toPromptText() {
    final buf = StringBuffer();
    buf.writeln('【用户今日学习数据】');
    buf.writeln(
        '日期: ${date.year}-${_p2(date.month)}-${_p2(date.day)}');
    buf.writeln('今日新增单词(${newWords.length}): ${newWords.join(', ')}');
    buf.writeln('今日复习单词(${reviewedWords.length}): ${reviewedWords.join(', ')}');
    if (missedWords.isNotEmpty) {
      buf.writeln('今日没记住的单词(请重点使用): ${missedWords.join(', ')}');
    }
    buf.writeln('词库总量: $totalWords 词；连续学习: $currentStreak 天');
    buf.writeln('掌握分布: 新词 $newCount / 学习中 $learningCount / 熟悉 $familiarCount / 已掌握 $masteredCount');
    return buf.toString();
  }

  /// 结构化 JSON（未来 AI 陪练等可传结构化上下文）
  Map<String, dynamic> toJson() => {
        'date': '${date.year}-${_p2(date.month)}-${_p2(date.day)}',
        'new_words': newWords,
        'reviewed_words': reviewedWords,
        'missed_words': missedWords,
        'total_words': totalWords,
        'current_streak': currentStreak,
        'status_distribution': {
          'new': newCount,
          'learning': learningCount,
          'familiar': familiarCount,
          'mastered': masteredCount,
        },
      };

  static String _p2(int v) => v.toString().padLeft(2, '0');
}

/// 学习上下文构建器：从 DAO 汇总当日数据。
class LearningContextBuilder {
  final WordDao wordDao;
  final ReviewDao reviewDao;
  final StatsDao statsDao;

  LearningContextBuilder({
    required this.wordDao,
    required this.reviewDao,
    required this.statsDao,
  });

  /// 构建今日上下文
  DailyLearningContext buildToday() => buildFor(DateTime.now());

  /// 构建指定日期的上下文
  DailyLearningContext buildFor(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final newRows = wordDao.getWordsAddedBetween(start, end);
    final dist = statsDao.getStatusDistribution();
    final streak = reviewDao.getCurrentStreak();

    return DailyLearningContext(
      date: day,
      newWords: newRows.map((r) => r['word'] as String).toList(),
      reviewedWords: reviewDao.getReviewedWordsToday(),
      missedWords: reviewDao.getMissedWordsToday(),
      totalWords: wordDao.count(),
      currentStreak: streak,
      newCount: dist.newCount,
      learningCount: dist.learningCount,
      familiarCount: dist.familiarCount,
      masteredCount: dist.masteredCount,
    );
  }
}
