/// 从网络同步 - 编排仓库（施工文档 §2.4/§2.5 全流程、manifest 读写、水位、清理）
///
/// 依赖全部走抽象：[SyncStorage]（infra/sync）、[SyncSettingsStore]（secure_storage
/// 的键值抽象）、[SyncLocalStats]（review_logs 统计）、[SyncBackupGateway]
/// （backup_repository 的快照出入口）——单元测试注入 fake，不碰真网/真库。
///
/// 决策依据（D5/D6/D7，施工文档 §4）：纯手动串行接力；"新旧"判定用水位 +
/// parent 链，全程不读设备时钟；文案中性，不出现"同步/冲突"字样。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/stats.dart' show ImportResult;
import '../../domain/services/sync/sync_models.dart';
import '../../infra/sync/webdav_client.dart';
import '../database/app_database.dart';
import 'backup_repository.dart';

/// secure_storage 键值抽象（§3.3：全部走设备本地存储，绝不进 app_settings）
abstract class SyncSettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// §3.3 各键（值只存 secure_storage；应用密码绝不入日志/备份）
class SyncSettingKeys {
  static const deviceId = 'sync.device_id';
  static const deviceName = 'sync.device_name';
  static const davUrl = 'sync.dav_url';
  static const davUser = 'sync.dav_user';
  static const davPassword = 'sync.dav_password';
  static const watermarkName = 'sync.watermark_name';
  static const watermarkStats = 'sync.watermark_stats';
}

/// 本机 review_logs 统计（§3.6 两条 SQL）
abstract class SyncLocalStats {
  Future<int> reviewLogCount();
  Future<String?> lastReviewedAt();
}

/// 备份出入口抽象（复用 backup_repository 管线，不重写）
abstract class SyncBackupGateway {
  /// 生成快照 zip（内部含 sqlite backup API + quick_check）
  Future<Uint8List> exportBytes();

  /// 把字节落临时文件（供 import 的文件路径入参）
  Future<String> writeTempFile(Uint8List bytes);

  /// 覆盖导入（重建模式）
  Future<ImportResult> import(String zipPath);
}

/// 一次同步操作的结果
class SyncOpResult {
  final bool ok;
  final bool needsConfirmation; // true：需要用户确认后带 confirmed=true 重调
  final String message; // 确认文案 / 成功信息 / 错误文案
  final int? ownSnapshotsKept; // 上传成功后本机快照保留数（X/10）
  final int? totalRemoteSnapshots; // 云端快照总数（>20 时 UI 提示手动处理）

  const SyncOpResult({
    required this.ok,
    this.needsConfirmation = false,
    required this.message,
    this.ownSnapshotsKept,
    this.totalRemoteSnapshots,
  });

  const SyncOpResult.success(this.message,
      {this.ownSnapshotsKept, this.totalRemoteSnapshots})
      : ok = true,
        needsConfirmation = false;

  const SyncOpResult.failure(this.message)
      : ok = false,
        needsConfirmation = false,
        ownSnapshotsKept = null,
        totalRemoteSnapshots = null;

  const SyncOpResult.confirmRequired(this.message)
      : ok = false,
        needsConfirmation = true,
        ownSnapshotsKept = null,
        totalRemoteSnapshots = null;
}

class SyncRepository {
  /// 固定远端目录（v2.0 不开放自定义）
  static const remoteDir = '/wordmem';
  static const _manifestPath = '$remoteDir/manifest.json';
  static const _namePattern = r'^wordmem_\d{8}T\d{6}Z\.zip$';
  /// 本机快照保留上限（D3）
  static const keepOwnSnapshots = 10;
  /// 单次清理最多删除份数（D3）
  static const maxCleanupPerRun = 2;
  /// 云端总条目超过此数提示用户手动处理（§3.4）
  static const totalSnapshotsHint = 20;

  final SyncStorage storage;
  final SyncSettingsStore settings;
  final SyncLocalStats localStats;
  final SyncBackupGateway backup;
  final String appVersion;

  /// 最近一次 fetchManifest 是否触发了降级重建（UI 顶部提示"云端索引已自动修复"）
  bool lastManifestRepaired = false;

  SyncRepository({
    required this.storage,
    required this.settings,
    required this.localStats,
    required this.backup,
    this.appVersion = AppConstants.appVersion,
  });

  // ─────────────────────── 配置 / 连通性（§2.3）───────────────────────

