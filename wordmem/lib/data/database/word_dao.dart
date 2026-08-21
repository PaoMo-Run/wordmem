import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';

/// 单词 DAO - user_words 表操作
class WordDao {
  final AppDatabase _db;
  WordDao(this._db);

  Database get _v => _db.vocab;

  /// 新增单词
  int insert({
    required String word,
    int senseId = 0,
    String? customDef,
    String note = '',
    String tags = '',
    bool isFavorite = false,
    String cardState = 'new',
    double stability = 0,
    double difficulty = 0,
    int reps = 0,
    int lapses = 0,
    required String due,
    String? lastReview,
    double elapsedDays = 0,
    double scheduledDays = 0,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    _v.execute(
      '''INSERT INTO user_words
         (word, sense_id, custom_def, note, tags, is_favorite,
          created_at, updated_at, card_state, stability, difficulty,
          reps, lapses, due, last_review, elapsed_days, scheduled_days)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [word, senseId, customDef, note, tags, isFavorite ? 1 : 0,
       now, now, cardState, stability, difficulty,
       reps, lapses, due, lastReview, elapsedDays, scheduledDays],
    );
    // 获取刚插入的 id
    final row = _v.select('SELECT last_insert_rowid() as id').first;
    return row['id'] as int;
  }

  /// 根据 ID 查询单词
  Map<String, dynamic>? getById(int id) {
    final rows = _v.select('SELECT * FROM user_words WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// 根据单词文本查询
  Map<String, dynamic>? getByWord(String word) {
    final rows =
        _v.select('SELECT * FROM user_words WHERE word = ? COLLATE NOCASE', [word]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// 检查单词是否已存在
  bool exists(String word) {
    final row = _v.select(
      'SELECT COUNT(*) as c FROM user_words WHERE word = ? COLLATE NOCASE',
      [word],
    ).first;
    return (row['c'] as int) > 0;
  }

  /// 更新单词信息（自定义释义、备注、标签等）
  void update(int id, {
    String? customDef,
    String? note,
    String? tags,
    bool? isFavorite,
    int? senseId,
  }) {
    final sets = <String>[];
    final args = <Object?>[];
    if (customDef != null) { sets.add('custom_def = ?'); args.add(customDef); }
    if (note != null) { sets.add('note = ?'); args.add(note); }
    if (tags != null) { sets.add('tags = ?'); args.add(tags); }
    if (isFavorite != null) { sets.add('is_favorite = ?'); args.add(isFavorite ? 1 : 0); }
    if (senseId != null) { sets.add('sense_id = ?'); args.add(senseId); }
    if (sets.isEmpty) return;
    sets.add('updated_at = ?');
    args.add(DateTime.now().toUtc().toIso8601String());
    args.add(id);
    _v.execute('UPDATE user_words SET ${sets.join(', ')} WHERE id = ?', args);
  }

  /// 更新卡片状态（FSRS 评分后）
  void updateCardState(int id, {
    required String cardState,
    required double stability,
    required double difficulty,
    required int reps,
    required int lapses,
    required String due,
    required String lastReview,
    required double elapsedDays,
    required double scheduledDays,
  }) {
    _v.execute(
      '''UPDATE user_words SET
         card_state = ?, stability = ?, difficulty = ?,
         reps = ?, lapses = ?, due = ?, last_review = ?,
         elapsed_days = ?, scheduled_days = ?, updated_at = ?
         WHERE id = ?''',
      [cardState, stability, difficulty, reps, lapses, due, lastReview,
       elapsedDays, scheduledDays,
       DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  /// 删除单词
  void delete(int id) {
    _v.execute('DELETE FROM user_words WHERE id = ?', [id]);
  }

  /// 查询所有单词（分页）
  List<Map<String, dynamic>> getAll({
    int offset = 0,
    int limit = 50,
    String? tagFilter,
    String? stateFilter,
    bool? favoriteOnly,
    String? sortBy,
  }) {
    final where = <String>[];
    final args = <Object?>[];

    if (tagFilter != null && tagFilter.isNotEmpty) {
      where.add('tags LIKE ?');
      args.add('%$tagFilter%');
    }
    if (stateFilter != null && stateFilter.isNotEmpty) {
      where.add('card_state = ?');
      args.add(stateFilter);
    }
    if (favoriteOnly == true) {
      where.add('is_favorite = 1');
    }

    final whereClause =
        where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';
    final orderBy = switch (sortBy) {
      'due' => 'due ASC',
      'word' => 'word COLLATE NOCASE ASC',
      'created' => 'created_at DESC',
      _ => 'created_at DESC',
    };

    final sql = 'SELECT * FROM user_words $whereClause ORDER BY $orderBy LIMIT ? OFFSET ?';
    args.add(limit);
    args.add(offset);
    return _v.select(sql, args);
  }

  /// 获取待复习单词（due <= now，排除新词与已掌握）
  List<Map<String, dynamic>> getDueWords({int limit = 100}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _v.select(
      "SELECT * FROM user_words WHERE due <= ? AND card_state NOT IN ('new', 'mastered') ORDER BY due ASC LIMIT ?",
      [now, limit],
    );
  }

  /// 获取新词（未复习过的）
  List<Map<String, dynamic>> getNewWords({int limit = 100}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _v.select(
      'SELECT * FROM user_words WHERE card_state = ? AND due <= ? ORDER BY created_at ASC LIMIT ?',
      ['new', now, limit],
    );
  }

  /// 今日学习过的单词（今日新增 UNION 今日复习，去重保序）——供「今日短文」取词
  List<String> getWordsStudiedToday() {
    final rows = _v.select(
      '''SELECT DISTINCT uw.word FROM user_words uw
         WHERE uw.created_at >= ?
         UNION
         SELECT DISTINCT uw.word FROM review_logs rl
         JOIN user_words uw ON uw.id = rl.user_word_id
         WHERE rl.reviewed_at >= ?''',
      [_todayUtcStart(), _todayUtcStart()],
    );
    return rows.map((r) => r['word'] as String).toList();
  }

  /// 获取词库全部单词文本（供"指定单词"多选列表）
  List<String> getAllWordTexts({int limit = 2000}) {
    final rows = _v.select(
      'SELECT word FROM user_words ORDER BY word COLLATE NOCASE ASC LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['word'] as String).toList();
  }

  /// 今日 UTC 起始时刻
  static String _todayUtcStart() {
    final now = DateTime.now().toUtc();
    return DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
  }

  /// 按添加日期范围查询（用于自选复习）
  /// [start] / [end] 为本地时间，内部转 UTC ISO 与 created_at 比较
  /// 注意：返回普通 List（而非 ResultSet），调用方可安全 shuffle
  List<Map<String, dynamic>> getWordsAddedBetween(DateTime start, DateTime end) {
    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();
    return _v
        .select(
          'SELECT * FROM user_words WHERE created_at >= ? AND created_at < ? ORDER BY created_at DESC',
          [startIso, endIso],
        )
        .map((r) => r as Map<String, dynamic>)
        .toList();
  }

  /// 获取词库中最早 / 最晚的添加日期（用于自定义日期选择范围边界）
  (DateTime, DateTime)? getAddedDateBounds() {
    final rows = _v.select(
      'SELECT MIN(created_at) AS mn, MAX(created_at) AS mx FROM user_words',
    );
    if (rows.isEmpty) return null;
    final mn = rows.first['mn'];
    final mx = rows.first['mx'];
    if (mn == null || mx == null) return null;
    try {
      final start = DateTime.parse(mn as String).toLocal();
      final end = DateTime.parse(mx as String).toLocal();
      return (start, end);
    } catch (_) {
      return null;
    }
  }

  /// 统计总数
  int count() {
    return _v.select('SELECT COUNT(*) as c FROM user_words').first['c'] as int;
  }

  /// 今日新增数量
  int countNewToday() {
    final todayStart = DateTime.now().toUtc();
    final startOfDay = DateTime(todayStart.year, todayStart.month, todayStart.day).toUtc().toIso8601String();
    final row = _v.select(
      'SELECT COUNT(*) as c FROM user_words WHERE created_at >= ?',
      [startOfDay],
    ).first;
    return row['c'] as int;
  }

  /// 搜索（英文 FTS5 / 中文 LIKE）
  List<Map<String, dynamic>> search(String query, {int limit = 100}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final isChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed);
    if (isChinese) {
      final pattern = '%$trimmed%';
      return _v.select(
        '''SELECT * FROM user_words
           WHERE custom_def LIKE ? OR note LIKE ? OR tags LIKE ?
           ORDER BY created_at DESC LIMIT ?''',
        [pattern, pattern, pattern, limit],
      );
    } else {
      final ftsQuery = '${trimmed.replaceAll('"', ' ')}*';
      return _v.select(
        '''SELECT uw.* FROM user_words_fts
           JOIN user_words uw ON uw.id = user_words_fts.rowid
           WHERE user_words_fts MATCH ?
           ORDER BY rank LIMIT ?''',
        [ftsQuery, limit],
      );
    }
  }
}
