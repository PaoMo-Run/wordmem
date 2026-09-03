// sync_repository 单测：fake 全注入（storage / settings / stats / backup），不碰真网
// 施工文档 §8.1 / §8.2 / §8.5 / §8.6
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/data/repositories/sync_repository.dart';
import 'package:wordmem/domain/models/stats.dart' show ImportResult;
import 'package:wordmem/domain/services/sync/sync_models.dart';
import 'package:wordmem/infra/sync/webdav_client.dart';

// ─────────────────────────── fakes ───────────────────────────

class FakeSyncStorage implements SyncStorage {
  /// 完整路径 → 内容
  final files = <String, Uint8List>{};
  /// 操作日志（按发生顺序），断言"先传 zip → 再改 manifest → 再清理"
  final ops = <String>[];
  /// 每次调用路径含 key 的**写操作**时抛出（模拟服务端 PUT 失败）
  final Map<String, SyncStorageException> failAlways = {};

  Uint8List _u(String s) => Uint8List.fromList(utf8.encode(s));

  void seedManifest(SyncManifest m) =>
      files['/wordmem/manifest.json'] = _u(m.toJsonString());

  void seedZip(String name, {String? deviceId, String? uploadedAt, int size = 3}) {
    files['/wordmem/$name'] = _u('ZIP:$name');
    // 无 manifest 时的裸 zip 种子用不到条目属性；有 manifest 时由测试自建条目
  }

  void failWritesContaining(String fragment, SyncStorageException e) =>
      failAlways[fragment] = e;

  @override
  Future<void> delete(String path) async {
    ops.add('delete:$path');
    if (files.remove(path) == null) {
      throw const SyncStorageException(SyncErrorCode.notFound, debug: 'delete');
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    ops.add('read:$path');
    final f = files[path];
    if (f == null) {
      throw const SyncStorageException(SyncErrorCode.notFound, debug: 'read');
    }
    return f;
  }

  @override
  Future<List<RemoteFile>> list(String dirPath) async {
    ops.add('list:$dirPath');
    final prefix = dirPath.endsWith('/') ? dirPath : '$dirPath/';
    final out = <RemoteFile>[];
    files.forEach((path, bytes) {
      if (!path.startsWith(prefix)) return;
      final rest = path.substring(prefix.length);
      if (rest.contains('/')) return; // 子目录内容不列
      out.add(RemoteFile(
          name: rest, isDir: false, size: bytes.length));
    });
    return out;
  }

  @override
  Future<void> mkdir(String path) async {
    ops.add('mkdir:$path');
  }

  @override
  Future<void> ping() async {
    ops.add('ping');
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    ops.add('write:$path');
    failAlways.forEach((frag, e) {
      if (path.contains(frag)) throw e;
    });
    files[path] = bytes;
  }
}

class FakeSettings implements SyncSettingsStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

class FakeStats implements SyncLocalStats {
  int count = 0;
  String? lastAt;
  @override
  Future<int> reviewLogCount() async => count;
  @override
  Future<String?> lastReviewedAt() async => lastAt;
}

class FakeBackup implements SyncBackupGateway {
  Uint8List exported = Uint8List.fromList(utf8.encode('FAKEZIPDATA'));
  ImportResult importResult =
      const ImportResult(success: true, wordCount: 10, reviewCount: 100);
  final importedPaths = <String>[];

  @override
  Future<Uint8List> exportBytes() async => exported;

  @override
  Future<String> writeTempFile(Uint8List bytes) async => '/tmp/fake.zip';

