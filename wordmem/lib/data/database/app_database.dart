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

    // 4.6 存量已掌握词 due 自愈（v2.1.7）：把 v2.1.5 fuse 遗留的「10 年后」拉回当前
    _healLegacyMasteredDue();

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
  score           INTEGER,
  timeouts        INTEGER NOT NULL DEFAULT 0,
  kind            TEXT NOT NULL DEFAULT 'review',
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

    // 检查式迁移：review_logs 增加 score / timeouts / kind（v2.1.8）
    // - score:    本轮测验得分 0–6（三环节 × 2 分扣分制；旧的存量记录为 NULL）
    // - timeouts: 本轮超时的环节数 0–3（复习历史里显示「超时 N 处」）
    // - kind:     'review' 常规三环节测验 ｜ 'quiz' 熟练词抽检
    //   （抽检此前不写任何历史；现在统一进 review_logs 用 kind 区分）
    final rlCols = _vocabDb
        .select('PRAGMA table_info(review_logs)')
        .map((r) => r['name'] as String)
        .toList();
    if (!rlCols.contains('score')) {
      _vocabDb.execute('ALTER TABLE review_logs ADD COLUMN score INTEGER;');
    }
    if (!rlCols.contains('timeouts')) {
      _vocabDb.execute(
          'ALTER TABLE review_logs ADD COLUMN timeouts INTEGER NOT NULL DEFAULT 0;');
    }
    if (!rlCols.contains('kind')) {
      _vocabDb.execute(
          "ALTER TABLE review_logs ADD COLUMN kind TEXT NOT NULL DEFAULT 'review';");
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

  /// fuse 遗留值的判定阈值：远超正常抽检排期上限（答对 15 天）。
  /// 留 365 天是为了让"正常数据会不会被误伤"这个问题有**数学上的**答案。
  static const Duration legacyMasteredDueThreshold = Duration(days: 365);

  /// 严格形状：ISO-8601 + 显式时区（`Z` 或 `±HH:MM`）。
  ///
  /// 为什么要形状校验，而不是直接 `DateTime.tryParse`：Dart 的 `tryParse` 会
  /// **宽松归一化越界值**——`'2036-13-45'` 会被解析成 2037-02-14，距离现在一样「很远」，
  /// 于是一个坏字符串会被误判成 fuse 遗留值而改掉。本判据的前提是
  /// 「只可能命中 App 自己写出的 fuse 值」，所以形状不符的脏数据一律放行不动。
  ///
  /// 实测真机存档 285 行的 `due` / `created_at` / `last_review` / `updated_at`
  /// **全部**符合该形状（长度 27、`Z` 结尾），故收紧零损失。
  static final RegExp _isoWithZone =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$');

  /// 「10 年 fuse 遗留值」判据（纯函数，便于单测）。
  ///
  /// 正常已掌握词的 `due` 只会在 now 前后 15 天内浮动
  /// （答对 +15 天 / 跳过 +7 天 / 答错 +3 天），因此 `due - now > 365 天`
  /// 只可能是 v2.1.5 `_masteredFuse` 的残留。
  ///
  /// 形状不符 / 缺失 / 不可解析 → **返回 false（不动它）**：脏数据宁可漏修，不可误修。
  static bool isLegacyMasteredDue(String? dueIso, DateTime now) {
    final raw = dueIso ?? '';
    if (!_isoWithZone.hasMatch(raw)) return false;
    final due = DateTime.tryParse(raw);
    if (due == null) return false;
    return due.difference(now.toUtc()) > legacyMasteredDueThreshold;
  }

  /// 存量已掌握词的 due 自愈（v2.1.7）。
  ///
  /// **为什么不能再用一次性迁移**：v2.1.5 的 `_masteredFuse` 会把「掌握」的词
  /// due 推到 10 年后（3650 天）。v2.1.6 用一次性迁移 `quiz_mastered_v1` 把它拉回，
  /// 但写法是「查到 app_settings 标签就 return」。2026-09-17 真机实测发现：
  /// 标签是在**空库**状态下写入的，之后才通过备份导入/恢复带进来的存量词
  /// **永远不会**被修到——用户 57 个已掌握词里 52 个停在 2036 年，永远进不了抽检池。
  ///
  /// 因此改成**按条件自愈**，不依赖任何标签：
  /// - 判据 [isLegacyMasteredDue]：`due` 可解析 且 距现在 > 365 天
  /// - 只处理 `card_state = 'mastered'`：fuse 只作用于已掌握词，绝不放宽到
  ///   review / learning / new —— 它们的 due 是真实排期，一行都不能碰
  /// - 不依赖标签 ⇒ 天然幂等（跑完即无行可匹配），且**每次启动都会跑**：
  ///   将来再恢复一次旧备份，也会在下次启动被自愈，而不是重新卡死
  /// - 只写 `due` 与 `updated_at`：**不碰** stability / difficulty / reps /
  ///   lapses / card_state / last_review，即不改变任何学习进度语义
  /// - 全部写在一个事务里；失败整体回滚并静默（不阻塞启动，下次再试）
  ///
  /// 无命中时直接 return：绝大多数启动是零写入。
  void _healLegacyMasteredDue() {
    try {
      final now = DateTime.now().toUtc();
      final rows = _vocabDb.select(
        "SELECT id, due FROM user_words WHERE card_state = 'mastered'",
      );
      final ids = <int>[
        for (final r in rows)
          if (isLegacyMasteredDue(r['due'] as String?, now)) r['id'] as int,
      ];
      if (ids.isEmpty) return;

      final nowIso = now.toIso8601String();
      _vocabDb.execute('BEGIN');
      try {
        for (final id in ids) {
          // 再带一次 card_state 条件：SELECT 与 UPDATE 之间状态若被改过就不动它
          _vocabDb.execute(
            'UPDATE user_words SET due = ?, updated_at = ? '
            "WHERE id = ? AND card_state = 'mastered'",
            [nowIso, nowIso, id],
          );
        }
        _vocabDb.execute('COMMIT');
      } catch (_) {
        _vocabDb.execute('ROLLBACK');
        rethrow; // 交给外层 catch 静默
      }
    } catch (_) {
      // 自愈失败不阻塞启动：数据保持原样，下次启动重试
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
