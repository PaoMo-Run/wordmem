// sync_models 单测：manifest 往返 / schema 降级 / 检查 A/B / parent 链 / 错误文案
// 施工文档 §8.1 / §8.3 / §8.4 / §8.7
import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/services/sync/sync_models.dart';

void main() {
  group('SyncManifest', () {
    test('json 往返保留全部字段', () {
      const m = SyncManifest(
        snapshots: [
          SnapshotEntry(
            name: 'wordmem_20260903T141530Z.zip',
            sha256: 'abc123',
            size: 12345678,
            deviceId: 'dev-a',
            deviceName: '小米13',
            parent: 'wordmem_20260902T091200Z.zip',
            stats: SyncStats(reviewLogs: 1205, lastReviewedAt: '2026-09-03T14:10:00Z'),
            uploadedAt: '2026-09-03T14:20:00Z',
            appVersion: '2.1.3',
          ),
        ],
        latest: 'wordmem_20260903T141530Z.zip',
      );
      final back = SyncManifest.fromJsonString(m.toJsonString());
      expect(back.schema, 1);
      expect(back.snapshots.length, 1);
      final e = back.snapshots.first;
      expect(e.name, 'wordmem_20260903T141530Z.zip');
      expect(e.sha256, 'abc123');
      expect(e.size, 12345678);
      expect(e.deviceId, 'dev-a');
      expect(e.deviceName, '小米13');
      expect(e.parent, 'wordmem_20260902T091200Z.zip');
      expect(e.stats!.reviewLogs, 1205);
      expect(e.stats!.lastReviewedAt, '2026-09-03T14:10:00Z');
      expect(e.appVersion, '2.1.3');
      expect(back.latest, 'wordmem_20260903T141530Z.zip');
    });

    test('schema 版本不识别 → FormatException（调用方走降级重建）', () {
      expect(
        () => SyncManifest.fromJson({'schema': 2, 'snapshots': []}),
        throwsFormatException,
      );
    });

    test('snapshots 结构非法 → FormatException', () {
      expect(
        () => SyncManifest.fromJson({'schema': 1, 'snapshots': 'oops'}),
        throwsFormatException,
      );
    });

    test('从快照名解析上传时间', () {
      const e = SnapshotEntry(name: 'wordmem_20260903T141530Z.zip');
      expect(e.uploadedTime, DateTime.utc(2026, 9, 3, 14, 15, 30));
      expect(const SnapshotEntry(name: 'random.txt').uploadedTime, isNull);
    });

    test('withAdded / without 维护 latest', () {
      const a = SnapshotEntry(name: 'a.zip', uploadedAt: '2026-09-01T00:00:00Z');
      const b = SnapshotEntry(name: 'b.zip', uploadedAt: '2026-09-02T00:00:00Z');
      var m = const SyncManifest(snapshots: [], latest: null).withAdded(a);
      expect(m.latest, 'a.zip');
      m = m.withAdded(b);
      expect(m.latest, 'b.zip');
      m = m.without('b.zip');
      expect(m.latest, 'a.zip'); // 删除 latest 后回退到时间最新剩余条目
      m = m.without('a.zip');
      expect(m.latest, isNull);
    });
  });

  group('SyncChecks.remoteHasUnseenBackup（水位 + parent 链，无时钟）', () {
    SyncManifest m(List<SnapshotEntry> entries, String? latest) =>
        SyncManifest(snapshots: entries, latest: latest);

    test('无 manifest / 无 latest → false', () {
      expect(
          SyncChecks.remoteHasUnseenBackup(manifest: null, watermarkName: null),
          isFalse);
      expect(
          SyncChecks.remoteHasUnseenBackup(
              manifest: m([], null), watermarkName: null),
          isFalse);
    });

    test('latest == 水位 → false', () {
      final manifest = m(
          [const SnapshotEntry(name: 'w.zip', parent: null)], 'w.zip');
      expect(
        SyncChecks.remoteHasUnseenBackup(
            manifest: manifest, watermarkName: 'w.zip'),
        isFalse,
      );
    });

    test('latest 的 parent 链上出现水位 → true（他机在水位之后接力）', () {
      final manifest = m([
        const SnapshotEntry(name: 'w.zip'),
        const SnapshotEntry(name: 'new.zip', parent: 'w.zip'),
      ], 'new.zip');
      expect(
        SyncChecks.remoteHasUnseenBackup(
            manifest: manifest, watermarkName: 'w.zip'),
        isTrue,
      );
    });

    test('latest 是他机根（parent==null）→ true', () {
      final manifest = m([
        const SnapshotEntry(name: 'w.zip'),
        const SnapshotEntry(name: 'root.zip', parent: null),
      ], 'root.zip');
      expect(
        SyncChecks.remoteHasUnseenBackup(
            manifest: manifest, watermarkName: 'w.zip'),
        isTrue,
      );
    });

    test('parent 链断裂（水位快照已被清理）→ true（信息不足宁可多问）', () {
      final manifest = m([
        const SnapshotEntry(name: 'new.zip', parent: 'pruned.zip'),
      ], 'new.zip');
      expect(
        SyncChecks.remoteHasUnseenBackup(
            manifest: manifest, watermarkName: 'w.zip'),
        isTrue,
      );
    });
  });

  group('SyncChecks.beforeUpload（检查 A，§4.2）', () {
    test('manifest 不存在 → 静默', () {
      final d = SyncChecks.beforeUpload(manifest: null, watermarkName: null);
      expect(d.needsConfirm, isFalse);
    });

    test('水位 == latest → 静默', () {
      const manifest = SyncManifest(
          snapshots: [SnapshotEntry(name: 'w.zip')], latest: 'w.zip');
      final d = SyncChecks.beforeUpload(
          manifest: manifest, watermarkName: 'w.zip');
      expect(d.needsConfirm, isFalse);
    });

    test('latest ≠ 水位 → 确认，文案含设备名与复习条数', () {
      const manifest = SyncManifest(
        snapshots: [
          SnapshotEntry(
              name: 'new.zip',
              parent: 'w.zip',
              deviceName: '小米13',
              stats: SyncStats(reviewLogs: 1300)),
          SnapshotEntry(name: 'w.zip'),
        ],
        latest: 'new.zip',
      );
      final d = SyncChecks.beforeUpload(
          manifest: manifest, watermarkName: 'w.zip');
      expect(d.needsConfirm, isTrue);
      expect(d.message, contains('小米13'));
      expect(d.message, contains('1300'));
      expect(d.message, contains('下载数据'));
    });

    test('降级重建态（stats/device 缺失）→ 确认但不做新旧断言', () {
      const manifest = SyncManifest(
        snapshots: [SnapshotEntry(name: 'new.zip', sha256: null)],
        latest: 'new.zip',
      );
      final d = SyncChecks.beforeUpload(
          manifest: manifest, watermarkName: 'w.zip');
      expect(d.needsConfirm, isTrue);
      expect(d.message, isNot(contains('共 ')));
    });
  });

  group('SyncChecks.beforeDownload（检查 B，§4.3）', () {
    test('本机无学习记录（空库）→ 静默', () {
      final d = SyncChecks.beforeDownload(localReviewCount: 0, watermark: null);
      expect(d.needsConfirm, isFalse);
    });

    test('计数未超水位且时间不晚于水位 → 静默', () {
      const wm = SyncStats(reviewLogs: 1205, lastReviewedAt: '2026-09-03T10:00:00Z');
      final d = SyncChecks.beforeDownload(
        localReviewCount: 1205,
        watermark: wm,
        localLastReviewedAt: '2026-09-03T09:00:00Z',
      );
      expect(d.needsConfirm, isFalse);
    });

    test('计数超水位 → 确认（文案含本机条数）', () {
      const wm = SyncStats(reviewLogs: 1200);
      final d = SyncChecks.beforeDownload(localReviewCount: 1205, watermark: wm);
      expect(d.needsConfirm, isTrue);
      expect(d.message, contains('1205'));
      expect(d.message, contains('上传数据'));
    });

    test('计数相同但本机最新复习时间晚于水位 → 确认', () {
      const wm = SyncStats(reviewLogs: 100, lastReviewedAt: '2026-09-01T00:00:00Z');
      final d = SyncChecks.beforeDownload(
        localReviewCount: 100,
        watermark: wm,
        localLastReviewedAt: '2026-09-03T00:00:00Z',
      );
      expect(d.needsConfirm, isTrue);
    });

    test('水位缺失 → 确认但文案无具体数字', () {
      final d = SyncChecks.beforeDownload(
          localReviewCount: 500, watermark: null);
      expect(d.needsConfirm, isTrue);
      expect(d.message, contains('尚未上传'));
      expect(d.message, isNot(contains('本机共')));
    });
  });

  group('syncErrorText（§5 错误映射）', () {
    test('8 类错误均有非空文案且含关键提示', () {
      expect(syncErrorText(SyncErrorCode.auth), contains('应用密码'));
      expect(syncErrorText(SyncErrorCode.rateLimited), contains('限频'));
      expect(syncErrorText(SyncErrorCode.network), contains('网络'));
      expect(syncErrorText(SyncErrorCode.quota), contains('空间不足'));
      expect(syncErrorText(SyncErrorCode.notFound), contains('不存在'));
      expect(syncErrorText(SyncErrorCode.server), contains('稍后再试'));
      expect(syncErrorText(SyncErrorCode.incompatible), contains('兼容性'));
      expect(syncErrorText(SyncErrorCode.unknown), isNotEmpty);
    });
  });
}
