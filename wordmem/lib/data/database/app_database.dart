import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../core/constants/app_constants.dart';

/// 数据库连接管理器
/// 管理两个 SQLite 数据库：词典(只读，专业版唯一内置) + 个人词库(可写)
class AppDatabase {
  late Database _vocabDb;
  late Database _dictDb;

  Database get vocab => _vocabDb;
  Database get dict => _dictDb;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 读取版本标记文件内容（不存在返回 null）
  String? _readVersion(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return f.readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    final docDir = await getApplicationDocumentsDirectory();

    // 1. 词典数据库：专业版为唯一内置词典，从 assets 复制到文档目录（带版本检查）
    _dictDb =
        await _loadDict(AppConstants.dictProDbName, AppConstants.dictProVersion);

    // 2. 个人词库数据库
    final vocabPath = p.join(docDir.path, AppConstants.vocabDbName);
    _vocabDb = sqlite3.open(vocabPath);

    // 3. 设置 PRAGMA
    _vocabDb.execute('PRAGMA journal_mode=WAL;');
    _vocabDb.execute('PRAGMA synchronous=NORMAL;');
    _vocabDb.execute('PRAGMA foreign_keys=ON;');
    _vocabDb.execute('PRAGMA temp_store=MEMORY;');

    // 4. 创建表结构
    _createSchema();

    // 4.5 复习算法迁移（艾宾浩斯 7 周期）：老 8 档 reps → 新 7 档
    _migrateSchedule();

    // 5. 初始化默认数据
    _initDefaultData();

    // 6. 完整性检查
    _verifyIntegrity();

    _initialized = true;
  }

