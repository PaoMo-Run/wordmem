import 'package:flutter/material.dart';

import '../../../data/repositories/sync_repository.dart';

/// 从云端恢复数据的**统一执行链**（v2.1.7）。
///
/// 恢复备份是破坏性操作（覆盖本机数据），所以防呆确认链只允许有一份实现。
/// 原本只有「我的 → 进度同步」页在使用；v2.1.7 首页启动探测也要能触发恢复，
/// 因此把它抽出来给两处共用——**新入口绝不能绕过这套确认**，
/// 否则用户会在首页一键覆盖掉本机更新的学习进度。
///
/// 调用方负责：耗时状态（loading）、结果提示（snack）、词库刷新信号。
/// 返回值 null 表示「本次没有执行恢复」：
/// - 用户在确认框点了取消
/// - 用户选择了「先上传本机数据」（由 [onUploadFirst] 接管后续流程）
Future<SyncOpResult?> executeCloudRestore({
  required BuildContext context,
  required SyncRepository repo,
  String? snapshotName,
  /// 非空时在确认框中额外提供「先上传本机数据」出口（换设备接力路径）。
  Future<void> Function()? onUploadFirst,
}) async {
  // 第一趟：只做防呆检查（本机进度 vs 水位），不写任何数据
  var result =
      await repo.download(snapshotName: snapshotName, confirmed: false);
  if (!result.needsConfirmation) return result;

  final message = result.message;
  if (!context.mounted) return null;
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('下载数据'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消')),
        if (onUploadFirst != null)
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'upload-first'),
              child: const Text('先上传本机数据')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'download'),
            child: const Text('仍要下载')),
      ],
    ),
  );
  if (action == null || action == 'cancel') return null;
  if (action == 'upload-first') {
    await onUploadFirst!();
    return null;
  }

  // 用户已确认 → 带 confirmed 重调（此时内部不再触发确认）
  result = await repo.download(snapshotName: snapshotName, confirmed: true);
  return result;
}
