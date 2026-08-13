import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';
import '../../domain/models/stats.dart';

/// 统计 DAO
class StatsDao {
  final AppDatabase _db;
  StatsDao(this._db);

  Database get _v => _db.vocab;

  /// 今日统计
  TodayStats getTodayStats() {
    final now = DateTime.now().toUtc();
    final startOfDay =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

    final newToday = _v.select(
      'SELECT COUNT(*) as c FROM user_words WHERE created_at >= ?',
      [startOfDay],
    ).first['c'] as int;

    final pending = _v.select(
      'SELECT COUNT(*) as c FROM user_words WHERE due <= ? AND reps = 0',
      [now.toIso8601String()],
    ).first['c'] as int;

    final pendingReview = _v.select(
      'SELECT COUNT(*) as c FROM user_words WHERE due <= ? AND reps > 0 AND card_state != ?',
      [now.toIso8601String(), 'new'],
    ).first['c'] as int;

    final reviewedToday = _v.select(
      'SELECT COUNT(*) as c FROM review_logs WHERE reviewed_at >= ?',
      [startOfDay],
    ).first['c'] as int;

    final total = _v.select('SELECT COUNT(*) as c FROM user_words').first['c'] as int;

    return TodayStats(
      newWordsToday: newToday,
      pendingReviews: pending + pendingReview,
      reviewedToday: reviewedToday,
      totalWords: total,
    );
  }

  /// 连续学习统计
  StreakStats getStreakStats() {
    final streak = _getCurrentStreak();
    final totalReviews =
        _v.select('SELECT COUNT(*) as c FROM review_logs').first['c'] as int;
    final totalWords =
        _v.select('SELECT COUNT(*) as c FROM user_words').first['c'] as int;

    // 预测平均记忆率
    final now = DateTime.now().toUtc();
    final dueWords = _v.select(
      'SELECT stability, last_review, card_state FROM user_words WHERE card_state != ?',
      ['new'],
    );
    double totalR = 0;
    int count = 0;
    for (final row in dueWords) {
      final stability = (row['stability'] as num?)?.toDouble() ?? 0;
      final lastReview = row['last_review'] as String?;
      if (stability > 0 && lastReview != null) {
        final elapsed = now.difference(DateTime.parse(lastReview)).inSeconds / 86400.0;
        final decay = -0.5;
        final factor = _pow(0.9, 1 / decay) - 1;
        final r = _pow(1 + factor * elapsed / stability, decay);
        totalR += r.clamp(0.0, 1.0);
        count++;
      }
    }

    return StreakStats(
      currentStreak: streak,
      longestStreak: streak, // MVP: 只记录当前
      totalReviews: totalReviews,
      totalWords: totalWords,
      predictedRetention: count > 0 ? totalR / count : 0,
    );
  }

  /// 掌握状态分布
  StatusDistribution getStatusDistribution() {
    final newCount = _v.select(
      "SELECT COUNT(*) as c FROM user_words WHERE card_state = 'new' AND reps = 0",
    ).first['c'] as int;

    final learningCount = _v.select(
      "SELECT COUNT(*) as c FROM user_words WHERE card_state IN ('learning', 'relearning')",
    ).first['c'] as int;

    final familiarCount = _v.select(
      "SELECT COUNT(*) as c FROM user_words WHERE card_state = 'review' AND reps < 5",
    ).first['c'] as int;

    final masteredCount = _v.select(
      "SELECT COUNT(*) as c FROM user_words WHERE card_state = 'review' AND reps >= 5 AND lapses = 0",
    ).first['c'] as int;

    return StatusDistribution(
      newCount: newCount,
      learningCount: learningCount,
      familiarCount: familiarCount,
      masteredCount: masteredCount,
    );
  }

  /// 每日学习记录（最近 N 天）
  List<DailyRecord> getDailyRecords(int days) {
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
        .toIso8601String();

    final reviewData = _v.select(
      '''SELECT DATE(reviewed_at) as date, COUNT(*) as count
         FROM review_logs WHERE reviewed_at >= ?
         GROUP BY DATE(reviewed_at)''',
      [since],
    );
    final newData = _v.select(
      '''SELECT DATE(created_at) as date, COUNT(*) as count
         FROM user_words WHERE created_at >= ?
         GROUP BY DATE(created_at)''',
      [since],
    );

    final reviewMap = {for (final r in reviewData) r['date'] as String: r['count'] as int};
    final newMap = {for (final r in newData) r['date'] as String: r['count'] as int};

    final allDates = {...reviewMap.keys, ...newMap.keys}.toList()..sort();
    return allDates.map((d) => DailyRecord(
      date: DateTime.parse(d),
      newWords: newMap[d] ?? 0,
      reviews: reviewMap[d] ?? 0,
    )).toList();
  }

  int _getCurrentStreak() {
    final rows = _v.select(
      '''SELECT DISTINCT DATE(reviewed_at) as d FROM review_logs
         UNION SELECT DISTINCT DATE(created_at) as d FROM user_words
         ORDER BY d DESC LIMIT 365''',
    );
    if (rows.isEmpty) return 0;
    final dates = rows.map((r) => r['d'] as String).toSet();

    int streak = 0;
    var checkDate = DateTime.now().toUtc();
    final todayStr = _dateStr(checkDate);
    if (!dates.contains(todayStr)) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }
    for (var i = 0; i < 365; i++) {
      final d = checkDate.subtract(Duration(days: i));
      if (dates.contains(_dateStr(d))) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _pow(double x, double y) {
    if (y == 0) return 1;
    if (x <= 0) return 0;
    return _exp(y * _ln(x));
  }

  double _ln(double x) {
    if (x <= 0) return double.negativeInfinity;
    var sum = 0.0;
    var term = (x - 1) / (x + 1);
    var ts = term * term;
    var denom = 1.0;
    var cur = term;
    for (var i = 0; i < 100; i++) {
      sum += cur / denom;
      cur *= ts;
      denom += 2;
      if (cur / denom < 1e-15) break;
    }
    return 2 * sum;
  }

  double _exp(double x) {
    var sum = 1.0;
    var term = 1.0;
    for (var i = 1; i < 50; i++) {
      term *= x / i;
      sum += term;
      if (term.abs() < 1e-15) break;
    }
    return sum;
  }
}
