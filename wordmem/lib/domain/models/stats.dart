/// 统计数据模型
class TodayStats {
  final int newWordsToday;
  final int pendingReviews;
  final int reviewedToday;
  final int totalWords;

  const TodayStats({
    this.newWordsToday = 0,
    this.pendingReviews = 0,
    this.reviewedToday = 0,
    this.totalWords = 0,
  });

  int get totalTasks => pendingReviews + newWordsToday;
  int get completedTasks => reviewedToday;
  double get progress => totalTasks == 0 ? 0 : completedTasks / totalTasks;
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