  @override
  Future<ImportResult> import(String zipPath) async {
    importedPaths.add(zipPath);
    return importResult;
  }
}

// ─────────────────────────── helpers ───────────────────────────

const devA = 'dev-a-uuid';
const devB = 'dev-b-uuid';

SnapshotEntry ownEntry(String name, {String? parent, SyncStats? stats}) =>
    SnapshotEntry(
      name: name,
      sha256: null,
      size: 3,
      deviceId: devA,
      deviceName: '本机',
      parent: parent,
      stats: stats,
      uploadedAt: _uploadedAtOf(name),
      appVersion: '2.1.3',
    );

String _uploadedAtOf(String name) {
  final t = SnapshotEntry(name: name).uploadedTime;
  return t?.toIso8601String() ?? '2026-09-01T00:00:00Z';
}

SyncRepository buildRepo({
  required FakeSyncStorage storage,
  required FakeSettings settings,
  required FakeStats stats,
  required FakeBackup backup,
}) {
  settings.map[SyncSettingKeys.deviceId] = devA;
  settings.map[SyncSettingKeys.deviceName] = '本机';
  return SyncRepository(
    storage: storage,
    settings: settings,
    localStats: stats,
    backup: backup,
    appVersion: '2.1.3',
  );
}

SyncManifest manifestOf(List<SnapshotEntry> entries, String? latest) =>
    SyncManifest(snapshots: entries, latest: latest);

// ─────────────────────────── tests ───────────────────────────

void main() {
  group('fetchManifest（§8.1 / §8.2）', () {
    test('云端无 manifest → null', () async {
      final repo = buildRepo(
          storage: FakeSyncStorage(),
          settings: FakeSettings(),
          stats: FakeStats(),
          backup: FakeBackup());
      expect(await repo.fetchManifest(), isNull);
      expect(repo.lastManifestRepaired, isFalse);
    });

    test('manifest 损坏（非法 JSON）→ PROPFIND 重建 + 写回 + 修复标记', () async {
      final storage = FakeSyncStorage();
      storage.files['/wordmem/manifest.json'] =
          Uint8List.fromList(utf8.encode('not json at all'));
      storage.seedZip('wordmem_20260901T000000Z.zip');
      final repo = buildRepo(
          storage: storage,
          settings: FakeSettings(),
          stats: FakeStats(),
          backup: FakeBackup());

      final m = await repo.fetchManifest();
      expect(m, isNotNull);
      expect(m!.snapshots.length, 1);
      expect(m.snapshots.first.name, 'wordmem_20260901T000000Z.zip');
      expect(m.snapshots.first.sha256, isNull); // 降级重建态
      expect(m.latest, 'wordmem_20260901T000000Z.zip');
      expect(repo.lastManifestRepaired, isTrue);
      // 已写回
      expect(storage.files.containsKey('/wordmem/manifest.json'), isTrue);
    });

    test('schema 版本不识别 → 同样走降级重建', () async {
      final storage = FakeSyncStorage();
      storage.files['/wordmem/manifest.json'] = Uint8List.fromList(
          utf8.encode('{"schema": 99, "snapshots": []}'));
      storage.seedZip('wordmem_20260902T000000Z.zip');
      final repo = buildRepo(
          storage: storage,
          settings: FakeSettings(),
          stats: FakeStats(),
          backup: FakeBackup());
      final m = await repo.fetchManifest();
      expect(repo.lastManifestRepaired, isTrue);
      expect(m!.snapshots.first.name, 'wordmem_20260902T000000Z.zip');
    });
  });

  group('upload（§2.4 / §8.6 顺序不变量 / §8.5 清理规则）', () {
    test('首次上传：先传 zip → 再改 manifest → 记录水位', () async {
      final storage = FakeSyncStorage();
      final settings = FakeSettings();
      final stats = FakeStats()..count = 1205;
      final repo = buildRepo(
          storage: storage, settings: settings, stats: stats, backup: FakeBackup());

      final r = await repo.upload();
      expect(r.ok, isTrue, reason: r.message);
      expect(r.message, contains('已上传'));

      // 顺序不变量：zip 的 write 在 manifest 的 write 之前
      final zipWrites = storage.ops
          .indexed
          .where((x) => x.$2.startsWith('write:/wordmem/wordmem_2'))
          .toList();
      final manifestWriteIdx = storage.ops
          .indexed
          .firstWhere((x) => x.$2 == 'write:/wordmem/manifest.json')
          .$1;
      expect(zipWrites, isNotEmpty);
      expect(zipWrites.first.$1, lessThan(manifestWriteIdx));

      // manifest latest 指向新快照且不指向不存在文件
      final m = SyncManifest.fromJsonString(
          utf8.decode(storage.files['/wordmem/manifest.json']!));
      expect(m.latest, isNotNull);
      expect(storage.files.containsKey('/wordmem/${m.latest}'), isTrue);
      expect(m.snapshots.first.parent, isNull); // 首次上传 parent=null
      expect(m.snapshots.first.stats!.reviewLogs, 1205);
      expect(m.snapshots.first.appVersion, '2.1.3');

      // 水位已记录
      expect(settings.map[SyncSettingKeys.watermarkName], m.latest);
      expect(settings.map[SyncSettingKeys.watermarkStats], isNotNull);
    });

    test('检查 A：latest ≠ 水位 → 返回确认，未写任何数据', () async {
      final storage = FakeSyncStorage();
      storage.seedZip('wordmem_20260801T000000Z.zip');
      storage.seedZip('wordmem_20260901T000000Z.zip');
      storage.seedManifest(manifestOf([
        ownEntry('wordmem_20260801T000000Z.zip'),
        const SnapshotEntry(
            name: 'wordmem_20260901T000000Z.zip',
            deviceId: devB,
            deviceName: '平板',
            parent: 'wordmem_20260801T000000Z.zip',
            stats: SyncStats(reviewLogs: 1300)),
      ], 'wordmem_20260901T000000Z.zip'));
      final settings = FakeSettings()
        ..map[SyncSettingKeys.watermarkName] = 'wordmem_20260801T000000Z.zip';
      final repo = buildRepo(
          storage: storage, settings: settings, stats: FakeStats(), backup: FakeBackup());

      final r = await repo.upload(confirmed: false);
      expect(r.needsConfirmation, isTrue);
      expect(r.message, contains('下载数据'));
      // 除读操作外没有写请求（zip 数量不变）
      expect(
        storage.files.keys.where((p) => p.endsWith('.zip')).length,
        2,
      );
    });

    test('confirmed=true 越过检查 A 正常上传', () async {
      final storage = FakeSyncStorage();
      storage.seedManifest(manifestOf(
          [ownEntry('wordmem_20260901T000000Z.zip')],
          'wordmem_20260901T000000Z.zip'));
      final settings = FakeSettings()
        ..map[SyncSettingKeys.watermarkName] = 'wordmem_20260901T000000Z.zip';
      final repo = buildRepo(
          storage: storage, settings: settings, stats: FakeStats(), backup: FakeBackup());

      final r = await repo.upload(confirmed: true);
      expect(r.ok, isTrue, reason: r.message);
      final m = SyncManifest.fromJsonString(
          utf8.decode(storage.files['/wordmem/manifest.json']!));
      expect(m.snapshots.length, 2);
    });

    test('清理：12 份本机快照单次最多删 2、绝不触碰他机条目', () async {
      final storage = FakeSyncStorage();
      final entries = <SnapshotEntry>[];
      // 11 份旧本机快照（2026-08-20 时 00..10，时间戳各不相同保证确定性排序）
      for (var h = 0; h < 11; h++) {
        final name =
            'wordmem_20260820T${h.toString().padLeft(2, '0')}0000Z.zip';
        storage.seedZip(name);
        entries.add(ownEntry(name));
      }
      // 1 份他机快照
      storage.seedZip('wordmem_20260825T000000Z.zip');
      entries.add(const SnapshotEntry(
          name: 'wordmem_20260825T000000Z.zip',
          deviceId: devB,
          deviceName: '平板'));
      // 水位 == 最新本机快照 → 检查 A 静默
      storage.seedManifest(manifestOf(entries, entries.last.name));
      final settings = FakeSettings()
        ..map[SyncSettingKeys.watermarkName] = entries.last.name;

      final repo = buildRepo(
          storage: storage, settings: settings, stats: FakeStats(), backup: FakeBackup());
      final r = await repo.upload(confirmed: true);
      expect(r.ok, isTrue, reason: r.message);

      // 上传后本机共 12 份 → 删最旧 2 份（单次上限），他机 1 份仍在
      expect(storage.files.containsKey('/wordmem/wordmem_20260820T000000Z.zip'),
          isFalse);
      expect(storage.files.containsKey('/wordmem/wordmem_20260820T010000Z.zip'),
          isFalse);
      expect(storage.files.containsKey('/wordmem/wordmem_20260820T020000Z.zip'),
          isTrue);
      expect(
          storage.files
              .containsKey('/wordmem/wordmem_20260825T000000Z.zip'),
          isTrue);

      final m = SyncManifest.fromJsonString(
          utf8.decode(storage.files['/wordmem/manifest.json']!));
      expect(m.snapshots.length, 11); // 12 - 2 + 1(新) - ... 实际：11旧+1他机+1新-2删=11
      expect(r.ownSnapshotsKept, 10);
      // manifest 中不再含被删条目
      expect(m.entry('wordmem_20260820T000000Z.zip'), isNull);
      expect(m.entry('wordmem_20260820T010000Z.zip'), isNull);
    });

    test('manifest 写入持续失败 → 上传报错，latest 不指向不存在文件', () async {
      final storage = FakeSyncStorage();
      storage.seedZip('wordmem_20260901T000000Z.zip');
      storage.seedManifest(manifestOf(
          [ownEntry('wordmem_20260901T000000Z.zip')],
          'wordmem_20260901T000000Z.zip'));
      final settings = FakeSettings()
        ..map[SyncSettingKeys.watermarkName] = 'wordmem_20260901T000000Z.zip';
      storage.failWritesContaining('manifest.json',
          const SyncStorageException(SyncErrorCode.server, debug: 'put'));
      final repo = buildRepo(
          storage: storage, settings: settings, stats: FakeStats(), backup: FakeBackup());

      final r = await repo.upload(confirmed: true);
      expect(r.ok, isFalse);
      expect(r.message, contains('坚果云服务异常')); // 保留原始错误码映射
      // 不变量：manifest latest 仍指向旧快照（旧文件存在）
      final m = SyncManifest.fromJsonString(
          utf8.decode(storage.files['/wordmem/manifest.json']!));
      expect(m.latest, 'wordmem_20260901T000000Z.zip');
      expect(storage.files.containsKey('/wordmem/${m.latest}'), isTrue);
      // 水位未更新
      expect(settings.map[SyncSettingKeys.watermarkName],
          'wordmem_20260901T000000Z.zip');
    });

    test('存储层认证失败 → 错误文案按 §5 映射', () async {
      final storage = FakeSyncStorage();
      storage.failWritesContaining('.json',
          const SyncStorageException(SyncErrorCode.auth, statusCode: 401));
      final repo = buildRepo(
          storage: storage, settings: FakeSettings(), stats: FakeStats(), backup: FakeBackup());
      final r = await repo.upload(confirmed: true);
      expect(r.ok, isFalse);
      expect(r.message, syncErrorText(SyncErrorCode.auth));
    });
  });

  group('download（§2.5 / 检查 B）', () {
    test('云端没有任何备份 → 提示语', () async {
      final repo = buildRepo(
          storage: FakeSyncStorage(),
          settings: FakeSettings(),
          stats: FakeStats(),
          backup: FakeBackup());
      final r = await repo.download();
      expect(r.ok, isFalse);
      expect(r.message, '云端还没有任何备份');
    });

    test('检查 B：本机进度超水位 → 确认；确认后正常恢复并记录水位', () async {
      final storage = FakeSyncStorage();
      final settings = FakeSettings();
      final stats = FakeStats()..count = 1300; // 超过水位 1200
      final backup = FakeBackup();

      final zipBytes = Uint8List.fromList(utf8.encode('FAKEZIPDATA'));
      // manifest 里记录的 sha 必须是云端 zip 实际内容的 sha
      backup.exported = zipBytes;
      final sha = sha256.convert(zipBytes).toString();
      storage.files['/wordmem/wordmem_20260903T141530Z.zip'] = zipBytes;
      storage.seedManifest(manifestOf([
        SnapshotEntry(
            name: 'wordmem_20260903T141530Z.zip',
            sha256: sha,
            deviceId: devB,
            parent: null,
            stats: const SyncStats(reviewLogs: 1205)),
      ], 'wordmem_20260903T141530Z.zip'));
      settings.map[SyncSettingKeys.watermarkName] = 'wordmem_20260801T000000Z.zip';
      settings.map[SyncSettingKeys.watermarkStats] =
          jsonEncode(const SyncStats(reviewLogs: 1200).toJson());

      final repo = buildRepo(
          storage: storage, settings: settings, stats: stats, backup: backup);

      final check = await repo.download(confirmed: false);
      expect(check.needsConfirmation, isTrue);
      expect(check.message, contains('上传数据'));

      final r = await repo.download(confirmed: true);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.message, contains('已恢复到'));
      expect(r.message, contains('2026-09-03 14:15'));
      expect(backup.importedPaths, ['/tmp/fake.zip']);
      // 水位更新为所恢复快照
      expect(settings.map[SyncSettingKeys.watermarkName],
          'wordmem_20260903T141530Z.zip');
      final wm =
          SyncStats.fromJsonOrNull(jsonDecode(settings.map[SyncSettingKeys.watermarkStats]!));
      expect(wm!.reviewLogs, 100); // import 返回的 reviewCount
    });

    test('检查 B：空库静默通过', () async {
      final storage = FakeSyncStorage();
      storage.seedZip('wordmem_20260903T141530Z.zip');
      storage.seedManifest(manifestOf([
        const SnapshotEntry(name: 'wordmem_20260903T141530Z.zip', sha256: null),
      ], 'wordmem_20260903T141530Z.zip'));
      final backup = FakeBackup();
      final repo = buildRepo(
          storage: storage,
          settings: FakeSettings(),
          stats: FakeStats()..count = 0,
          backup: backup);
      final r = await repo.download();
      expect(r.ok, isTrue, reason: r.message);
      expect(backup.importedPaths, isNotEmpty);
    });

    test('sha256 不匹配 → 校验失败文案', () async {
      final storage = FakeSyncStorage();
      storage.seedZip('wordmem_20260903T141530Z.zip');
      storage.seedManifest(manifestOf([
        const SnapshotEntry(
            name: 'wordmem_20260903T141530Z.zip', sha256: 'deadbeef'),
      ], 'wordmem_20260903T141530Z.zip'));
      final repo = buildRepo(
          storage: storage,
          settings: FakeSettings(),
          stats: FakeStats()..count = 0,
          backup: FakeBackup());
      final r = await repo.download(confirmed: true);
      expect(r.ok, isFalse);
      expect(r.message, contains('校验失败'));
    });

    test('快照文件已被清理 → notFound 文案', () async {
      final storage = FakeSyncStorage();
      storage.seedManifest(manifestOf([
        const SnapshotEntry(
            name: 'wordmem_20260903T141530Z.zip', sha256: null),
      ], 'wordmem_20260903T141530Z.zip'));
      final repo = buildRepo(
          storage: storage,
          settings: FakeSettings(),
          stats: FakeStats()..count = 0,
          backup: FakeBackup());
      final r = await repo.download(confirmed: true);
      expect(r.ok, isFalse);
      expect(r.message, syncErrorText(SyncErrorCode.notFound));
    });

    test('导入失败 → 透传 backup 错误口径', () async {
      final storage = FakeSyncStorage();
      storage.seedZip('wordmem_20260903T141530Z.zip');
      storage.seedManifest(manifestOf([
        const SnapshotEntry(name: 'wordmem_20260903T141530Z.zip', sha256: null),
      ], 'wordmem_20260903T141530Z.zip'));
      final backup = FakeBackup()
        ..importResult = const ImportResult(success: false, error: '备份文件格式不正确');
      final repo = buildRepo(
          storage: storage,
          settings: FakeSettings(),
          stats: FakeStats()..count = 0,
          backup: backup);
      final r = await repo.download(confirmed: true);
      expect(r.ok, isFalse);
      expect(r.message, contains('备份文件格式不正确'));
    });
  });