  /// 从 assets 复制词典到文档目录（带版本检查）并打开只读连接
  Future<Database> _loadDict(String dbName, String version) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dictPath = p.join(docDir.path, dbName);
    final dictVersionPath = p.join(docDir.path, '$dbName.version');
    final needCopy = !File(dictPath).existsSync() ||
        _readVersion(dictVersionPath) != version;
    if (needCopy) {
      final data = await rootBundle.load('assets/dict/$dbName');
      final bytes = data.buffer.asUint8List();
      await File(dictPath).writeAsBytes(bytes);
      await File(dictVersionPath).writeAsString(version);
    }
    return sqlite3.open(dictPath);
  }

  void _createSchema() {
    _vocabDb.execute('''
CREATE TABLE IF NOT EXISTS user_words (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  word            TEXT NOT NULL,
  sense_id        INTEGER DEFAULT 0,
  custom_def      TEXT,
  note            TEXT DEFAULT '',
  tags            TEXT DEFAULT '',
  is_favorite     INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  card_state      TEXT NOT NULL DEFAULT 'new',
  stability       REAL DEFAULT 0,
  difficulty      REAL DEFAULT 0,
  reps            INTEGER NOT NULL DEFAULT 0,
  lapses          INTEGER NOT NULL DEFAULT 0,
  due             TEXT NOT NULL,
  last_review     TEXT,
  elapsed_days    REAL DEFAULT 0,
  scheduled_days  REAL DEFAULT 0,
  source          TEXT NOT NULL DEFAULT 'manual',
  source_story_id INTEGER
);
''');

    _vocabDb.execute('''
CREATE TABLE IF NOT EXISTS review_logs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  user_word_id    INTEGER NOT NULL,
  rating          INTEGER NOT NULL,
  state           TEXT NOT NULL,
  elapsed_days    REAL,
  scheduled_days  REAL,
  reviewed_at     TEXT NOT NULL,
  FOREIGN KEY (user_word_id) REFERENCES user_words(id) ON DELETE CASCADE
);
''');

    _vocabDb.execute('''
CREATE TABLE IF NOT EXISTS fsrs_params (
  id                INTEGER PRIMARY KEY DEFAULT 1,
  parameters        TEXT NOT NULL,
  desired_retention REAL NOT NULL DEFAULT 0.9,
  optimized_at      TEXT,
  review_count      INTEGER DEFAULT 0,
  is_active         INTEGER NOT NULL DEFAULT 0,
  updated_at        TEXT NOT NULL
);
''');

    _vocabDb.execute('''
CREATE TABLE IF NOT EXISTS app_settings (
  key             TEXT PRIMARY KEY,
  value           TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);
''');

    // 今日短文（生成历史 + 记忆库条目，支持编辑与归档）
    _vocabDb.execute('''
CREATE TABLE IF NOT EXISTS story_logs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  title           TEXT NOT NULL DEFAULT '',
  content         TEXT NOT NULL,
  translation     TEXT NOT NULL DEFAULT '',
  words           TEXT NOT NULL DEFAULT '',
  source          TEXT NOT NULL DEFAULT 'template',
  archived        INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);
''');

    // 短文记忆测试记录
    _vocabDb.execute('''
CREATE TABLE IF NOT EXISTS story_quiz_records (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id        INTEGER NOT NULL,
  mode            TEXT NOT NULL,
  total           INTEGER NOT NULL,
  correct         INTEGER NOT NULL,
  wrong_blanks    TEXT NOT NULL DEFAULT '',
  created_at      TEXT NOT NULL
);
''');

    // 检查式迁移：user_words 增加 source / source_story_id 字段
    // （source: manual 手动添加 | quiz 短文测试错词；source_story_id: 错词来源短文）
    final uwCols = _vocabDb
        .select('PRAGMA table_info(user_words)')
        .map((r) => r['name'] as String)
        .toList();
    if (!uwCols.contains('source')) {
      _vocabDb.execute(
          "ALTER TABLE user_words ADD COLUMN source TEXT NOT NULL DEFAULT 'manual';");
    }
    if (!uwCols.contains('source_story_id')) {
      _vocabDb.execute(
          'ALTER TABLE user_words ADD COLUMN source_story_id INTEGER;');
    }

    // 索引
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_uw_due ON user_words(due);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_uw_state ON user_words(card_state);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_uw_created ON user_words(created_at);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_uw_fav ON user_words(is_favorite);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_uw_tags ON user_words(tags);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_uw_source ON user_words(source);');
    _vocabDb.execute(
        'CREATE INDEX IF NOT EXISTS idx_uw_src_story ON user_words(source_story_id);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_rl_word ON review_logs(user_word_id);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_rl_time ON review_logs(reviewed_at);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_story_created ON story_logs(created_at);');
    _vocabDb.execute('CREATE INDEX IF NOT EXISTS idx_story_archived ON story_logs(archived);');
    _vocabDb.execute(
        'CREATE INDEX IF NOT EXISTS idx_quiz_story ON story_quiz_records(story_id);');

    // FTS5 虚拟表
    _vocabDb.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS user_words_fts USING fts5(
  word, custom_def, note, tags,
  content='user_words', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2'
);
''');

    // FTS5 触发器
    _vocabDb.execute('''
CREATE TRIGGER IF NOT EXISTS user_words_ai AFTER INSERT ON user_words BEGIN
  INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
  VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
END;
''');
    _vocabDb.execute('''
CREATE TRIGGER IF NOT EXISTS user_words_ad AFTER DELETE ON user_words BEGIN
  INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
  VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
END;
''');
    _vocabDb.execute('''
CREATE TRIGGER IF NOT EXISTS user_words_au AFTER UPDATE ON user_words BEGIN
  INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
  VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
  INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
  VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
END;
''');
  }

  /// 复习算法迁移：旧 8 档艾宾浩斯间隔 [3h,8h,1d,2d,4d,7d,15d,30d]
  /// 迁移到新 7 周期 [5min,30min,12h,1d,2d,4d,7d]。
  /// - 旧 reps 1..7 直接沿用（语义相近：学习进度档位）
  /// - 旧 reps 8（30 天档）→ 新 reps 7（7 天档，封顶）
  /// - 已 mastered 的词不受影响
  /// 仅执行一次（app_settings 打标），幂等安全。
  void _migrateSchedule() {
    try {
      final done = _vocabDb.select(
        "SELECT COUNT(*) as c FROM app_settings WHERE key = 'sched_ebbinghaus_v7'",
      ).first['c'] as int;
      if (done > 0) return;

      _vocabDb.execute(
        '''UPDATE user_words SET reps = CASE WHEN reps >= 8 THEN 7 ELSE reps END
           WHERE reps BETWEEN 1 AND 8 AND card_state != 'mastered' ''',
      );
      _vocabDb.execute(
        '''INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at''',
        ['sched_ebbinghaus_v7', '1', DateTime.now().toUtc().toIso8601String()],
      );
    } catch (_) {
      // 迁移失败不阻塞启动，下次启动重试
    }
  }

  void _initDefaultData() {
    final now = DateTime.now().toUtc().toIso8601String();
    // 默认 FSRS 参数
    final count = _vocabDb
        .select('SELECT COUNT(*) as c FROM fsrs_params WHERE id = 1')
        .first['c'] as int;
    if (count == 0) {
      _vocabDb.execute(
        'INSERT INTO fsrs_params (id, parameters, desired_retention, is_active, updated_at) VALUES (1, ?, 0.9, 0, ?)',
        [AppConstants.defaultFsrsParams.join(','), now],
      );
    }
  }

  void _verifyIntegrity() {
    final result = _vocabDb.select('PRAGMA quick_check;').first;
    if (result['quick_check'] != 'ok') {
      throw Exception('数据库损坏: ${result['quick_check']}');
    }
  }

  /// 事务执行
  void transaction(void Function() action) {
    _vocabDb.execute('BEGIN;');
    try {
      action();
      _vocabDb.execute('COMMIT;');
    } catch (e) {
      _vocabDb.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// WAL checkpoint
  void walCheckpoint() {
    _vocabDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
  }

  /// 获取数据库文件路径
  Future<String> get vocabDbPath async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, AppConstants.vocabDbName);
  }

  /// 关闭
  void close() {
    try {
      _vocabDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}
    _vocabDb.dispose();
    _dictDb.dispose();
    _initialized = false;
  }

  /// 关闭连接并清理 WAL 残留文件（供导入覆盖数据库文件前调用）。
  ///
  /// 根因修复：WAL 模式下残留 vocabulary.db-wal / -shm 文件，
  /// 直接覆盖主 db 后重新 open 会回放旧日志导致数据错乱。
  /// 因此覆盖前必须先 checkpoint 并删除残留的 -wal / -shm。
  Future<void> closeForReplace() async {
    try {
      _vocabDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}
    _vocabDb.dispose();
    _dictDb.dispose();
    _initialized = false;

    final path = await vocabDbPath;
    for (final suffix in const ['-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}