  /// 测试连接：ping → mkdir → 写 /.conn_test → 读回比对 → 删除。
  /// 失败抛 [SyncStorageException]，由 UI 按 §5 映射文案。
  Future<void> testConnection() async {
    await storage.ping();
    await storage.mkdir(remoteDir);
    final payload =
        utf8.encode('wordmem-conn-${DateTime.now().toUtc().toIso8601String()}');
    const testPath = '$remoteDir/.conn_test';
    await storage.write(testPath, Uint8List.fromList(payload));
    final Uint8List back;
    try {
      back = await storage.read(testPath);
    } catch (_) {
      throw const SyncStorageException(SyncErrorCode.incompatible,
          debug: 'conn-test read');
    }
    if (!_bytesEqual(back, payload)) {
      throw const SyncStorageException(SyncErrorCode.incompatible,
          debug: 'conn-test mismatch');
    }
    await storage.delete(testPath);
  }

  // ─────────────────────── manifest（§3.2）───────────────────────

  /// 拉取 manifest：不存在 → null；解析失败 / schema 不识别 → 降级重建
  /// （PROPFIND 按文件名重建，sha256/parent/stats 置 null）并写回，
  /// 同时置 [lastManifestRepaired]（§5：顶部提示"云端索引已自动修复"）。
  Future<SyncManifest?> fetchManifest() async {
    lastManifestRepaired = false;
    final Uint8List raw;
    try {
      raw = await storage.read(_manifestPath);
    } on SyncStorageException catch (e) {
      if (e.code == SyncErrorCode.notFound) return null;
      rethrow;
    }
    try {
      return SyncManifest.fromJsonString(utf8.decode(raw));
    } on FormatException {
      return await _rebuildManifest();
    } on TypeError {
      return await _rebuildManifest();
    }
  }

  Future<SyncManifest> _rebuildManifest() async {
    final files = await storage.list(remoteDir);
    final entries = <SnapshotEntry>[];
    final re = RegExp(_namePattern);
    for (final f in files) {
      if (f.isDir || !re.hasMatch(f.name)) continue;
      entries.add(SnapshotEntry(
        name: f.name,
        sha256: null,
        size: f.size,
        deviceId: null,
        deviceName: null,
        parent: null,
        stats: null,
        uploadedAt: _timeFromName(f.name)?.toIso8601String(),
        appVersion: null,
      ));
    }
    entries.sort((a, b) => (b.uploadedTime ?? DateTime.utc(0))
        .compareTo(a.uploadedTime ?? DateTime.utc(0)));
    final manifest = SyncManifest(
      snapshots: entries,
      latest: entries.isNotEmpty ? entries.first.name : null,
    );
    // 写回（尽力而为：失败不阻断，下次还会重建）
    try {
      await storage.write(
          _manifestPath, Uint8List.fromList(utf8.encode(manifest.toJsonString())));
    } on SyncStorageException {
      // ignore
    }
    lastManifestRepaired = true;
    return manifest;
  }

  static DateTime? _timeFromName(String name) {
    final entry = SnapshotEntry(name: name);
    return entry.uploadedTime;
  }

  // ─────────────────────── 上传（§2.4）───────────────────────

