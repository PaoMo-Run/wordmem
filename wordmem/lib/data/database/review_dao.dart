import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';
import '../../domain/models/review_rating.dart';

/// 复习记录 DAO
class ReviewDao {
  final AppDatabase _db;
  ReviewDao(this._db);

  Database get _v => _db.vocab;

  /// 今日复习过的单词（去重，按词排序）——供 AI 学习上下文使用
  List<String> getReviewedWordsToday() {
    final rows = _v.select(
      '''SELECT DISTINCT uw.word FROM review_logs rl
         JOIN user_words uw ON uw.id = rl.user_word_id
         WHERE rl.reviewed_at >= ? AND rl.reviewed_at < ?
         ORDER BY uw.word COLLATE NOCASE''',
      _todayRange(),
    );
    return rows.map((r) => r['word'] as String).toList();
  }

  /// 今日忘记的单词（评分 Again，去重）——供 AI 上下文重点巩固
  List<String> getMissedWordsToday() {
    final rows = _v.select(
      '''SELECT DISTINCT uw.word FROM review_logs rl
         JOIN user_words uw ON uw.id = rl.user_word_id
         WHERE rl.reviewed_at >= ? AND rl.reviewed_at < ? AND rl.rating = ?
         ORDER BY uw.word COLLATE NOCASE''',
      [..._todayRange(), ReviewRating.again.value],
    );
    return rows.map((r) => r['word'] as String).toList();
  }

  /// 今日 UTC 起止区间
  List<String> _todayRange() {
    final now = DateTime.now().toUtc();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));
    return [start.toIso8601String(), end.toIso8601String()];
  }

  /// 插入复习记录
  void insert({
    required int userWordId,
    required int rating,
    required String state,
    double? elapsedDays,
    double? scheduledDays,
    required String reviewedAt,
  }) {
    _v.execute(
      '''INSERT INTO review_logs
         (user_word_id, rating, state, elapsed_days, scheduled_days, reviewed_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [userWordId, rating, state, elapsedDays, scheduledDays, reviewedAt],
    );
  }

  /// 查询单词的复习历史
  List<Map<String, dynamic>> getHistory(int wordId) {
    return _v.select(
      'SELECT * FROM review_logs WHERE user_word_id = ? ORDER BY reviewed_at DESC',
      [wordId],
    );
  }

  /// 今日复习数量
  int countReviewedToday() {
    final now = DateTime.now().toUtc();
    final startOfDay =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final row = _v.select(
      'SELECT COUNT(*) as c FROM review_logs WHERE reviewed_at >= ?',
      [startOfDay],
    ).first;
    return row['c'] as int;
  }

  /// 总复习次数
  int count() {
    return _v.select('SELECT COUNT(*) as c FROM review_logs').first['c'] as int;
  }

  /// 最近 N 天每日复习数量
  List<Map<String, dynamic>> dailyReviewCounts(int days) {
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
        .toIso8601String();
    return _v.select(
      '''SELECT DATE(reviewed_at) as date, COUNT(*) as count
         FROM review_logs
         WHERE reviewed_at >= ?
         GROUP BY DATE(reviewed_at)
         ORDER BY date ASC''',
      [since],
    );
  }

  /// 最近 N 天每日新增单词数量
  List<Map<String, dynamic>> dailyNewWordCounts(int days) {
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
        .toIso8601String();
    return _v.select(
      '''SELECT DATE(created_at) as date, COUNT(*) as count
         FROM user_words
         WHERE created_at >= ?
         GROUP BY DATE(created_at)
         ORDER BY date ASC''',
      [since],
    );
  }

  /// 获取连续学习天数
  int getCurrentStreak() {
    final rows = _v.select(
      '''SELECT DISTINCT DATE(reviewed_at) as d FROM review_logs
         UNION
         SELECT DISTINCT DATE(created_at) as d FROM user_words
         ORDER BY d DESC LIMIT 365''',
    );
    if (rows.isEmpty) return 0;
    final dates = rows.map((r) => r['d'] as String).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    int streak = 0;
    var checkDate = DateTime.now().toUtc();
    // 如果今天没学习，从昨天开始算
    final todayStr =
        '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
    if (!dates.contains(todayStr)) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    for (var i = 0; i < 365; i++) {
      final d = checkDate.subtract(Duration(days: i));
      final dStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (dates.contains(dStr)) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// 获取所有标签
  List<String> getAllTags() {
    final rows = _v.select('SELECT DISTINCT tags FROM user_words WHERE tags != ""');
    final tags = <String>{};
    for (final row in rows) {
      final t = row['tags'] as String;
      t.split(',').forEach((tag) {
        final trimmed = tag.trim();
        if (trimmed.isNotEmpty) tags.add(trimmed);
      });
    }
    return tags.toList()..sort();
  }
}
