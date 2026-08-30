import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/backup_repository.dart';

/// 「我的」页面（B 方案第 5 个 tab）
/// 收纳：个人概览 / 学习（统计·词典选择）/ 偏好（AI·提醒·主题）/ 数据 / 关于
///
/// 设计约定（2026-08-30 液体玻璃改版）：iOS 设置页式玻璃分组卡
/// （静态玻璃 blur 0——ListTile 组不长但分组卡是低频区，静态即可）。
class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});

  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  int _streak = 0;
  int _totalWords = 0;
  int _mastered = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    try {
      final reviewDao = ref.read(reviewDaoProvider);
      final statsDao = ref.read(statsDaoProvider);
      setState(() {
        _streak = reviewDao.getCurrentStreak();
        _totalWords = statsDao.getStreakStats().totalWords;
        _mastered = statsDao.getStatusDistribution().masteredCount;
      });
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final reminderEnabled = ref.watch(reminderEnabledProvider);
    final reminderHour = ref.watch(reminderHourProvider);
    final reminderMinute = ref.watch(reminderMinuteProvider);
    // 词库版本变化时刷新统计
    ref.listen(wordListVersionProvider, (_, __) => _loadStats());

    return Scaffold(
      // 液体玻璃布局：背景由 MainShell 的 aurora 光斑提供，Scaffold 透明
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // 个人概览（静态玻璃卡）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: GlassContainer(
              blur: 0,
              elevated: false,
              radius: 14,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text('词',
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('我的学习',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          '连续 $_streak 天 · 已收录 $_totalWords 词 · 已掌握 $_mastered',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),

          // 学习
          const _SectionHeader('学习'),
          _GlassSection(
            children: [
              ListTile(
                leading: const Icon(Icons.bar_chart_outlined),
                title: const Text('学习统计'),
                subtitle: const Text('学习曲线 / 掌握分布'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/stats'),
              ),
              // 词典信息（唯一内置：专业版）
              const ListTile(
                leading: Icon(Icons.menu_book_outlined),
                title: Text('词典信息'),
                subtitle: Text('专业版（15529 词 · 含航空专业词）'),
              ),
            ],
          ),

          // 偏好
          const _SectionHeader('偏好'),
          _GlassSection(
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
                      final reviewRepo = ref.read(reviewRepositoryProvider);
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
                        ref.read(reminderHourProvider.notifier).set(time.hour);
                        ref
                            .read(reminderMinuteProvider.notifier)
                            .set(time.minute);
                        final notif = ref.read(notificationServiceProvider);
                        final reviewRepo = ref.read(reviewRepositoryProvider);
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
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题模式'),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, icon: Icon(Icons.auto_mode)),
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

          // 数据
          const _SectionHeader('数据'),
          _GlassSection(
            children: [
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('文本批量导入'),
                subtitle: const Text('从剪贴板或文件导入单词'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/text-import'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: const Text('导出备份'),
                subtitle: const Text('导出词库和复习记录为 zip 文件'),
                onTap: () async {
                  try {
                    final repo = ref.read(backupRepositoryProvider);
                    final bytes = await repo.exportBytes();
                    final now = DateTime.now();
                    final savePath = await FilePicker.platform.saveFile(
                      dialogTitle: '选择备份保存位置',
                      fileName: BackupRepository.defaultFileName(now),
                      type: FileType.custom,
                      allowedExtensions: ['zip'],
                      bytes: bytes,
                    );
                    if (savePath == null) return;
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
                  if (result == null || result.files.single.path == null) {
                    return;
                  }
                  if (!context.mounted) return;

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
                            onPressed: () => Navigator.pop(ctx, 'overwrite'),
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
                        : await repo.importMerge(result.files.single.path!);
                    if (importResult.success) {
                      ref.read(wordListVersionProvider.notifier).state++;
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

          // 关于
          const _SectionHeader('关于'),
          _GlassSection(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于词记'),
                subtitle:
                    const Text('版本 ${AppConstants.appVersion} · 更新日志 / 隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/about'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// iOS 设置页式玻璃分组卡（静态玻璃，条目贴边满宽）
class _GlassSection extends StatelessWidget {
  final List<Widget> children;
  const _GlassSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GlassContainer(
        blur: 0,
        elevated: false,
        radius: 14,
        padding: EdgeInsets.zero,
        child: Column(children: children),
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