  /// 上传快照。首次调用 [confirmed]=false：若触发检查 A，返回
  /// needsConfirmation + 确认文案（不发任何写请求）；用户确认后带
  /// [confirmed]=true 重调。顺序不变量（§8.6）：先传 zip → 再改 manifest
  /// → 再清理；任何一步失败，远端都不会出现指向不存在文件的 latest。
  Future<SyncOpResult> upload({bool confirmed = false}) async {
    try {
      final deviceId = await settings.read(SyncSettingKeys.deviceId);
      final deviceName = await settings.read(SyncSettingKeys.deviceName);
      final watermark = await settings.read(SyncSettingKeys.watermarkName);

      final manifest = await fetchManifest();

      // 防呆检查 A（§4.2）
      if (!confirmed) {
        final decision = SyncChecks.beforeUpload(
          manifest: manifest,
          watermarkName: watermark,
        );
        if (decision.needsConfirm) {
          return SyncOpResult.confirmRequired(decision.message);
        }
      }

      // 生成快照（backup_repository.exportBytes，内含 sqlite backup + quick_check）
      final bytes = await backup.exportBytes();
      if (bytes.isEmpty) {
        return const SyncOpResult.failure('备份生成失败，请重试');
      }
      final sha = sha256.convert(bytes).toString();
      final now = DateTime.now().toUtc();
      final name =
          'wordmem_${_fmtUtcName(now)}.zip';
      final reviewCount = await localStats.reviewLogCount();
      final lastAt = await localStats.lastReviewedAt();

      // 1) 先传 zip
      await storage.write('$remoteDir/$name', bytes);

      // 2) 再改 manifest（读-改-写 + 回读校验，最多 3 次）
      final base =
          manifest ?? const SyncManifest(snapshots: [], latest: null);
      final entry = SnapshotEntry(
        name: name,
        sha256: sha,
        size: bytes.length,
        deviceId: deviceId,
        deviceName: deviceName,
        parent: watermark,
        stats: SyncStats(reviewLogs: reviewCount, lastReviewedAt: lastAt),
        uploadedAt: now.toIso8601String(),
        appVersion: appVersion,
      );
      final updated = base.withAdded(entry);
      var manifestSaved = false;
      SyncStorageException? lastErr;
      for (var attempt = 0; attempt < 3 && !manifestSaved; attempt++) {
        try {
          await storage.write(_manifestPath,
              Uint8List.fromList(utf8.encode(updated.toJsonString())));
          final back = SyncManifest.fromJsonString(
              utf8.decode(await storage.read(_manifestPath)));
          manifestSaved = back.latest == name;
        } on FormatException {
          manifestSaved = false;
        } on SyncStorageException catch (e) {
          lastErr = e;
          manifestSaved = false;
        }
      }
      if (!manifestSaved) {
        // zip 已在云端但未登入 manifest：latest 仍指向旧快照，不变量保持
        if (lastErr != null) throw lastErr; // 保留原错误码走 §5 文案
        return const SyncOpResult.failure('云端索引更新失败，请稍后再试（备份文件已上传，下次上传会自动补登）');
      }

      // 3) 清理旧快照（§3.4）
      final prune = await _pruneOwnSnapshots(updated, deviceId ?? '');

      // 记录水位（§3.3）
      await settings.write(SyncSettingKeys.watermarkName, name);
      await settings.write(
          SyncSettingKeys.watermarkStats,
          jsonEncode(SyncStats(reviewLogs: reviewCount, lastReviewedAt: lastAt)
              .toJson()));

      final kept = (prune.$3) ?? keepOwnSnapshots;
      final mb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      return SyncOpResult.success(
        '已上传（$mb MB，云端保留 $kept/$keepOwnSnapshots 份）',
        ownSnapshotsKept: kept,
        totalRemoteSnapshots: prune.$1,
      );
    } on SyncStorageException catch (e) {
      return SyncOpResult.failure(syncErrorText(e.code));
    } catch (_) {
      return const SyncOpResult.failure('上传失败，请稍后再试');
    }
  }

  /// 清理规则（D3）：只删本机（deviceId 匹配）创建的快照，按 uploaded_at 倒序，
  /// 只删第 [keepOwnSnapshots] 份起且单次最多 [maxCleanupPerRun] 个；
  /// 其他设备的文件一律不碰。返回 (云端总条目数, 本次删除数, 本机保留数)。
  Future<(int, int, int?)> _pruneOwnSnapshots(
      SyncManifest manifest, String deviceId) async {
    final mine = manifest.snapshots
        .where((e) => e.deviceId != null && e.deviceId == deviceId)
        .toList()
      ..sort((a, b) => (b.uploadedTime ?? DateTime.utc(0))
          .compareTo(a.uploadedTime ?? DateTime.utc(0)));

    var deleted = 0;
    var working = manifest;
    if (mine.length > keepOwnSnapshots) {
      final over = mine.skip(keepOwnSnapshots).toList();
      for (final e in over) {
        if (deleted >= maxCleanupPerRun) break;
        try {
          await storage.delete('$remoteDir/${e.name}');
        } on SyncStorageException catch (err) {
          if (err.code == SyncErrorCode.network ||
              err.code == SyncErrorCode.rateLimited) {
            break; // 网络原因中断清理，下次上传再继续
          }
          // 单个文件删除失败（如已不存在）继续删下一个
          continue;
        }
        working = working.without(e.name);
        deleted++;
      }
      if (deleted > 0) {
        await storage.write(_manifestPath,
            Uint8List.fromList(utf8.encode(working.toJsonString())));
      }
    }

    final keptMine = mine.length - deleted;
    return (working.snapshots.length, deleted, keptMine);
  }

  // ─────────────────────── 下载（§2.5）───────────────────────

