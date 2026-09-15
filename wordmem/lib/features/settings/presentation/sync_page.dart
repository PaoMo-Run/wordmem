import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../../data/repositories/sync_repository.dart';
import '../../../domain/services/sync/sync_models.dart';
import '../../../infra/sync/webdav_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';

/// 从网络同步（v2.1.3，施工文档 §2.2）
///
/// 文案基调（§2.6）：统一"上传备份 / 下载备份"语义，不出现"同步/冲突"
/// 等暗示实时同步的词——这是手动备份，不是实时同步。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  bool _loadedConfig = false;
  String? _davUrl;
  String? _davUser;
  // 应用密码只进内存/安全存储，绝不打日志（§6）
  String? _davPassword;

  bool _uploading = false;
  bool _downloading = false;
  bool _repairedNotice = false;
  List<SnapshotEntry> _snapshots = const [];
  // v2.1.5：云端快照列表只展示最近若干份，避免条目过多刷屏
  static const int _visibleSnapshots = 5;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final store = ref.read(syncSettingsStoreProvider);
    final url = await store.read(SyncSettingKeys.davUrl);
    final user = await store.read(SyncSettingKeys.davUser);
    final pass = await store.read(SyncSettingKeys.davPassword);
    if (!mounted) return;
    setState(() {
      _davUrl = url;
      _davUser = user;
      _davPassword = pass;
      _loadedConfig = true;
    });
    if (_configured) _refreshSnapshots();
  }

  bool get _configured =>
      (_davUrl?.isNotEmpty ?? false) &&
      (_davUser?.isNotEmpty ?? false) &&
      (_davPassword?.isNotEmpty ?? false);

  SyncRepository _buildRepo() {
    return SyncRepository(
      storage: WebdavSyncStorage(
        url: _davUrl!,
        user: _davUser!,
        password: _davPassword!,
      ),
      settings: ref.read(syncSettingsStoreProvider),
      localStats: ref.read(syncLocalStatsProvider),
      backup: ref.read(syncBackupGatewayProvider),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────── 上传（§2.4）───────────────────────

  Future<void> _upload() async {
    if (_uploading || _downloading) return; // 防重复锁
    if (!_configured) {
      await _showConfigDialog(onDone: _upload);
      return;
    }
    setState(() => _uploading = true);
    try {
      final repo = _buildRepo();
      var r = await repo.upload(confirmed: false);
      if (r.needsConfirmation && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('上传数据'),
            content: Text(r.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('仍要上传')),
            ],
          ),
        );
        if (go != true) return;
        r = await repo.upload(confirmed: true);
      }
      _snack(r.message);
      if (r.ok) _refreshSnapshots();
      if (repo.lastManifestRepaired && mounted) {
        setState(() => _repairedNotice = true);
      }
    } catch (_) {
      _snack('上传失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ─────────────────────── 下载（§2.5）───────────────────────

  Future<void> _download(String? snapshotName) async {
    if (_uploading || _downloading) return; // 防重复锁
    if (!_configured) {
      await _showConfigDialog(onDone: () => _download(snapshotName));
      return;
    }
    setState(() => _downloading = true);
    try {
      final repo = _buildRepo();
      var r = await repo.download(snapshotName: snapshotName, confirmed: false);
      if (r.needsConfirmation && mounted) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('下载数据'),
            content: Text(r.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'upload-first'),
                  child: const Text('先上传本机数据')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'download'),
                  child: const Text('仍要下载')),
            ],
          ),
        );
        if (action == null || action == 'cancel') return;
        if (action == 'upload-first') {
          setState(() => _downloading = false);
          await _upload(); // 直接转上传分支（§4.3）
          return;
        }
        r = await repo.download(snapshotName: snapshotName, confirmed: true);
      }
      _snack(r.message);
      if (r.ok) _refreshSnapshots();
      if (repo.lastManifestRepaired && mounted) {
        setState(() => _repairedNotice = true);
      }
    } catch (_) {
      _snack('下载失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ─────────────────────── 快照列表 ────────────────────────

  Future<void> _refreshSnapshots() async {
    if (!_configured) return;
    try {
      final list = await _buildRepo().remoteSnapshots();
      if (mounted) setState(() => _snapshots = list);
    } catch (_) {
      // 列表拉取失败不打断主流程
    }
  }

  // ─────────────────────── 首次配置（§2.3）───────────────────────

  Future<void> _showConfigDialog({
    required Future<void> Function() onDone,
  }) async {
    final urlCtrl = TextEditingController(
        text: _davUrl?.isNotEmpty == true
            ? _davUrl
            : 'https://dav.jianguoyun.com/dav/');
    final userCtrl = TextEditingController(text: _davUser ?? '');
    final passCtrl = TextEditingController(text: _davPassword ?? '');
    var testing = false;
    var passVisible = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('配置网盘账号'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://dav.jianguoyun.com/dav/',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: userCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(labelText: '账号（注册邮箱）'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: !passVisible,
                  decoration: InputDecoration(
                    labelText: '应用密码',
                    suffixIcon: IconButton(
                      icon: Icon(passVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setDialog(() => passVisible = !passVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '应用密码获取：坚果云 App → 设置 → 第三方应用管理 → 添加应用密码；'
                  '或网页端 账户信息 → 安全选项 → 第三方应用管理。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  '应用密码仅保存在本机安全存储，不会上传或写入备份。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: testing ? null : () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: testing
                  ? null
                  : () async {
                      final url = urlCtrl.text.trim();
                      final user = userCtrl.text.trim();
                      final pass = passCtrl.text;
                      if (url.isEmpty || user.isEmpty || pass.isEmpty) {
                        _snack('请填写完整的服务器地址、账号和应用密码');
                        return;
                      }
                      setDialog(() => testing = true);
                      try {
                        // 用临时配置做测试连接（§2.3：ping→mkdir→写读回环→删除）
                        final temp = SyncRepository(
                          storage: WebdavSyncStorage(
                              url: url, user: user, password: pass),
                          settings: ref.read(syncSettingsStoreProvider),
                          localStats: ref.read(syncLocalStatsProvider),
                          backup: ref.read(syncBackupGatewayProvider),
                        );
                        await temp.testConnection();
                      } on SyncStorageException catch (e) {
                        if (ctx.mounted) {
                          setDialog(() => testing = false);
                          _snack(syncErrorText(e.code));
                        }
                        return;
                      } catch (_) {
                        if (ctx.mounted) {
                          setDialog(() => testing = false);
                          _snack('无法连接到坚果云，请检查网络');
                        }
                        return;
                      }
                      // 通过 → 保存配置（§3.3 全部进 secure_storage）
                      final store = ref.read(syncSettingsStoreProvider);
                      await store.write(SyncSettingKeys.davUrl, url);
                      await store.write(SyncSettingKeys.davUser, user);
                      await store.write(SyncSettingKeys.davPassword, pass);
                      await _ensureDeviceIdentity();
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('测试连接'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        _davUrl = urlCtrl.text.trim();
        _davUser = userCtrl.text.trim();
        _davPassword = passCtrl.text;
      });
      await onDone(); // 返回原动作继续执行（§2.3.4）
    }
  }

  /// 首次配置时生成本机身份（§3.3：device_id 随机 UUID + device_name）
  /// v2.1.4：device_name 读取真机品牌+型号（如 "Xiaomi 2210132C"），
  /// 旧版本写入的默认值"安卓设备"也一并迁移为真实设备名。
  Future<void> _ensureDeviceIdentity() async {
    final store = ref.read(syncSettingsStoreProvider);
    if (await store.read(SyncSettingKeys.deviceId) == null) {
      await store.write(SyncSettingKeys.deviceId, _generateUuidV4());
    }
    final stored = await store.read(SyncSettingKeys.deviceName);
    if (stored == null || stored == '安卓设备') {
      await store.write(SyncSettingKeys.deviceName,
          await _resolveDeviceName());
    }
  }

  /// 读取真机品牌 + 型号；失败回退"安卓设备"
  static Future<String> _resolveDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      final android = await plugin.androidInfo;
      final brand = android.brand.trim();
      final model = android.model.trim();
      if (brand.isEmpty && model.isEmpty) return '安卓设备';
      if (brand.isEmpty) return model;
      if (model.isEmpty || model == brand) return brand;
      return '$brand $model';
    } catch (_) {
      return '安卓设备';
    }
  }

  static String _generateUuidV4() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _maskAccount(String user) {
    final at = user.indexOf('@');
    if (at <= 0) return '${user.isEmpty ? '' : user[0]}***';
    return '${user[0]}***${user.substring(at)}';
  }

  static String _maskHost(String url) {
    final u = Uri.tryParse(url);
    return u?.host ?? url;
  }

  // ─────────────────────── UI ────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _uploading || _downloading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('从网络同步'),
        backgroundColor: Colors.transparent,
      ),
      body: !_loadedConfig
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_repairedNotice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassContainer(
                      blur: 0,
                      elevated: false,
                      radius: 14,
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Icon(Icons.build_circle_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('云端索引已自动修复',
                                style: theme.textTheme.bodySmall)),
                      ]),
                    ),
                  ),

                // 状态卡
                GlassSection(
                  children: [
                    ListTile(
                      leading: Icon(
                        _configured ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                        color: _configured ? theme.colorScheme.primary : null,
                      ),
                      title: Text(_configured ? '已连接网盘' : '尚未配置网盘账号'),
                      subtitle: Text(_configured
                          ? '${_maskHost(_davUrl!)} · ${_maskAccount(_davUser!)}'
                          : '点击任一按钮开始配置（支持坚果云）'),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () => _showConfigDialog(onDone: () async {
                                  _refreshSnapshots();
                                }),
                        child: Text(_configured ? '修改' : '配置'),
                      ),
                    ),
                  ],
                ),

                // 主按钮：上传
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: GlassButton(
                    label: _uploading ? '正在上传…' : '上传数据到云端',
                    icon: _uploading ? null : Icons.backup_outlined,
                    onPressed: busy ? null : _upload,
                  ),
                ),
                // 主按钮：下载
                GlassButton(
                  label: _downloading ? '正在下载…' : '从云端下载数据',
                  icon: _downloading ? null : Icons.restore_outlined,
                  onPressed: busy ? null : () => _download(null),
                  tinted: true,
                ),

                // 高级：快照列表
                const _SectionHeader('高级'),
                GlassSection(
                  children: [
                    if (_snapshots.isEmpty)
                      const ListTile(
                        leading: Icon(Icons.inbox_outlined),
                        title: Text('云端还没有快照'),
                        subtitle: Text('上传数据后会显示在这里'),
                      )
                    else ...[
                      // v2.1.5：只展示最近 5 份（remoteSnapshots 已按时间倒序），
                      // 超出部分用一行汇总提示代替，避免列表冗长
                      for (final s in _snapshots.take(_visibleSnapshots))
                        _snapshotTile(s),
                      if (_snapshots.length > _visibleSnapshots)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.more_horiz, size: 20),
                          title:
                              const Text('仅显示最近 $_visibleSnapshots 份'),
                          subtitle: Text(
                            _snapshots.length >
                                    SyncRepository.totalSnapshotsHint
                                ? '云端共 ${_snapshots.length} 份快照，'
                                    '建议到网盘的 wordmem 目录手动清理'
                                : '云端共 ${_snapshots.length} 份快照',
                          ),
                        ),
                    ],
                  ],
                ),

                // 说明文案（§2.6 文案基调）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '这是手动备份，不是实时同步。换设备学习：旧设备先「上传数据到云端」，'
                    '新设备再「从云端下载数据」。云端保留最近 10 份本机快照，其他设备的备份不会被删除。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _snapshotTile(SnapshotEntry s) {
    final when = s.uploadedTime;
    // v2.1.4：云端存 UTC，展示按设备本地时区（北京时间）换算
    final local = when?.toLocal();
    final whenText = local != null
        ? '${local.year}-${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')} '
            '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
        : s.name;
    final degraded = s.sha256 == null; // 降级重建态：信息有限
    final sizeText = s.size != null
        ? '${(s.size! / 1024 / 1024).toStringAsFixed(1)} MB'
        : null;
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(whenText),
      subtitle: Text(
        [
          if (s.deviceName != null) s.deviceName!,
          if (sizeText != null) sizeText,
          if (degraded) '信息有限',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // v2.1.5：删除云端备份（二次确认）
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除此备份',
            onPressed: _uploading || _downloading
                ? null
                : () => _confirmDeleteSnapshot(s),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '恢复此备份',
            onPressed: _uploading || _downloading
                ? null
                : () => _download(s.name), // 换选旧版（D4）
          ),
        ],
      ),
    );
  }

  /// 删除云端备份：二次确认 → 调 deleteSnapshot → 刷新列表
  Future<void> _confirmDeleteSnapshot(SnapshotEntry s) async {
    final when = s.uploadedTime?.toLocal();
    final whenText = when != null
        ? '${when.year}-${when.month.toString().padLeft(2, '0')}-'
            '${when.day.toString().padLeft(2, '0')} '
            '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
        : s.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除云端备份？'),
        content: Text('将永久删除 $whenText 的备份（${s.deviceName ?? "未知设备"}），'
            '删除后无法恢复。确认删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _downloading = true); // 复用忙态锁，防止并发操作
    try {
      final result = await _buildRepo().deleteSnapshot(s.name);
      if (mounted) _snack(result.message);
      if (result.ok) await _refreshSnapshots();
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}

/// 区块标题（与 me_page 同款）
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
