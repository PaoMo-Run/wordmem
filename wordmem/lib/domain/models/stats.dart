/// 今日统计
///
/// 口径（2026-08-30 修正）：
/// - [dueNew] / [dueReview] 是「此刻到期」这一集合的**互斥切片**，两者之和即 [pendingReviews]；
/// - [newWordsToday] 是「今日新增入库」的词量，与待处理量无关，仅作展示，不计入任务量；
/// - [totalTasks] = 已完成 + 待处理，保证 [progress] 恒在 0..1。
///   （旧口径 `pendingReviews + newWordsToday` 把两个不同语义相加，会让进度超过 100%）
class TodayStats {
  /// 今日新增入库的词量
  final int newWordsToday;
  /// 到期待学的新词（reps = 0）
  final int dueNew;
  /// 到期待复习的熟词（reps > 0 且非 new）
  final int dueReview;
  /// 今日已完成的复习次数
  final int reviewedToday;
  /// 词库总量
  final int totalWords;

  const TodayStats({
    this.newWordsToday = 0,
    this.dueNew = 0,
    this.dueReview = 0,
    this.reviewedToday = 0,
    this.totalWords = 0,
  });

  /// 此刻待处理总数
  int get pendingReviews => dueNew + dueReview;
  /// 今日已完成
  int get completedTasks => reviewedToday;
  /// 今日任务总量（已完成 + 待处理）
  int get totalTasks => completedTasks + pendingReviews;
  /// 完成度，恒在 0..1
  double get progress {
    if (totalTasks == 0) return 0;
    return (completedTasks / totalTasks).clamp(0.0, 1.0).toDouble();
  }
}

/// 每日学习记录
class DailyRecord {
  final DateTime date;
  final int newWords;
  final int reviews;

  const DailyRecord({
    required this.date,
    this.newWords = 0,
    this.reviews = 0,
  });
}

/// 连续学习统计
class StreakStats {
  final int currentStreak;
  final int longestStreak;
  final int totalReviews;
  final int totalWords;
  final double predictedRetention;

  const StreakStats({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalReviews = 0,
    this.totalWords = 0,
    this.predictedRetention = 0.0,
  });
}

/// 掌握状态分布
class StatusDistribution {
  final int newCount;
  final int learningCount;
  final int familiarCount;
  final int masteredCount;

  const StatusDistribution({
    this.newCount = 0,
    this.learningCount = 0,
    this.familiarCount = 0,
    this.masteredCount = 0,
  });

  int get total =>
      newCount + learningCount + familiarCount + masteredCount;
}

/// 备份信息
class BackupInfo {
  final String version;
  final String appVersion;
  final String dictVersion;
  final int dictWordCount;
  final DateTime backupTime;
  final int userWordCount;
  final int reviewLogCount;
  final int streakDays;

  const BackupInfo({
    required this.version,
    required this.appVersion,
    required this.dictVersion,
    required this.dictWordCount,
    required this.backupTime,
    required this.userWordCount,
    required this.reviewLogCount,
    required this.streakDays,
  });

  factory BackupInfo.fromMap(Map<String, dynamic> m) => BackupInfo(
        version: m['version'] as String,
        appVersion: m['app_version'] as String? ?? '1.0.0',
        dictVersion: m['dict_version'] as String,
        dictWordCount: m['dict_word_count'] as int? ?? 0,
        backupTime: DateTime.parse(m['backup_time'] as String),
        userWordCount: m['user_word_count'] as int? ?? 0,
        reviewLogCount: m['review_log_count'] as int? ?? 0,
        streakDays: m['streak_days'] as int? ?? 0,
      );
}

/// 导入结果
class ImportResult {
  final bool success;
  final String? error;
  final int? wordCount;
  final int? reviewCount;
  /// 续写模式下被跳过的重复词数量（覆盖模式为 null）
  final int? skippedCount;

  const ImportResult({
    required this.success,
    this.error,
    this.wordCount,
    this.reviewCount,
    this.skippedCount,
  });
}

/// 文本批量导入结果
class TextImportResult {
  final List<String> matchedWords;
  final List<String> unmatchedWords;
  final int totalExtracted;

  const TextImportResult({
    this.matchedWords = const [],
    this.unmatchedWords = const [],
    this.totalExtracted = 0,
  });
}
