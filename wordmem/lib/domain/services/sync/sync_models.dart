/// 从网络同步 - 纯模型与判定逻辑（v2.0 快照同步）
///
/// 本文件必须保持 pure Dart（不 import Flutter / IO / 网络库），
/// 供 sync_repository 与单元测试复用。判定规格见施工文档 §4。
library;

import 'dart:convert';

/// 统计信息（manifest 快照 stats 字段 / 本机水位 stats 通用）
class SyncStats {
  final int reviewLogs;
  final String? lastReviewedAt; // ISO8601 UTC

  const SyncStats({required this.reviewLogs, this.lastReviewedAt});

  Map<String, dynamic> toJson() => {
        'review_logs': reviewLogs,
        if (lastReviewedAt != null) 'last_reviewed_at': lastReviewedAt,
      };

  static SyncStats? fromJsonOrNull(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final n = raw['review_logs'];
    if (n is! int) return null;
    final t = raw['last_reviewed_at'];
    return SyncStats(reviewLogs: n, lastReviewedAt: t is String ? t : null);
  }
}

/// 远端快照条目
class SnapshotEntry {
  final String name; // wordmem_{UTC时间戳}.zip
  final String? sha256; // 降级重建态为 null
  final int? size;
  final String? deviceId;
  final String? deviceName;
  final String? parent; // 上传者本机水位指向的快照名，首次上传为 null
  final SyncStats? stats;
  final String? uploadedAt; // ISO8601 UTC
  final String? appVersion;

  const SnapshotEntry({
    required this.name,
    this.sha256,
    this.size,
    this.deviceId,
    this.deviceName,
    this.parent,
    this.stats,
    this.uploadedAt,
    this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (sha256 != null) 'sha256': sha256,
        if (size != null) 'size': size,
        if (deviceId != null) 'device_id': deviceId,
        if (deviceName != null) 'device_name': deviceName,
        if (parent != null) 'parent': parent,
        if (stats != null) 'stats': stats!.toJson(),
        if (uploadedAt != null) 'uploaded_at': uploadedAt,
        if (appVersion != null) 'app_version': appVersion,
      };

  static SnapshotEntry? fromJsonOrNull(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    return SnapshotEntry(
      name: name,
      sha256: raw['sha256'] is String ? raw['sha256'] as String : null,
      size: raw['size'] is int ? raw['size'] as int : null,
      deviceId: raw['device_id'] is String ? raw['device_id'] as String : null,
      deviceName:
          raw['device_name'] is String ? raw['device_name'] as String : null,
      parent: raw['parent'] is String ? raw['parent'] as String : null,
      stats: SyncStats.fromJsonOrNull(raw['stats']),
      uploadedAt:
          raw['uploaded_at'] is String ? raw['uploaded_at'] as String : null,
      appVersion:
          raw['app_version'] is String ? raw['app_version'] as String : null,
    );
  }

  /// 从快照名解析上传时间（wordmem_20260903T141530Z.zip），解析失败返回 null
  DateTime? get uploadedTime {
    if (uploadedAt != null) return DateTime.tryParse(uploadedAt!);
    final m = RegExp(r'^wordmem_(\d{8})T(\d{6})Z\.zip$').firstMatch(name);
    if (m == null) return null;
    final d = m.group(1)!;
    final t = m.group(2)!;
    return DateTime.tryParse(
        '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}'
        'T${t.substring(0, 2)}:${t.substring(2, 4)}:${t.substring(4, 6)}Z');
  }
}

/// 远端 manifest（v1 schema）
class SyncManifest {
  static const int currentSchema = 1;

  final int schema;
  final List<SnapshotEntry> snapshots;
  final String? latest;

  const SyncManifest({
    this.schema = currentSchema,
    required this.snapshots,
    this.latest,
  });

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'snapshots': snapshots.map((e) => e.toJson()).toList(),
        if (latest != null) 'latest': latest,
      };

  /// 解析失败（schema 不识别 / 结构非法）时抛 FormatException，
  /// 由调用方走降级重建（施工文档 §3.2）。
  factory SyncManifest.fromJson(Map<String, dynamic> raw) {
    final schema = raw['schema'];
    if (schema is! int || schema != SyncManifest.currentSchema) {
      throw const FormatException('unsupported manifest schema');
    }
    final rawList = raw['snapshots'];
    if (rawList is! List) {
      throw const FormatException('invalid manifest snapshots');
    }
    final entries = <SnapshotEntry>[];
    for (final item in rawList) {
      final e = SnapshotEntry.fromJsonOrNull(item);
      if (e != null) entries.add(e);
    }
    final latest = raw['latest'];
    return SyncManifest(
      schema: SyncManifest.currentSchema,
      snapshots: entries,
      latest: latest is String ? latest : null,
    );
  }

  factory SyncManifest.fromJsonString(String s) =>
      SyncManifest.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());

  SnapshotEntry? entry(String? name) {
    if (name == null) return null;
    for (final e in snapshots) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// 追加/替换条目并更新 latest
  SyncManifest withAdded(SnapshotEntry entry) {
    final rest = snapshots.where((e) => e.name != entry.name).toList()
      ..add(entry);
    return SyncManifest(schema: schema, snapshots: rest, latest: entry.name);
  }

  SyncManifest without(String name) {
    final rest = snapshots.where((e) => e.name != name).toList();
    String? newLatest = latest == name ? null : latest;
    newLatest ??= rest.isNotEmpty
        ? (rest.toList()
              ..sort((a, b) => (b.uploadedTime ?? DateTime.utc(0))
                  .compareTo(a.uploadedTime ?? DateTime.utc(0))))
            .first
            .name
        : null;
    return SyncManifest(schema: schema, snapshots: rest, latest: newLatest);
  }
}

