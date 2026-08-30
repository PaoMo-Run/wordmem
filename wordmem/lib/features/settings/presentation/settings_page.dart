import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/backup_repository.dart';

/// 设置页面
///
/// 设计约定（2026-08-30 液体玻璃改版）：aurora 背景 + iOS 设置页式玻璃分组卡；
/// 「复习算法」等过时文案已随 FSRS 修正。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retention = ref.watch(desiredRetentionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final reminderEnabled = ref.watch(reminderEnabledProvider);
    final reminderHour = ref.watch(reminderHourProvider);
    final reminderMinute = ref.watch(reminderMinuteProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              // 复习设置
              const _SectionHeader('复习设置'),
              GlassSection(
                children: [
                  ListTile(
                    leading: const Icon(Icons.psychology_outlined),
                    title: const Text('目标记忆率'),
                    subtitle: Text('${(retention * 100).toStringAsFixed(0)}%'),
                    trailing: SizedBox(
                      width: 180,
                      child: Slider(
                        value: retention,
                        min: AppConstants.minDesiredRetention,
                        max: AppConstants.maxDesiredRetention,
                        divisions: 15,
                        label: '${(retention * 100).round()}%',
                        onChanged: (v) =>
                            ref.read(desiredRetentionProvider.notifier).set(v),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '目标记忆率越高，复习间隔越短，复习频率越高。范围 80%-95%。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              // 提醒设置
              const _SectionHeader('提醒设置'),
              GlassSection(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: const Text('每日提醒'),
                    subtitle: Text(reminderEnabled
                        ? '每天 ${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')} 提醒'
                        : '已关闭'),
                    value: reminderEnabled,
                    onChanged: (v) async {
                      ref.read(reminderEnabledProvider.notifier).set(v);
                      if (v) {
                        final notif = ref.read(notificationServiceProvider);
                        await notif.init();
                        final granted = await notif.requestPermissions();
                        if (granted) {
                          final reviewRepo =
                              ref.read(reviewRepositoryProvider);
                          final pending = reviewRepo.pendingCount;
                          await notif.scheduleDailyReminder(
                            hour: reminderHour,
                            minute: reminderMinute,
                            pendingCount: pending,
                          );
                        }
                      } else {
                        final notif = ref.read(notificationServiceProvider);
                        await notif.cancelAll();
                      }
                    },
                  ),
                  if (reminderEnabled)
                    ListTile(
                      leading: const SizedBox(width: 24),
                      title: const Text('提醒时间'),
                      trailing: TextButton(
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                                hour: reminderHour, minute: reminderMinute),
                          );
                          if (time != null) {
                            ref
                                .read(reminderHourProvider.notifier)
                                .set(time.hour);
                            ref
                                .read(reminderMinuteProvider.notifier)
                                .set(time.minute);
                            final notif =
                                ref.read(notificationServiceProvider);
                            final reviewRepo =
                                ref.read(reviewRepositoryProvider);
                            final pending = reviewRepo.pendingCount;
                            await notif.scheduleDailyReminder(
                              hour: time.hour,
                              minute: time.minute,
                              pendingCount: pending,
                            );
                          }
                        },
                        child: Text(
                          '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                ],
              ),

              // 外观
              const _SectionHeader('外观'),
              GlassSection(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('主题模式'),
                    trailing: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.auto_mode)),
                        ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined)),
                        ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined)),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) =>
                          ref.read(themeModeProvider.notifier).set(s.first),
                    ),
                  ),
                ],
              ),

              // AI 服务（未来短文生成 / 陪练的接入端口）
              const _SectionHeader('AI 服务'),
              GlassSection(
                children: [
                  Consumer(builder: (context, ref, _) {
                    final aiCfg = ref.watch(aiConfigProvider);
                    return ListTile(
                      leading: const Icon(Icons.smart_toy_outlined),
                      title: const Text('AI 接入配置'),
                      subtitle: Text(aiCfg.isConfigured
                          ? '已接入 ${aiCfg.providerName}（${aiCfg.model}）'
                          : '未配置：接入后可使用 AI 短文 / 陪练'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/ai-config'),
                    );
                  }),
                ],
              ),

              // 数据管理
              const _SectionHeader('数据管理'),
              GlassSection(
                children: [
                  ListTile(
                    leading: const Icon(Icons.upload_outlined),
                    title: const Text('导出备份'),
                    subtitle: const Text('导出词库和复习记录为 zip 文件'),
                    onTap: () async {
                      try {
                        final repo = ref.read(backupRepositoryProvider);
                        // 1. 生成备份 zip 字节
                        final bytes = await repo.exportBytes();

                        // 2. 让用户选择保存位置（Android/iOS 需传 bytes 由系统写入）
                        final now = DateTime.now();
                        final savePath = await FilePicker.platform.saveFile(
                          dialogTitle: '选择备份保存位置',
                          fileName: BackupRepository.defaultFileName(now),
                          type: FileType.custom,
                          allowedExtensions: ['zip'],
                          bytes: bytes,
                        );
                        if (savePath == null) return; // 用户取消选择

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('备份已导出')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('导出失败: $e')),
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('导入备份'),
                    subtitle: const Text('从 zip 文件恢复词库（覆盖或续写）'),
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['zip'],
                      );
                      if (result == null ||
                          result.files.single.path == null) {
                        return;
                      }
                      if (!context.mounted) return;

                      // 选择导入模式：覆盖 / 续写 / 取消
                      final mode = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('导入备份'),
                          content: const Text(
                              '请选择导入方式：\n\n覆盖：用备份完全替换当前词库\n续写：只添加当前没有的单词，保留现有数据'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, 'merge'),
                                child: const Text('续写')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, 'overwrite'),
                                child: const Text('覆盖')),
                          ],
                        ),
                      );
                      if (mode == null) return;

                      try {
                        final repo = ref.read(backupRepositoryProvider);
                        final isOverwrite = mode == 'overwrite';
                        final importResult = isOverwrite
                            ? await repo.import(result.files.single.path!)
                            : await repo.importMerge(
                                result.files.single.path!);
                        if (importResult.success) {
                          // 触发词库刷新信号，让词库/今日页立即重载
                          ref
                              .read(wordListVersionProvider.notifier)
                              .state++;
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                              importResult.success
                                  ? (isOverwrite
                                      ? '导入成功: ${importResult.wordCount} 个单词'
                                      : '续写成功: 新增 ${importResult.wordCount} 词，跳过 ${importResult.skippedCount ?? 0} 词')
                                  : '导入失败: ${importResult.error}',
                            )),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('导入失败: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),

              // 词典信息
              const _SectionHeader('词典信息'),
              GlassSection(
                children: [
                  const ListTile(
                    leading: Icon(Icons.menu_book_outlined),
                    title: Text('内置词典'),
                    subtitle: Text(
                        '专业版 ECDICT（含航空专业词）\n版本: ${AppConstants.dictProVersion}\n词条数: ${AppConstants.dictProWordCount}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('按新词典刷新词库释义'),
                    subtitle: const Text(
                        '将词库中已有单词的释义更新为词典最新版（改善近义词/词根归类）'),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('刷新词库释义'),
                          content: const Text(
                              '将用词典最新释义覆盖词库中所有单词的释义。\n'
                              '此操作会影响近义词/词根分组，完成后将自动重新聚类。\n\n'
                              '继续？'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('刷新')),
                          ],
                        ),
                      );
                      if (confirmed != true) return;

                      final repo = ref.read(wordRepositoryProvider);
                      final updated = repo.refreshDefinitionsFromDict();
                      // 即时反馈：词库列表 + 近义词/词根群立即重聚类
                      ref.read(wordListVersionProvider.notifier).state++;
                      ref.read(groupVersionProvider.notifier).state++;
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '已刷新 $updated 个单词的释义，近义词/词根分组已更新')),
                        );
                      }
                    },
                  ),
                ],
              ),

              // 关于
              const _SectionHeader('关于'),
              const GlassSection(
                children: [
                  ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('词记'),
                    subtitle:
                        Text('版本 ${AppConstants.appVersion}\n离线英语词库与间隔复习'),
                  ),
                  ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('隐私'),
                    subtitle: Text(
                        '学习数据默认仅存本机；仅当你主动使用 AI 功能时，当日学习数据才会发送给所选 AI 服务商。'),
                  ),
                  // 过时文案修正：算法为 FSRS（非艾宾浩斯固定间隔）
                  ListTile(
                    leading: Icon(Icons.code),
                    title: Text('复习算法'),
                    subtitle: Text(
                        'FSRS 间隔重复算法\n按每词记忆稳定性动态排程，目标记忆率可调'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