  /// 下载恢复。默认取 latest；[snapshotName] 可换选旧版（高级列表）。
  /// 防呆检查 B（§4.3）触发时返回 needsConfirmation。
  Future<SyncOpResult> download({
    String? snapshotName,
    bool confirmed = false,
  }) async {
    try {
      final manifest = await fetchManifest();
      if (manifest == null || manifest.snapshots.isEmpty) {
        return const SyncOpResult.failure('云端还没有任何备份');
      }
      final targetName = snapshotName ?? manifest.latest;
      final entry = manifest.entry(targetName);
      if (entry == null) {
        return const SyncOpResult.failure('云端索引与文件不一致，请刷新后重试');
      }

      // 防呆检查 B（§4.3）：本机进度 vs 水位
      if (!confirmed) {
        final count = await localStats.reviewLogCount();
        final lastAt = await localStats.lastReviewedAt();
        final wmStats = await _readWatermarkStats();
        final decision = SyncChecks.beforeDownload(
          localReviewCount: count,
          watermark: wmStats,
          localLastReviewedAt: lastAt,
        );
        if (decision.needsConfirm) {
          return SyncOpResult.confirmRequired(decision.message);
        }
      }

      // 下载 + sha256 校验
      final bytes = await storage.read('$remoteDir/${entry.name}');
      final expected = entry.sha256;
      if (expected != null && sha256.convert(bytes).toString() != expected) {
        return const SyncOpResult.failure(
            '备份文件校验失败，可能在传输中损坏，请重试；若反复出现请删除该快照后重新上传');
      }
      if (bytes.isEmpty) {
        return const SyncOpResult.failure('备份文件校验失败，可能在传输中损坏，请重试');
      }

      // 落临时文件 → 覆盖导入（backup_repository.import，文件路径入参）
      final tmpPath = await backup.writeTempFile(bytes);
      final result = await backup.import(tmpPath);
      if (!result.success) {
        return SyncOpResult.failure('恢复失败：${result.error ?? '未知错误'}');
      }

      // 成功 → 记录水位
      await settings.write(SyncSettingKeys.watermarkName, entry.name);
      final restoredCount = result.reviewCount ?? 0;
      await settings.write(
          SyncSettingKeys.watermarkStats,
          jsonEncode(SyncStats(reviewLogs: restoredCount).toJson()));

      final when = entry.uploadedTime;
      final whenText = when != null
          ? '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}'
              ' ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
          : entry.name;
      return SyncOpResult.success('已恢复到 $whenText 的备份');
    } on SyncStorageException catch (e) {
      return SyncOpResult.failure(syncErrorText(e.code));
    } catch (_) {
      return const SyncOpResult.failure('下载失败，请稍后再试');
    }
  }

  // ─────────────────────── 查询 ────────────────────────

  /// 高级区快照列表（时间倒序）。manifest 缺失时按目录 listing 临时推导
  /// （不写回），条目缺 sha256/stats（降级态）由 UI 显示"信息有限"。
  Future<List<SnapshotEntry>> remoteSnapshots() async {
    final manifest = await fetchManifest();
    if (manifest != null) return manifest.snapshots;
    final files = await storage.list(remoteDir);
    final re = RegExp(_namePattern);
    final entries = <SnapshotEntry>[];
    for (final f in files) {
      if (f.isDir || !re.hasMatch(f.name)) continue;
      entries.add(SnapshotEntry(
        name: f.name,
        size: f.size,
        uploadedAt: _timeFromName(f.name)?.toIso8601String(),
      ));
    }
    entries.sort((a, b) => (b.uploadedTime ?? DateTime.utc(0))
        .compareTo(a.uploadedTime ?? DateTime.utc(0)));
    return entries;
  }

  // ─────────────────────── 内部 ────────────────────────

  Future<SyncStats?> _readWatermarkStats() async {
    final raw = await settings.read(SyncSettingKeys.watermarkStats);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SyncStats.fromJsonOrNull(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static String _fmtUtcName(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}'
      'T${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}Z';

  static bool _bytesEqual(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 本机统计的正式实现（§3.6 两条 SQL；reviewed_at 有索引 idx_rl_time）
class DbSyncLocalStats implements SyncLocalStats {
  final AppDatabase _db;
  DbSyncLocalStats(this._db);

  @override
  Future<int> reviewLogCount() async {
    return _db.vocab
        .select('SELECT COUNT(*) AS c FROM review_logs')
        .first['c'] as int;
  }

  @override
  Future<String?> lastReviewedAt() async {
    final row = _db.vocab
        .select('SELECT MAX(reviewed_at) AS t FROM review_logs')
        .first;
    return row['t'] as String?;
  }
}

/// 备份出入口的正式实现：全部委托 BackupRepository（唯一数据出入口，不重写）
class BackupRepositoryGateway implements SyncBackupGateway {
  final BackupRepository _repo;
  BackupRepositoryGateway(this._repo);

  @override
  Future<Uint8List> exportBytes() => _repo.exportBytes();

  @override
  Future<String> writeTempFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(
        dir.path, 'wordmem_sync_${DateTime.now().millisecondsSinceEpoch}.zip'));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<ImportResult> import(String zipPath) => _repo.import(zipPath);
}
