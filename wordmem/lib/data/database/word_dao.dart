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

  // ───────────────── 熟练词抽检（v2.1.6） ─────────────────

  /// 抽检候选：**全部冷却期已过**的已掌握词，按 due 升序（最久未抽在前）。
  ///
  /// v2.1.7 起不再截「前 N 个窗口」：随机化配比改由
  /// [AppConstants.orderTimeWeight] 的混合打分控制（见
  /// `ReviewRepository.blendByTimeWeight`），而打分需要**全体候选的时间名次**
  /// 才成立——先截窗口会让窗口外的词名次失真，等于把时间权重重新钉回 1.0。
  /// 调用方取到候选后自行打分、取前 5 个。
  ///
  /// ⚠️ v2.1.7 修复：原实现带一条 fallback——冷却期内的候选不足 5 个时，
  /// 会**丢掉 `due <= now` 条件**硬凑数量。对"已掌握词刚好 5 个"的用户后果是：
  /// 每轮抽检都抽走这 5 个（due 推后 15 天）→ 下一轮 ready 为空 → 又走 fallback
  /// 把这 5 个原样还回来，于是无论抽多少次永远是同一批词（只是顺序随机）。
  /// 宁可本次不抽检，也不放行冷却期内的词：池子小是数据现状，
  /// 不是可以打破冷却期的理由。
  List<Map<String, dynamic>> pickMasteredQuizCandidates() {
    final now = DateTime.now().toUtc().toIso8601String();
    return _v
        .select(
          '''SELECT * FROM user_words
         WHERE card_state = 'mastered' AND due <= ?
         ORDER BY due ASC''',
          [now],
        )
        .map((r) => r as Map<String, dynamic>)
        .toList();
  }

  /// 已掌握词总数（抽检冷却期是否缩短的判据，v2.1.7）
  int countMastered() {
    return _v
        .select(
            "SELECT COUNT(*) AS c FROM user_words WHERE card_state = 'mastered'")
        .first['c'] as int;
  }

  /// 抽检状态回写：只更新 due（下次可抽检时间）与 difficulty（失败计数），
  /// 不触碰 FSRS 的 stability / reps / lapses 等排期字段。
  void updateMasteredQuizState(
    int id, {
    required String due,
    required double difficulty,
  }) {
    _v.execute(
      '''UPDATE user_words SET due = ?, difficulty = ?, updated_at = ?
         WHERE id = ?''',
      [due, difficulty, DateTime.now().toUtc().toIso8601String(), id],
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
    // v2.1.7：① 支持升/降两个方向；② **按到期时间排序时已掌握词固定排最后**。
    //
    // 为什么 mastered 要最后：它们的 `due` 语义是「下次可抽检时间」而非复习排期，
    // 而且是最近才被拉到当前附近（自愈），按 due 升序会整批挤到最前面 ——
    // 用户想看的「最近要复习的词」反被顶下去（真机反馈 2026-09-17）。
    const masteredLast = "CASE WHEN card_state = 'mastered' THEN 1 ELSE 0 END";
    // v2.1.9：`last_review` 对**从未复习过的新词是 NULL**，统一排到最后
    // （它们没有"上次复习时间"这个属性，把 NULL 当最小值会让"久 → 近"一开始
    //  全是新词，看不出排序效果）。与 masteredLast 同理，不依赖升/降方向。
    const neverReviewedLast =
        'CASE WHEN last_review IS NULL THEN 1 ELSE 0 END';
    final orderBy = switch (sortBy) {
      'due' || 'due_asc' => '$masteredLast, due ASC',
      'due_desc' => '$masteredLast, due DESC',
      'last_review' || 'last_review_desc' =>
        '$neverReviewedLast, last_review DESC',
      'last_review_asc' => '$neverReviewedLast, last_review ASC',
      'word' || 'word_asc' => 'word COLLATE NOCASE ASC',
      'word_desc' => 'word COLLATE NOCASE DESC',
      'created_asc' => 'created_at ASC',
      _ => 'created_at DESC',
    };

    final sql = 'SELECT * FROM user_words $whereClause ORDER BY $orderBy LIMIT ? OFFSET ?';
    args.add(limit);
    args.add(offset);
    return _v.select(sql, args);
  }

  /// 待处理量的**唯一口径（v2.1.7）**：首页按钮 / 复习中心 / 通知文案 / 复习队列
  /// 必须全部用它，否则会出现「按钮显示 N 个词、点进去却暂无待复习单词」。
  ///
  /// ⚠️ 两条不变量：
  /// 1. **`mastered` 必须排除**——已掌握词的 `due` 是「下次可抽检时间」而非复习排期
  ///    （抽检池由 `ReviewRepository.pickMasteredQuizWords` 单独管理）。
  ///    真机反馈 2026-09-17：自愈把 52 个已掌握词的 due 拉到当前后，首页按钮凭空
  ///    多出 52 个待复习，点进去是空的。
  /// 2. 两个切片互斥且穷尽「到期且非已掌握」集合：`dueNew`（新词）+ `dueReview`
  ///    （非新词非已掌握），两者之和 == 复习队列里会出现的词数。
  static const String dueNewWhere = "due <= ? AND card_state = 'new'";
  static const String dueReviewWhere =
      "due <= ? AND card_state NOT IN ('new', 'mastered')";

  /// 待处理词数（新词 + 待复习，与复习队列同口径）
  ///
  /// 注意：复习队列有 `limit`（`getReviewQueue(limit: 500)`），
  /// 因此待处理数 > limit 时，本值可能大于实际一次能刷到的词数。
  int countPendingQueue() {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = _v.select(
      'SELECT COUNT(*) AS c FROM user_words WHERE $dueNewWhere OR $dueReviewWhere',
      [now, now],
    ).first;
    return row['c'] as int;
  }

  /// 未来 [window] 内将到期的词数（首页提示用，v2.1.6）
  ///
  /// 只统计「此刻尚未到期、但将在 window 内到期」的词：不含已到期项，
  /// 也不含已掌握词（它们的 due 表示"下次可抽检时间"，语义不同）。
  int countDueWithin(Duration window) {
    final now = DateTime.now().toUtc();
    final row = _v.select(
      """SELECT COUNT(*) as c FROM user_words
         WHERE due > ? AND due <= ? AND card_state != 'mastered'""",
      [now.toIso8601String(), now.add(window).toIso8601String()],
    ).first;
    return row['c'] as int;
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
