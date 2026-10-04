import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/schedule_tuning.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';

/// 学习节奏设置页（v2.2.0 阶段 C）。
///
/// 顶部常驻生效语义提示 → 预设档 chip → 复习时间线 8 行（单位 小时/天 可切）
/// → 提前背窗口 → 熟练词抽检参数 → 底部「恢复默认 / 保存」。
///
/// 编辑在本地草稿上进行，点「保存」才落库生效；「恢复默认」立即生效（带确认）。
/// 时间线非递增只弹提示不禁止（用户拍板，艾宾浩斯曲线效果自担）。
class ScheduleTuningPage extends ConsumerStatefulWidget {
  const ScheduleTuningPage({super.key});

  @override
  ConsumerState<ScheduleTuningPage> createState() =>
      _ScheduleTuningPageState();
}

class _ScheduleTuningPageState extends ConsumerState<ScheduleTuningPage> {
  late ScheduleTuning _draft;
  bool _useDays = false; // 时间线输入单位：false = 小时，true = 天
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(scheduleTuningProvider);
  }

  // ───────────────── 编辑操作 ─────────────────

  void _update(ScheduleTuning next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  void _applyPreset(String id) => _update(ScheduleTuning.preset(id));

  Future<void> _editTimelineSegment(int i) async {
    final minutes = _draft.timelineMinutes[i];
    final unitLabel = _useDays ? '天' : '小时';
    final initial = _useDays ? _numStr(minutes / 1440) : _numStr(minutes / 60);
    final v = await _promptDouble(
      title: '第 ${i + 1} 段（T$i → T${i + 1}）',
      label: '间隔（$unitLabel）',
      initialValue: initial,
      helper: '范围 ${_numStr(ScheduleTuning.minSegmentMinutes / 60)} 小时 ~ '
          '${_numStr(ScheduleTuning.maxSegmentMinutes / 1440)} 天',
    );
    if (v == null || !mounted) return;
    final raw = _useDays ? (v * 1440).round() : (v * 60).round();
    final clamped =
        raw.clamp(ScheduleTuning.minSegmentMinutes, ScheduleTuning.maxSegmentMinutes);
    final tl = [..._draft.timelineMinutes]..[i] = clamped;
    _update(_draft.copyWith(timelineMinutes: tl));
  }

  Future<void> _editUpcomingHours() async {
    final v = await _promptDouble(
      title: '提前背窗口',
      label: '小时',
      initialValue: '${_draft.upcomingHours}',
      helper: '范围 ${ScheduleTuning.minUpcomingHours} ~ '
          '${ScheduleTuning.maxUpcomingHours} 小时',
    );
    if (v == null || !mounted) return;
    final raw = v.round().clamp(
        ScheduleTuning.minUpcomingHours, ScheduleTuning.maxUpcomingHours);
    _update(_draft.copyWith(upcomingHours: raw));
  }

  Future<void> _editQuizField(_QuizField field) async {
    final (title, helper, min, max) = switch (field) {
      _QuizField.count => (
          '单次抽检词量',
          '范围 ${ScheduleTuning.minQuizCount} ~ ${ScheduleTuning.maxQuizCount} 个',
          ScheduleTuning.minQuizCount,
          ScheduleTuning.maxQuizCount,
        ),
      _QuizField.correct => (
          '答对后冷却（天）',
          '范围 ${ScheduleTuning.minIntervalDays} ~ ${ScheduleTuning.maxIntervalDays} 天',
          ScheduleTuning.minIntervalDays,
          ScheduleTuning.maxIntervalDays,
        ),
      _QuizField.wrong => (
          '答错后复检（天）',
          '范围 ${ScheduleTuning.minIntervalDays} ~ ${ScheduleTuning.maxIntervalDays} 天',
          ScheduleTuning.minIntervalDays,
          ScheduleTuning.maxIntervalDays,
        ),
      _QuizField.skip => (
          '跳过后冷却（天）',
          '范围 ${ScheduleTuning.minIntervalDays} ~ ${ScheduleTuning.maxIntervalDays} 天',
          ScheduleTuning.minIntervalDays,
          ScheduleTuning.maxIntervalDays,
        ),
      _QuizField.short => (
          '小池答对冷却（天）',
          '已掌握词少于抽检词量时适用；'
              '范围 ${ScheduleTuning.minIntervalDays} ~ ${ScheduleTuning.maxIntervalDays} 天',
          ScheduleTuning.minIntervalDays,
          ScheduleTuning.maxIntervalDays,
        ),
    };
    final current = switch (field) {
      _QuizField.count => _draft.quizCount,
      _QuizField.correct => _draft.quizCorrectDays,
      _QuizField.wrong => _draft.quizWrongDays,
      _QuizField.skip => _draft.quizSkipDays,
      _QuizField.short => _draft.quizShortCooldownDays,
    };
    final v = await _promptDouble(
      title: title,
      label: '数值',
      initialValue: '$current',
      helper: helper,
    );
    if (v == null || !mounted) return;
    final raw = v.round().clamp(min, max);
    _update(switch (field) {
      _QuizField.count => _draft.copyWith(quizCount: raw),
      _QuizField.correct => _draft.copyWith(quizCorrectDays: raw),
      _QuizField.wrong => _draft.copyWith(quizWrongDays: raw),
      _QuizField.skip => _draft.copyWith(quizSkipDays: raw),
      _QuizField.short => _draft.copyWith(quizShortCooldownDays: raw),
    });
  }

  // ───────────────── 保存 / 重置 ─────────────────

  void _save() {
    final tl = _draft.timelineMinutes;
    final dips = <int>[
      for (var i = 1; i < tl.length; i++)
        if (tl[i] < tl[i - 1]) i,
    ];
    ref.read(scheduleTuningProvider.notifier).apply(_draft);
    setState(() => _dirty = false);
    final messenger = ScaffoldMessenger.of(context);
    if (dips.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('已保存，新节奏从下一次复习开始生效')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              '已保存。注意：第 ${dips.join('、')} 段比前一段短，记忆曲线会在该处回折'),
        ),
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认节奏？'),
        content: const Text('将立即生效并清除当前自定义值。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(scheduleTuningProvider.notifier).reset();
    setState(() {
      _draft = ScheduleTuning.defaults();
      _dirty = false;
    });
  }

  // ───────────────── 小工具 ─────────────────

  /// 数字显示：整数去掉小数点（1.0 → 1），非整数原样（0.5）
  static String _numStr(double x) =>
      x % 1 == 0 ? x.toInt().toString() : '$x';

  /// 分钟的友好显示：整 1440 → 天，整 60 → 小时，其余 → 分钟
  static String _fmtMinutes(int m) {
    if (m % 1440 == 0) return '${m ~/ 1440} 天';
    if (m % 60 == 0) return '${m ~/ 60} 小时';
    return '$m 分钟';
  }

  Future<double?> _promptDouble({
    required String title,
    required String label,
    required String initialValue,
    String? helper,
  }) {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, helperText: helper),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              Navigator.pop(context, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = _draft.resolvedPresetId;
    return Scaffold(
      appBar: AppBar(title: const Text('学习节奏')),
      body: ListView(
        children: [
          // 生效语义提示条（§4.0 原文，勿改写）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 20, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        children: const [
                          TextSpan(text: '新节奏从'),
                          TextSpan(
                              text: '下一次复习',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(
                              text:
                                  '开始生效。已经排好时间的词会先按原时间复习一次，之后才切换到新节奏。'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 预设档
          const _SectionHeader('预设档'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (id, name) in const [
                  ('standard', '标准'),
                  ('intensive', '密集'),
                  ('relaxed', '保守'),
                ])
                  ChoiceChip(
                    label: Text(name),
                    selected: resolved == id,
                    onSelected: (_) => _applyPreset(id),
                  ),
                // 自定义 chip：仅作反推展示，不可点选（选了也没有可套用的值）
                ChoiceChip(
                  label: const Text('自定义'),
                  selected: resolved == 'custom',
                  onSelected: null,
                ),
              ],
            ),
          ),

          // 复习时间线
          _TimelineHeader(
            useDays: _useDays,
            onToggle: (v) => setState(() => _useDays = v),
          ),
          GlassSection(
            children: [
              for (var i = 0; i < _draft.timelineMinutes.length; i++)
                ListTile(
                  title: Text('第 ${i + 1} 段（T$i → T${i + 1}）'),
                  trailing: Text(
                    _fmtMinutes(_draft.timelineMinutes[i]),
                    style: theme.textTheme.titleMedium,
                  ),
                  onTap: () => _editTimelineSegment(i),
                ),
            ],
          ),

          // 提前背窗口
          const _SectionHeader('提前背'),
          GlassSection(
            children: [
              ListTile(
                title: const Text('提前背窗口'),
                subtitle: const Text('首页「即将到期」提示与「提前背」按钮的统计范围'),
                trailing: Text(
                  '${_draft.upcomingHours} 小时',
                  style: theme.textTheme.titleMedium,
                ),
                onTap: _editUpcomingHours,
              ),
            ],
          ),

          // 熟练词抽检
          const _SectionHeader('熟练词抽检'),
          GlassSection(
            children: [
              _quizTile(theme, _QuizField.count, '单次抽检词量',
                  '每次从已掌握词中抽取的词量', '${_draft.quizCount} 个'),
              _quizTile(theme, _QuizField.correct, '答对后冷却',
                  '答对抽检后到下次抽检的天数', '${_draft.quizCorrectDays} 天'),
              _quizTile(theme, _QuizField.wrong, '答错后复检',
                  '答错后再次接受抽检的天数', '${_draft.quizWrongDays} 天'),
              _quizTile(theme, _QuizField.skip, '跳过后冷却',
                  '本次跳过抽检后到下次抽检的天数', '${_draft.quizSkipDays} 天'),
              _quizTile(theme, _QuizField.short, '小池答对冷却',
                  '已掌握词数量少于抽检词量时，答对后的冷却天数',
                  '${_draft.quizShortCooldownDays} 天'),
            ],
          ),

          // 底部操作
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('恢复默认'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(_dirty ? '保存' : '保存（无改动）'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quizTile(
      ThemeData theme, _QuizField field, String title, String subtitle,
      String value) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(value, style: theme.textTheme.titleMedium),
      onTap: () => _editQuizField(field),
    );
  }
}

enum _QuizField { count, correct, wrong, skip, short }

/// 复习时间线组头：标题 + 单位切换（小时 / 天）
class _TimelineHeader extends StatelessWidget {
  final bool useDays;
  final ValueChanged<bool> onToggle;

  const _TimelineHeader({required this.useDays, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '复习时间线（T0 → T8 共 8 段）',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('小时')),
              ButtonSegment(value: true, label: Text('天')),
            ],
            selected: {useDays},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onToggle(s.first),
          ),
        ],
      ),
    );
  }
}

/// 分组小标题（与 me_page._SectionHeader 同款样式）
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
