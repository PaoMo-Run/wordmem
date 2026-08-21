import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';
import '../../domain/models/story_quiz.dart';

/// 短文记忆测试 DAO - story_quiz_records 表操作 + 错词加入词库
class StoryQuizDao {
  final AppDatabase _db;
  StoryQuizDao(this._db);

  Database get _v => _db.vocab;

  /// 记录一次测试结果
  int insertRecord(StoryQuizRecord record) {
    _v.execute(
      '''INSERT INTO story_quiz_records
         (story_id, mode, total, correct, wrong_blanks, created_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [
        record.storyId,
        record.mode.name,
        record.total,
        record.correct,
        record.wrongBlanks
            .map((w) => '${w.word}:${w.userAnswer}:${w.correctAnswer}')
            .join(';'),
        record.createdAt.toUtc().toIso8601String(),
      ],
    );
    return _v.select('SELECT last_insert_rowid() as id').first['id'] as int;
  }

  /// 查询某篇短文的历史测试记录（按时间倒序）
  List<StoryQuizRecord> getByStory(int storyId) {
    final rows = _v.select(
      'SELECT * FROM story_quiz_records WHERE story_id = ? ORDER BY created_at DESC',
      [storyId],
    );
    return rows.map(StoryQuizRecord.fromMap).toList();
  }

  /// 将错词加入词库（source='quiz' + source_story_id），已在词库（任意来源）的跳过。
  /// 返回实际新增的单词列表。
  List<String> addWrongWordsToLibrary(
    List<String> words, {
    int? storyId,
  }) {
    if (words.isEmpty) return const [];
    final added = <String>[];
    final now = DateTime.now().toUtc().toIso8601String();
    _db.transaction(() {
      for (final w in words) {
        final word = w.trim();
        if (word.isEmpty) continue;
        final exists = _v
            .select('SELECT COUNT(*) as c FROM user_words WHERE word = ? COLLATE NOCASE',
                [word])
            .first['c'] as int;
        if (exists > 0) continue;
        _v.execute(
          '''INSERT INTO user_words
             (word, sense_id, custom_def, note, tags, is_favorite,
              created_at, updated_at, card_state, stability, difficulty,
              reps, lapses, due, last_review, elapsed_days, scheduled_days,
              source, source_story_id)
             VALUES (?, 0, NULL, '', '', 0, ?, ?, 'new', 0, 0, 0, 0, ?, NULL, 0, 0, 'quiz', ?)''',
          [word, now, now, now, storyId],
        );
        added.add(word);
      }
    });
    return added;
  }

  /// 词库分组（方案 B）：
  /// - 手动添加：source != 'quiz'（含旧数据 NULL）
  /// - 短文测试：source = 'quiz'，按 source_story_id 关联短文标题分组
  List<Map<String, dynamic>> getLibraryGroups() {
    final groups = <Map<String, dynamic>>[];

    final manualRows = _v.select(
        "SELECT word FROM user_words WHERE source IS NULL OR source != 'quiz' ORDER BY created_at DESC");
    groups.add({
      'type': 'manual',
      'title': '手动添加',
      'words': manualRows.map((r) => r['word'] as String).toList(),
    });

    final quizRows = _v.select('''
      SELECT uw.word, uw.source_story_id,
             COALESCE(sl.title, '') as story_title
      FROM user_words uw
      LEFT JOIN story_logs sl ON sl.id = uw.source_story_id
      WHERE uw.source = 'quiz'
      ORDER BY uw.created_at DESC
    ''');
    final byStory = <int?, List<String>>{};
    final storyTitles = <int?, String>{};
    for (final r in quizRows) {
      final storyId = r['source_story_id'] as int?;
      byStory.putIfAbsent(storyId, () => []).add(r['word'] as String);
      storyTitles[storyId] = r['story_title'] as String? ?? '';
    }
    byStory.forEach((storyId, words) {
      groups.add({
        'type': 'quiz',
        'storyId': storyId,
        'title': storyTitles[storyId]?.isNotEmpty == true
            ? storyTitles[storyId]
            : '短文测试',
        'words': words,
      });
    });
    return groups;
  }
}
