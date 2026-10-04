import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/mastery_badge.dart';
import '../../../core/theme/colors.dart';

/// 近义词群专属挑战页（v2.2.0 需求3：单卡题组制）
///
/// 从「词群记忆 - 近义词群」点某张卡的「测试」进入：只测该卡对应的词群，
/// 不再把多个群排成队列。群成员洗牌后按 ≤5 切块，每块一道子题
/// （8 个单词选项 = 块内近义词 + 干扰项），答对 ≥ 3 个（块内正确项不足 3 个时
/// 须全对）即该子题通过；全部子题通过 = 该群通过，熟悉度 +1（封顶 4）并立即落库。
/// 结果页按钮：再测一次 / 下一词群（最后一群时隐藏）/ 返回词群记忆。
class SynonymGroupChallengePage extends ConsumerStatefulWidget {
  /// 待测词群列表（按展示顺序），每项含 def / words / id
  final List<Map<String, dynamic>> groups;
  /// 从第几个词群开始测（默认 0）
  final int startIndex;

  const SynonymGroupChallengePage({
    super.key,
    required this.groups,
    this.startIndex = 0,
  });

  @override
  ConsumerState<SynonymGroupChallengePage> createState() =>
      _SynonymGroupChallengePageState();
}

class _SynonymGroupChallengePageState
    extends ConsumerState<SynonymGroupChallengePage> {
  // 相位：quiz(逐子题) → result(本群汇总)
  String _phase = 'quiz';

  late int _matchIndex; // 当前群在 groups 中的下标
  List<Map<String, dynamic>> _challenges = []; // 本群子题队列
  int _subIndex = 0;
  final Set<String> _selected = {};
  bool _submitted = false;
  bool _passed = false; // 当前子题是否通过
  List<bool> _subResults = []; // 各子题结果
  List<Set<String>> _selections = []; // 各子题用户选择（复盘用）
  int _mastery = 0;
  int _masteryAfter = 0;
  bool _groupPassed = false;

  Map<String, dynamic>? _challenge; // 当前子题

  /// 选项释义缓存（提交后展示，懒加载）
  final Map<String, String> _defs = {};

  /// 获取单词释义（词典首行，供提交后展示）
  String _defOf(String word) {
    return _defs.putIfAbsent(word, () {
      final dict = ref.read(dictSourceProvider);
      final w = dict.lookup(word);
      final t = w?.translation?.trim() ?? '';
      if (t.isEmpty) return '暂无释义';
      final first = t.split('\n').first.trim();
      return first.length > 60 ? '${first.substring(0, 60)}…' : first;
    });
  }

  @override
  void initState() {
    super.initState();
    _matchIndex = widget.startIndex.clamp(0, widget.groups.length - 1);
    _loadMastery();
    _buildSession();
  }

  Map<String, dynamic> get _group => widget.groups[_matchIndex];
  String get _groupId => _group['id'] as String? ?? '';
  int get _requiredCorrect => (_challenge?['requiredCorrect'] as int?) ?? 3;
  bool get _hasNextGroup => _matchIndex < widget.groups.length - 1;

  void _loadMastery() {
    final repo = ref.read(wordRepositoryProvider);
    _mastery = repo.getSynonymGroupMastery()[_groupId] ?? 0;
  }

  /// 为当前群构建子题队列（洗牌切块，覆盖全群成员）
  void _buildSession() {
    final repo = ref.read(wordRepositoryProvider);
    final words = (_group['words'] as List).cast<String>();
    _challenges = repo.buildGroupChallengeSession(words);
    _subIndex = 0;
    _selected.clear();
    _submitted = false;
    _passed = false;
    _subResults = [];
    _selections = [];
    _groupPassed = false;
    _masteryAfter = 0;
    _challenge = _challenges.isNotEmpty ? _challenges.first : null;
  }

  int get _correctSelected => _selected
      .where((w) => (_challenge!['correct'] as List).contains(w))
      .length;
  bool get _passedCurrent => _correctSelected >= _requiredCorrect;

  void _toggle(String word) {
    if (_submitted) return;
    setState(() {
      if (_selected.contains(word)) {
        _selected.remove(word);
      } else {
        _selected.add(word);
      }
    });
  }

  void _submit() {
    if (_challenge == null || _submitted) return;
    final passed = _passedCurrent;
    setState(() {
      _submitted = true;
      _passed = passed;
      _subResults.add(passed);
      _selections.add(Set.of(_selected));
    });
  }

  /// 子题推进：还有下一子题则继续，否则结算本群
  void _nextSub() {
    if (_subIndex < _challenges.length - 1) {
      setState(() {
        _subIndex++;
        _selected.clear();
        _submitted = false;
        _passed = false;
        _challenge = _challenges[_subIndex];
      });
    } else {
      _settleGroup();
    }
  }

  /// 本群结算：全部子题通过 = 该群通过，熟悉度 +1 并立即落库（封顶 4）
  void _settleGroup() {
    final repo = ref.read(wordRepositoryProvider);
    _groupPassed = _subResults.isNotEmpty && _subResults.every((p) => p);
    if (_groupPassed) {
      _masteryAfter = repo.bumpSynonymGroupMastery(_groupId);
      _mastery = _masteryAfter;
      // 通知词群记忆页刷新熟悉度
      ref.read(groupVersionProvider.notifier).state++;
    }
    setState(() => _phase = 'result');
  }

  /// 再测一次：重建本群子题（重新洗牌切块）
  void _retryGroup() {
    setState(() {
      _phase = 'quiz';
      _defs.clear();
    });
    _loadMastery();
    _buildSession();
  }

  /// 下一词群：推进到列表中的下一张卡
  void _nextGroup() {
    if (!_hasNextGroup) return;
    setState(() {
      _matchIndex++;
      _phase = 'quiz';
      _defs.clear();
    });
    _loadMastery();
    _buildSession();
  }

  /// 人工复核：提交后点击选项单词，跳转对应单词详情页（可手动移出词林/词根）
  void _openWordDetail(String w) {
    final row = ref.read(wordDaoProvider).getByWord(w);
    final id = row?['id'] as int?;
    if (id == null) return;
    context.push('/word/$id');
  }

  @override
  Widget build(BuildContext context) {
    if (_challenge == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('近义词群挑战'),
          backgroundColor: Colors.transparent,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('该群无法出题'),
                  const SizedBox(height: 12),
                  GlassButton(
                    onPressed: () => context.pop(),
                    label: '返回',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _phase == 'result' ? _buildResult() : _buildQuiz();
  }

  // 深浅自适应的评分色（dark 亮化版）
  Color get _goodColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingGoodDark
      : AppColors.ratingGood;
  Color get _againColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingAgainDark
      : AppColors.ratingAgain;

  Widget _buildQuiz() {
    final theme = Theme.of(context);
    final challenge = _challenge!;
    final correct = (challenge['correct'] as List).cast<String>();
    final options = (challenge['options'] as List).cast<String>();
    final isLastSub = _subIndex == _challenges.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
            '近义词群 ${_matchIndex + 1} / ${widget.groups.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              LinearProgressIndicator(
                  value: (_subIndex + 1) / _challenges.length, minHeight: 3),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _challenges.length > 1
                            ? '子题 ${_subIndex + 1} / ${_challenges.length}（覆盖本群全部近义词）'
                            : '选出含有该释义的近义词（至少选 $_requiredCorrect 个）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MasteryBadge(level: _mastery),
                          const SizedBox(width: 6),
                          Text(
                            '第 $_mastery / 4 级',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 核心中文释义（玻璃卡）
                      GlassContainer(
                        blur: 0,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _group['def'] as String? ?? '',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  const SizedBox(height: 24),
                  // 单词选项（横屏/宽屏自动换行，宽屏可用网格）
                  LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth > 600;
                    if (wide) {
                      return GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: _submitted ? 1.9 : 3.2,
                        children:
                            options.map((w) => _buildOptionChip(theme, w)).toList(),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children:
                          options.map((w) => _buildOptionChip(theme, w)).toList(),
                    );
                  }),
                  const SizedBox(height: 24),
                  if (_submitted) ...[
                    Text(
                      _passed
                          ? '通过！选对 $_correctSelected 个近义词'
                          : '未通过（需选对 $_requiredCorrect 个，当前选对 $_correctSelected 个）',
                      style: TextStyle(
                        color: _passed ? _goodColor : _againColor,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // 正确答案展示
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: correct.map((w) {
                        final hit = _selected.contains(w);
                        return Chip(
                          label: Text(w),
                          avatar: Icon(
                            hit
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: hit
                                ? _goodColor
                                : theme.colorScheme.outline,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      onPressed: _nextSub,
                      label: isLastSub ? '查看结果' : '下一题',
                      tinted: true,
                      height: 48,
                      blur: 0,
                    ),
                  ] else
                    GlassButton(
                      onPressed: _selected.length >= _requiredCorrect
                          ? _submit
                          : null,
                      label: _selected.length >= _requiredCorrect
                          ? '提交（已选 ${_selected.length} 个）'
                          : '至少选择 $_requiredCorrect 个单词',
                      tinted: true,
                      height: 48,
                      blur: 0,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      ],
    ),
    );
  }

  /// 本群结果汇总 + 三个收尾按钮
  Widget _buildResult() {
    final theme = Theme.of(context);
    final total = _subResults.length;
    final passedCount = _subResults.where((p) => p).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
            '近义词群 ${_matchIndex + 1} / ${widget.groups.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          Text('作答完成', textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('本群 $passedCount/$total 题通过',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: _groupPassed ? _goodColor : theme.colorScheme.primary,
              )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (_groupPassed ? _goodColor : _againColor)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: (_groupPassed ? _goodColor : _againColor)
                      .withValues(alpha: 0.4)),
            ),
            child: Text(
              _groupPassed
                  ? '通过！熟悉度 +1（${(_masteryAfter - 1).clamp(0, 4)} → $_masteryAfter / 4）'
                  : '本群未全部通过，熟悉度不变（$_mastery / 4）',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: _groupPassed ? _goodColor : _againColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 各子题复盘：正确词 + 是否命中
          ...List.generate(_challenges.length, (i) {
            final challenge = _challenges[i];
            final correct = (challenge['correct'] as List).cast<String>();
            final selected = _selections.length > i ? _selections[i] : <String>{};
            final passed = _subResults.length > i && _subResults[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassContainer(
                blur: 0,
                elevated: false,
                radius: 14,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          passed ? Icons.check_circle : Icons.cancel,
                          size: 18,
                          color: passed ? _goodColor : _againColor,
                        ),
                        const SizedBox(width: 6),
                        Text('子题 ${i + 1} · ${passed ? '通过' : '未通过'}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: passed ? _goodColor : _againColor,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: correct.map((w) {
                        final hit = selected.contains(w);
                        return Chip(
                          label: Text(w),
                          avatar: Icon(
                            hit
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color:
                                hit ? _goodColor : theme.colorScheme.outline,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          // 收尾按钮：纵向满宽堆叠，避免窄屏 Row 挤压导致文字错位
          // 优先级：下一词群 > 再测一次 > 返回
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasNextGroup) ...[
                FilledButton.icon(
                  onPressed: _nextGroup,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('下一词群'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: _retryGroup,
                icon: const Icon(Icons.refresh),
                label: const Text('再测一次'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 10),
              GlassButton(
                onPressed: () => context.pop(),
                icon: Icons.arrow_back,
                label: '返回词群记忆',
                tinted: true,
                height: 48,
                blur: 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(ThemeData theme, String word) {
    final selected = _selected.contains(word);
    final isCorrect =
        (_challenge!['correct'] as List).contains(word);

    Color? bg;
    Color? border;
    Color fg = theme.colorScheme.onSurface;

    if (_submitted) {
      if (isCorrect) {
        bg = _goodColor.withValues(alpha: 0.15);
        border = _goodColor;
        fg = _goodColor;
      } else if (selected) {
        bg = _againColor.withValues(alpha: 0.15);
        border = _againColor;
        fg = _againColor;
      }
    } else if (selected) {
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.4);
      border = theme.colorScheme.primary;
      fg = theme.colorScheme.primary;
    }

    return InkWell(
      // 提交后：点击选项跳转对应单词详情页（人工复核：可手动移出词林/词根）
      onTap: _submitted ? () => _openWordDetail(word) : () => _toggle(word),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border ?? theme.dividerColor, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: fg),
            ),
            if (_submitted) ...[
              const SizedBox(height: 3),
              Text(
                _defOf(word),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  height: 1.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
