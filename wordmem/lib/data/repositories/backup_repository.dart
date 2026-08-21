import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../database/app_database.dart';
import '../database/word_dao.dart';
import '../database/review_dao.dart';
import '../database/settings_dao.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/stats.dart';

/// 备份仓库 - 导入/导出
class BackupRepository {
  final AppDatabase _db;
  final WordDao _wordDao;
  final ReviewDao _reviewDao;
  final SettingsDao _settingsDao;

  BackupRepository(this._db, this._wordDao, this._reviewDao, this._settingsDao);

  /// 生成默认备份文件名
  static String defaultFileName(DateTime now) {
    return 'wordmem_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.zip';
  }

  /// 生成备份 zip 字节（供系统保存对话框直接写入）
  Future<Uint8List> exportBytes() async {
    final now = DateTime.now().toUtc();

    // 真实应用版本（manifest 元数据，供识别备份来源版本）
    var appVersion = AppConstants.appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) appVersion = info.version;
    } catch (_) {
      // 读取失败时回退常量版本
    }

    // 1. 用 SQLite 在线备份 API 做一致性快照（替代"直接读主库文件"）。
    //    原实现先 PRAGMA wal_checkpoint(TRUNCATE) 再 readAsBytes，但 checkpoint
    //    返回的 busy/log 状态被忽略——若有写活动未合并 WAL，读出的主库文件残缺，
    //    重新导入时会报"数据库已损坏"。backup API 在数据库层面保证一致性快照。
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = p.join(tmpDir.path,
        'wordmem_export_${DateTime.now().millisecondsSinceEpoch}.db');
    final destDb = sqlite3.open(tmpPath);
    try {
      // 注意：不要用 drain<double>() —— Dart SDK 的 drain 在默认值为 null 时会抛
      // "type 'Null' is not a subtype of type 'double' in type cast"，改用 await for。
      await for (final _ in _db.vocab.backup(destDb, nPage: -1)) {}
    } finally {
      destDb.dispose();
    }
    // 自检：快照必须是完整可读的库，失败则终止导出（避免产生损坏备份）
    final check = sqlite3.open(tmpPath);
    try {
      final result = check.select('PRAGMA quick_check;').first;
      if (result['quick_check'] != 'ok') {
        throw Exception('备份快照完整性检查失败: ${result['quick_check']}');
      }
    } finally {
      check.dispose();
    }
    final dbFile = File(tmpPath);
    final dbBytes = await dbFile.readAsBytes();
    try {
      await dbFile.delete();
    } catch (_) {}

    // 3. 读取 FSRS 参数
    final params = _settingsDao.getFsrsParams();
    final paramsJson = jsonEncode(params ?? {});

    // 4. 计算校验和
    final dbSha256 = sha256.convert(dbBytes).toString();
    final paramsSha256 = sha256.convert(utf8.encode(paramsJson)).toString();

    // 5. 统计信息
    final wordCount = _wordDao.count();
    final reviewCount = _reviewDao.count();
    final streak = _reviewDao.getCurrentStreak();

    // 6. 生成 manifest
    final manifest = {
      'version': AppConstants.backupVersion,
      'app_version': appVersion,
      'dict_version': AppConstants.dictProVersion,
      'dict_word_count': AppConstants.dictProWordCount,
      'backup_time': now.toIso8601String(),
      'user_word_count': wordCount,
      'review_log_count': reviewCount,
      'streak_days': streak,
      'files': {
        'vocabulary.db': {
          'sha256': dbSha256,
          'size': dbBytes.length,
        },
        'fsrs_params.json': {
          'sha256': paramsSha256,
          'size': paramsJson.length,
        },
      },
    };
    final manifestJson = jsonEncode(manifest);

    // 7. 打包 zip
    final manifestBytes = utf8.encode(manifestJson);
    final paramsBytes = utf8.encode(paramsJson);
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
      ..addFile(ArchiveFile('vocabulary.db', dbBytes.length, dbBytes))
      ..addFile(ArchiveFile('fsrs_params.json', paramsBytes.length, paramsBytes));

    final zipBytes = ZipEncoder().encode(archive)!;
    return Uint8List.fromList(zipBytes);
  }

  /// 导出备份到文件
  /// [outputPath] 指定保存路径；为空时保存到应用文档目录
  Future<String> export({String? outputPath}) async {
    final bytes = await exportBytes();
    final now = DateTime.now().toUtc();
    final finalPath = (outputPath != null && outputPath.isNotEmpty)
        ? outputPath
        : p.join(
            (await getApplicationDocumentsDirectory()).path,
            defaultFileName(now),
          );
    await File(finalPath).writeAsBytes(bytes);
    return finalPath;
  }

  /// 覆盖导入（重建模式）。
  ///
  /// 不再"直接把 zip 里的 db 文件替换当前库"——那样依赖 zip db 与手机 sqlite
  /// 版本/schema 完全兼容，一旦有差异（或旧备份 WAL 未合并导致残缺）就会在
  /// 打开时失败报"数据库已损坏"。改为：读出 zip 数据 → 用 App 自身 schema
  /// 重建全新空库 → 灌入数据，任何能被 sqlite3 读取的备份都能成功导入。
  Future<ImportResult> import(String zipPath) async {
    try {
      // 1. 读取 zip + 校验完整性
      final zipBytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.findFile('manifest.json');
      final dbFile = archive.findFile('vocabulary.db');
      if (manifestFile == null || dbFile == null) {
        return const ImportResult(success: false, error: '备份文件格式不正确');
      }
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;
      final dbBytes = dbFile.content as List<int>;
      final dbSha256 = sha256.convert(dbBytes).toString();
      final expectedSha256 =
          (manifest['files'] as Map<String, dynamic>)['vocabulary.db']['sha256']
              as String;
      if (dbSha256 != expectedSha256) {
        return const ImportResult(
            success: false,
            error: '数据库文件校验失败（sha256 不匹配）：文件可能在传输中损坏或被修改，请重新传输 zip');
      }

      // 2. 打开 zip 内 db，读取词条与复习记录
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = p.join(tmpDir.path,
          'wordmem_imp_${DateTime.now().millisecondsSinceEpoch}.db');
      await File(tmpPath).writeAsBytes(dbBytes);
      final srcDb = sqlite3.open(tmpPath);
      final List<Map<String, dynamic>> srcWords;
      final List<Map<String, dynamic>> srcLogs;
      final List<Map<String, dynamic>> srcSettings;
      final List<Map<String, dynamic>> srcStories;
      final List<Map<String, dynamic>> srcQuizzes;
      try {
        srcWords = srcDb.select('SELECT * FROM user_words').toList();
        srcLogs = srcDb.select('SELECT * FROM review_logs').toList();
        srcSettings =
            srcDb.select('SELECT key, value, updated_at FROM app_settings')
                .toList()
              ..retainWhere(
                  (r) => _syncSettingsKeys.contains(r['key'] as String?));
        srcStories =
            srcDb.select('SELECT * FROM story_logs ORDER BY id').toList();
        srcQuizzes =
            srcDb.select('SELECT * FROM story_quiz_records').toList();
      } finally {
        srcDb.dispose();
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }

      // 3. 备份当前数据库
      final currentDbPath = await _db.vocabDbPath;
      final backupPath = '$currentDbPath.bak';
      await File(currentDbPath).copy(backupPath);

      // 4. 关闭连接、删除旧库，让 init 重建全新空库（schema 与本机一致）
      await _db.closeForReplace();
      try {
        await File(currentDbPath).delete();
      } catch (_) {}

      try {
        await _db.init();
        final (added, skipped, logsAdded) = _restoreData(
          srcWords,
          srcLogs,
          srcSettings,
          srcStories,
          srcQuizzes,
          skipExisting: false,
        );
        await File(backupPath).delete();
        return ImportResult(
          success: true,
          wordCount: added,
          reviewCount: logsAdded,
          skippedCount: skipped,
        );
      } catch (e) {
        // 恢复原库
        try {
          await File(backupPath).copy(currentDbPath);
        } catch (_) {}
        await _db.init();
        return ImportResult(success: false, error: '导入失败，已恢复原数据: $e');
      }
    } catch (e) {
      return ImportResult(success: false, error: '导入失败: $e');
    }
  }

  /// 续写导入：只添加当前词库中不存在的单词（按 word 去重），
  /// 保留备份中的复习状态，并重建 review_logs 的外键映射。
  /// 不替换现有数据，属于"合并/续写"模式。
  Future<ImportResult> importMerge(String zipPath) async {
    try {
      // 1. 读取 zip + 校验完整性
      final zipBytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.findFile('manifest.json');
      final dbFile = archive.findFile('vocabulary.db');
      if (manifestFile == null || dbFile == null) {
        return const ImportResult(success: false, error: '备份文件格式不正确');
      }
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;
      final dbBytes = dbFile.content as List<int>;
      final dbSha256 = sha256.convert(dbBytes).toString();
      final expectedSha256 =
          (manifest['files'] as Map<String, dynamic>)['vocabulary.db']['sha256']
              as String;
      if (dbSha256 != expectedSha256) {
        return const ImportResult(
            success: false,
            error: '数据库文件校验失败（sha256 不匹配）：文件可能在传输中损坏或被修改，请重新传输 zip');
      }

      // 2. 打开 zip 内 db，读取词条与复习记录
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = p.join(tmpDir.path,
          'wordmem_merge_${DateTime.now().millisecondsSinceEpoch}.db');
      await File(tmpPath).writeAsBytes(dbBytes);
      final srcDb = sqlite3.open(tmpPath);
      final List<Map<String, dynamic>> srcWords;
      final List<Map<String, dynamic>> srcLogs;
      final List<Map<String, dynamic>> srcSettings;
      final List<Map<String, dynamic>> srcStories;
      final List<Map<String, dynamic>> srcQuizzes;
      try {
        srcWords = srcDb.select('SELECT * FROM user_words').toList();
        srcLogs = srcDb.select('SELECT * FROM review_logs').toList();
        srcSettings =
            srcDb.select('SELECT key, value, updated_at FROM app_settings')
                .toList()
              ..retainWhere(
                  (r) => _syncSettingsKeys.contains(r['key'] as String?));
        srcStories =
            srcDb.select('SELECT * FROM story_logs ORDER BY id').toList();
        srcQuizzes =
            srcDb.select('SELECT * FROM story_quiz_records').toList();
      } finally {
        srcDb.dispose();
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }

      // 3. 去重插入
      final (added, skipped, logsAdded) = _restoreData(
        srcWords,
        srcLogs,
        srcSettings,
        srcStories,
        srcQuizzes,
        skipExisting: true,
      );

      return ImportResult(
        success: true,
        wordCount: added,
        reviewCount: logsAdded,
        skippedCount: skipped,
      );
    } catch (e) {
      return ImportResult(success: false, error: '续写失败: $e');
    }
  }

  /// 随备份恢复的学习相关 app_settings 白名单键。
  /// 设备偏好（主题/提醒等）不属于学习数据，不随备份迁移。
  static const Set<String> _syncSettingsKeys = {
    'synonym_group_mastery',
    'root_mastery',
    'synonym_blacklist',
    'root_blacklist',
    'root_excluded',
  };

  /// 把 zip 内读出的词条/复习记录/学习设置/日记写入当前词库。
  /// [skipExisting] 为 true 时按 word 去重跳过已存在词（续写合并）；
  /// 为 false 时全部插入（覆盖重建，当前库应为新建空库）。
  /// 返回 (新增词数, 跳过词数, 新增复习记录数)。
  (int, int, int) _restoreData(
    List<Map<String, dynamic>> srcWords,
    List<Map<String, dynamic>> srcLogs,
    List<Map<String, dynamic>> srcSettings,
    List<Map<String, dynamic>> srcStories,
    List<Map<String, dynamic>> srcQuizzes, {
    required bool skipExisting,
  }) {
    final idMap = <int, int>{};
    var added = 0;
    var skipped = 0;
    var logsAdded = 0;

    _db.transaction(() {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final w in srcWords) {
        final word = (w['word'] as String? ?? '').trim();
        if (word.isEmpty) continue;
        if (skipExisting && _wordDao.exists(word)) {
          skipped++;
          continue;
        }
        _db.vocab.execute(
          '''INSERT INTO user_words
             (word, sense_id, custom_def, note, tags, is_favorite,
              created_at, updated_at, card_state, stability, difficulty,
              reps, lapses, due, last_review, elapsed_days, scheduled_days)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            w['word'],
            w['sense_id'] ?? 0,
            w['custom_def'],
            w['note'] ?? '',
            w['tags'] ?? '',
            w['is_favorite'] ?? 0,
            w['created_at'] ?? now,
            w['updated_at'] ?? now,
            w['card_state'] ?? 'new',
            w['stability'] ?? 0,
            w['difficulty'] ?? 0,
            w['reps'] ?? 0,
            w['lapses'] ?? 0,
            w['due'] ?? now,
            w['last_review'],
            w['elapsed_days'] ?? 0,
            w['scheduled_days'] ?? 0,
          ],
        );
        final newId = _db.vocab
            .select('SELECT last_insert_rowid() as id')
            .first['id'] as int;
        idMap[w['id'] as int] = newId;
        added++;
      }

      // 插入复习记录（重建外键映射，重复词的历史跳过）
      for (final log in srcLogs) {
        final oldWid = log['user_word_id'] as int?;
        if (oldWid == null) continue;
        final newWid = idMap[oldWid];
        if (newWid == null) continue;
        _db.vocab.execute(
          '''INSERT INTO review_logs
             (user_word_id, rating, state, elapsed_days, scheduled_days, reviewed_at)
             VALUES (?, ?, ?, ?, ?, ?)''',
          [
            newWid,
            log['rating'] ?? 0,
            log['state'] ?? 'new',
            log['elapsed_days'],
            log['scheduled_days'],
            log['reviewed_at'],
          ],
        );
        logsAdded++;
      }

      // 学习设置（白名单键）：覆盖 REPLACE / 续写合并
      _restoreSettings(srcSettings, skipExisting: skipExisting);

      // 日记 + 测验记录（覆盖全插 / 续写按标题去重）
      _restoreStories(srcStories, srcQuizzes, skipExisting: skipExisting);
    });

    return (added, skipped, logsAdded);
  }

  /// 恢复 app_settings 白名单键（群组熟悉度 / 近义词·词根黑名单等）。
  /// 覆盖模式直接写入；续写模式与现有值合并（计分取 max、集合取并集）。
  void _restoreSettings(
    List<Map<String, dynamic>> srcSettings, {
    required bool skipExisting,
  }) {
    if (srcSettings.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final s in srcSettings) {
      final key = s['key'] as String?;
      final newVal = s['value'] as String?;
      if (key == null || newVal == null) continue;
      var finalVal = newVal;
      if (skipExisting) {
        final rows = _db.vocab
            .select('SELECT value FROM app_settings WHERE key = ?', [key]);
        if (rows.isNotEmpty) {
          try {
            final merged = _mergeJsonMaps(
              jsonDecode(rows.first['value'] as String)
                  as Map<String, dynamic>,
              jsonDecode(newVal) as Map<String, dynamic>,
            );
            finalVal = jsonEncode(merged);
          } catch (_) {
            // 任一值非 JSON map 时不合并，直接覆盖
          }
        }
      }
      _db.vocab.execute(
        'INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
        [key, finalVal, now],
      );
    }
  }

  /// 合并两个 JSON map：数值键取较大值（如熟悉度次数）、列表键取并集（如黑名单），
  /// 其余以备份值覆盖。用于续写合并时保留现有进度并吸收备份数据。
  Map<String, dynamic> _mergeJsonMaps(
      Map<String, dynamic> a, Map<String, dynamic> b) {
    final out = Map<String, dynamic>.from(a);
    for (final e in b.entries) {
      final ov = out[e.key];
      if (ov is int && e.value is int) {
        out[e.key] = ov > e.value ? ov : e.value;
      } else if (ov is List && e.value is List) {
        out[e.key] = {
          ...ov.cast<String>(),
          ...(e.value as List).cast<String>(),
        }.toList();
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  /// 恢复日记与测验记录。覆盖模式全量插入；续写模式按标题去重（避免重复日记），
  /// 测验记录的 story_id 通过旧→新 id 映射重建。
  void _restoreStories(
    List<Map<String, dynamic>> srcStories,
    List<Map<String, dynamic>> srcQuizzes, {
    required bool skipExisting,
  }) {
    if (srcStories.isEmpty && srcQuizzes.isEmpty) return;
    final storyIdMap = <int, int>{};
    final existingTitles = skipExisting
        ? _db.vocab
            .select('SELECT title FROM story_logs')
            .map((r) => r['title'] as String)
            .toSet()
        : <String>{};
    for (final s in srcStories) {
      final title = s['title'] as String? ?? '';
      if (skipExisting && existingTitles.contains(title)) continue;
      _db.vocab.execute(
        '''INSERT INTO story_logs
           (title, content, translation, words, source, archived, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          s['title'] ?? '',
          s['content'] ?? '',
          s['translation'] ?? '',
          s['words'] ?? '',
          s['source'] ?? 'template',
          s['archived'] ?? 0,
          s['created_at'],
          s['updated_at'] ?? s['created_at'],
        ],
      );
      final newId = _db.vocab
          .select('SELECT last_insert_rowid() as id')
          .first['id'] as int;
      storyIdMap[s['id'] as int] = newId;
    }
    for (final q in srcQuizzes) {
      final oldSid = q['story_id'] as int?;
      if (oldSid == null) continue;
      final newSid = storyIdMap[oldSid];
      if (newSid == null) continue;
      _db.vocab.execute(
        '''INSERT INTO story_quiz_records
           (story_id, mode, total, correct, wrong_blanks, created_at)
           VALUES (?, ?, ?, ?, ?, ?)''',
        [
          newSid,
          q['mode'] ?? '',
          q['total'] ?? 0,
          q['correct'] ?? 0,
          q['wrong_blanks'] ?? '',
          q['created_at'],
        ],
      );
    }
  }
}