  group('testConnection（§2.3 写读回环）', () {
    test('写读一致 → 通过且测试文件已删除', () async {
      final storage = FakeSyncStorage();
      final repo = buildRepo(
          storage: storage, settings: FakeSettings(), stats: FakeStats(), backup: FakeBackup());
      await repo.testConnection();
      expect(storage.files.containsKey('/wordmem/.conn_test'), isFalse);
      expect(storage.ops, contains('ping'));
      expect(storage.ops, contains('mkdir:/wordmem'));
    });

    test('读回不一致 → incompatible 错误', () async {
      final storage = FakeSyncStorage();
      // read 劫持：对 .conn_test 返回篡改内容，模拟服务端写读不一致
      final repo = _RepoWithTamperedRead(storage);
      await expectLater(
        repo.testConnection(),
        throwsA(isA<SyncStorageException>()
            .having((e) => e.code, 'code', SyncErrorCode.incompatible)),
      );
    });
  });
}

/// read 时对 .conn_test 返回篡改内容（模拟服务端写读不一致）
class _RepoWithTamperedRead extends SyncRepository {
  _RepoWithTamperedRead(FakeSyncStorage storage)
      : super(
          storage: _TamperedStorage(storage),
          settings: FakeSettings(),
          localStats: FakeStats(),
          backup: FakeBackup(),
          appVersion: '2.1.3',
        );
}

class _TamperedStorage implements SyncStorage {
  final FakeSyncStorage inner;
  _TamperedStorage(this.inner);

  @override
  Future<void> delete(String path) => inner.delete(path);
  @override
  Future<List<RemoteFile>> list(String dirPath) => inner.list(dirPath);
  @override
  Future<void> mkdir(String path) => inner.mkdir(path);
  @override
  Future<void> ping() => inner.ping();
  @override
  Future<Uint8List> read(String path) async {
    if (path.endsWith('.conn_test')) {
      return Uint8List.fromList(utf8.encode('tampered'));
    }
    return inner.read(path);
  }

  @override
  Future<void> write(String path, Uint8List bytes) => inner.write(path, bytes);
}
