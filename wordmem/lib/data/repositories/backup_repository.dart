import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
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

    // 1. WAL checkpoint
    _db.walCheckpoint();

    // 2. 读取数据库文件
    final dbPath = await _db.vocabDbPath;
    final dbFile = File(dbPath);
    final dbBytes = await dbFile.readAsBytes();

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
      'app_version': '1.0.0',
      'dict_version': AppConstants.dictVersion,
      'dict_word_count': AppConstants.dictWordCount,
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

  /// 导入备份
  Future<ImportResult> import(String zipPath) async {
    try {
      // 1. 读取 zip
      final zipBytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      final manifestFile = archive.findFile('manifest.json');
      final dbFile = archive.findFile('vocabulary.db');

      if (manifestFile == null || dbFile == null) {
        return const ImportResult(success: false, error: '备份文件格式不正确');
      }

      // 2. 解析 manifest
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;

      // 3. 校验文件完整性
      final dbBytes = dbFile.content as List<int>;
      final dbSha256 = sha256.convert(dbBytes).toString();
      final expectedSha256 =
          (manifest['files'] as Map<String, dynamic>)['vocabulary.db']['sha256']
              as String;

      if (dbSha256 != expectedSha256) {
        return const ImportResult(success: false, error: '数据库文件校验失败，文件可能已损坏');
      }

      // 4. 备份当前数据库
      final currentDbPath = await _db.vocabDbPath;
      final backupPath = '$currentDbPath.bak';
      await File(currentDbPath).copy(backupPath);

      // 5. 安全关闭当前连接并清理 WAL 残留（修复导入不生效的根因）
      await _db.closeForReplace();

      // 6. 写入新数据库
      await File(currentDbPath).writeAsBytes(dbBytes);

      // 7. 重新打开并验证
      try {
        await _db.init();
        // 删除临时备份
        await File(backupPath).delete();
      } catch (e) {
        // 恢复
        await File(backupPath).copy(currentDbPath);
        await _db.init();
        return const ImportResult(success: false, error: '导入的数据库文件已损坏');
      }

      return ImportResult(
        success: true,
        wordCount: manifest['user_word_count'] as int?,
        reviewCount: manifest['review_log_count'] as int?,
      );
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
        return const ImportResult(success: false, error: '数据库文件校验失败，文件可能已损坏');
      }

      // 2. 写备份 db 到临时文件并打开
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = p.join(tmpDir.path,
          'wordmem_merge_${DateTime.now().millisecondsSinceEpoch}.db');
      await File(tmpPath).writeAsBytes(dbBytes);
      final srcDb = sqlite3.open(tmpPath);

      try {
        // 3. 读取备份数据
        final srcWords = srcDb.select('SELECT * FROM user_words').toList();
        final srcLogs = srcDb.select('SELECT * FROM review_logs').toList();

        // 4. 事务插入
        final idMap = <int, int>{};
        var added = 0;
        var skipped = 0;
        var logsAdded = 0;

        _db.transaction(() {
          final now = DateTime.now().toUtc().toIso8601String();
          for (final w in srcWords) {
            final word = (w['word'] as String? ?? '').trim();
            if (word.isEmpty) continue;
            if (_wordDao.exists(word)) {
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

          // 5. 插入复习记录（重建外键映射，跳过重复词的历史）
          for (final log in srcLogs) {
            final oldWid = log['user_word_id'] as int?;
            if (oldWid == null) continue;
            final newWid = idMap[oldWid];
            if (newWid == null) continue; // 对应词已存在，其历史跳过
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
        });

        return ImportResult(
          success: true,
          wordCount: added,
          reviewCount: logsAdded,
          skippedCount: skipped,
        );
      } finally {
        srcDb.dispose();
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }
    } catch (e) {
      return ImportResult(success: false, error: '续写失败: $e');
    }
  }
}