/// 防呆判定结果（§4.2/§4.3）
class SyncDecision {
  final bool needsConfirm;
  final String message; // needsConfirm == false 时为空串

  const SyncDecision.silent()
      : needsConfirm = false,
        message = '';
  const SyncDecision.confirm(this.message) : needsConfirm = true;
}

/// 纯判定逻辑（不读时钟，全程水位 + parent 链）
class SyncChecks {
  /// §4.1：远端是否有本机没见过的更新备份。
  /// latest == 水位 → false；否则沿 latest 条目的 parent 链上溯，
  /// 链上出现水位快照（本机见过的最新点）或他机根（parent==null）或断链
  /// 均视为"没见过"。任何时间戳都不参与比较。
  static bool remoteHasUnseenBackup({
    required SyncManifest? manifest,
    required String? watermarkName,
  }) {
    if (manifest == null) return false; // 无 manifest 时检查 A 直接静默（§4.2）
    final latest = manifest.latest;
    if (latest == null || latest == watermarkName) return false;
    // 上溯 parent 链（设上限防环）
    var cur = manifest.entry(latest);
    for (var i = 0; i < 32 && cur != null; i++) {
      if (cur.name == watermarkName) return true; // 链上出现水位 → 更新备份
      final parent = cur.parent;
      if (parent == null) return true; // 他机根 / 独立血缘
      final next = manifest.entry(parent);
      if (next == null) return true; // 链断裂（如快照被清理）
      cur = next;
    }
    return true; // 信息不足时宁可多问
  }

  /// §4.2 检查 A（上传前）
  static SyncDecision beforeUpload({
    required SyncManifest? manifest,
    required String? watermarkName,
  }) {
    if (manifest == null) return const SyncDecision.silent();
    if (manifest.latest == null ||
        manifest.latest == watermarkName ||
        watermarkName == manifest.latest) {
      return const SyncDecision.silent();
    }
    if (!remoteHasUnseenBackup(manifest: manifest, watermarkName: watermarkName)) {
      return const SyncDecision.silent();
    }
    final e = manifest.entry(manifest.latest);
    final detail = (e != null && e.deviceName != null && e.stats != null)
        ? '（${e.deviceName}，共 ${e.stats!.reviewLogs} 条复习记录）'
        : '';
    return SyncDecision.confirm(
        '云端已有本机未见过的更新备份$detail。本机上传将覆盖它。'
        '如果你最近在别的设备学习过，请先下载数据。');
  }

  /// §4.3 检查 B（下载前）
  /// [localReviewCount] 为本机 review_logs 计数；[watermark] 为本机水位 stats
  /// （null 表示水位缺失：老版本升级 / 重装后）；
  /// [localLastReviewedAt] 为本机 MAX(reviewed_at)，与水位记录值对比（§4.1）。
  static SyncDecision beforeDownload({
    required int localReviewCount,
    required SyncStats? watermark,
    String? localLastReviewedAt,
  }) {
    if (localReviewCount <= 0) return const SyncDecision.silent(); // 空库静默
    if (watermark == null) {
      return const SyncDecision.confirm('本机可能有学习记录尚未上传，'
          '下载数据将覆盖它们。建议先「上传数据」再下载。');
    }
    final countNewer = localReviewCount > watermark.reviewLogs;
    final timeNewer = _timeLater(localLastReviewedAt, watermark.lastReviewedAt);
    if (!countNewer && !timeNewer) return const SyncDecision.silent();
    return SyncDecision.confirm('本机有学习记录尚未上传（本机共 $localReviewCount 条），'
        '下载数据将覆盖它们。建议先「上传数据」再下载。');
  }

  static bool _timeLater(String? a, String? b) {
    if (a == null || b == null) return false;
    final ta = DateTime.tryParse(a);
    final tb = DateTime.tryParse(b);
    if (ta == null || tb == null) return false;
    return ta.isAfter(tb);
  }
}

/// §5 错误文案映射（全部中性可读，不打日志明文）
enum SyncErrorCode {
  auth, // 401/403
  rateLimited, // 429/503
  network, // 不可达/超时
  quota, // 507 / 上传 0 字节
  notFound, // 404
  server, // 其他 5xx
  incompatible, // 写读回环失败
  unknown,
}

String syncErrorText(SyncErrorCode code) {
  switch (code) {
    case SyncErrorCode.auth:
      return '账号或应用密码不正确（注意：必须使用「应用密码」而非登录密码）';
    case SyncErrorCode.rateLimited:
      return '坚果云请求过于频繁（免费版每 30 分钟 600 次限频），请稍后再试';
    case SyncErrorCode.network:
      return '无法连接到坚果云，请检查网络';
    case SyncErrorCode.quota:
      return '云端空间不足或写入失败，请检查坚果云账户';
    case SyncErrorCode.notFound:
      return '云端文件不存在，请刷新后重试';
    case SyncErrorCode.server:
      return '坚果云服务异常，请稍后再试';
    case SyncErrorCode.incompatible:
      return '该 WebDAV 服务兼容性不佳，写入后无法正确读回，不建议使用';
    case SyncErrorCode.unknown:
      return '操作失败，请稍后再试';
  }
}
