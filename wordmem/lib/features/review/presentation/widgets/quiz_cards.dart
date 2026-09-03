import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../../../domain/models/word_option.dart';
import '../../../../shared/widgets/glass.dart';
import '../../../../shared/widgets/word_play_button.dart';

/// 统一的测验卡片组件集合
///
/// 今日复习与自选复习共用：
/// 1. EnToZhChoiceCard 英译汉选择题（看英文单词，选对应中文释义）
/// 2. ChooseWordCard 四选一（看中文释义，选对应英文单词）
/// 3. DictationCard 默写（看中文释义/首字母提示，拼写英文）
/// 所有卡片均带"跳过"选项。
///
/// 设计约定（2026-08-30 液体玻璃）：题干卡玻璃化 + 主按钮 GlassButton；
/// 评分色深浅自适应（dark 亮化版），正文对比度 ≥4.5:1。

/// 英译汉选择题卡片
///
/// 题干：英文单词；选项：4 个中文释义（正确项 = 该词释义）。
/// 用户选出对应释义后回调 onAnswered(是否正确)，再点「下一题」。
class EnToZhChoiceCard extends StatefulWidget {
  final String word;
  final String definition;
  final List<WordOption> options;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  /// 单词发音回调（null = 不显示播放按钮，如开关关闭）。
  /// 题面单词本就可见，题面播放不泄答案。
  final void Function(String word)? onPlayWord;

  const EnToZhChoiceCard({
    super.key,
    required this.word,
    required this.definition,
    required this.options,
    required this.onAnswered,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
    this.onPlayWord,
  });

  @override
  State<EnToZhChoiceCard> createState() => _EnToZhChoiceCardState();
}

class _EnToZhChoiceCardState extends State<EnToZhChoiceCard> {
  int? _selected;

  Color get _goodColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingGoodDark
      : AppColors.ratingGood;
  Color get _againColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingAgainDark
      : AppColors.ratingAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = _selected != null;
    final correct = answered &&
        widget.options[_selected!].word == widget.word;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DirectionChip(text: '英译汉', color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              '选择与下列单词对应的中文释义',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // 英文单词题干（玻璃卡，题面即可播放发音）
            GlassContainer(
              blur: 0,
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      widget.word,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (widget.onPlayWord != null) ...[
                    const SizedBox(width: 4),
                    WordPlayButton(
                      onPressed: () => widget.onPlayWord!(widget.word),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 600;
              final options = widget.options.asMap().entries.map((e) {
                final idx = e.key;
                final opt = e.value;
                return _buildOption(theme, idx, opt, answered, correct);
              }).toList();
              if (wide) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 3.4,
                  children: options,
                );
              }
              return Column(children: options);
            }),
            if (answered) ...[
              const SizedBox(height: 8),
              Text(
                correct
                    ? '回答正确！'
                    : '正确答案：${widget.definition.isEmpty ? widget.word : widget.definition}',
                style: TextStyle(
                  color: correct ? _goodColor : _againColor,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              GlassButton(
                onPressed: widget.onNext,
                label: widget.isLast ? '完成' : '下一题',
                tinted: true,
                height: 48,
                blur: 0,
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onSkip,
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('跳过'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
      ThemeData theme, int idx, WordOption opt, bool answered, bool correct) {
    final selected = _selected == idx;
    final isCorrectOpt = opt.word == widget.word;

    Color bg = Colors.transparent;
    Color border = theme.dividerColor;
    Color fg = theme.colorScheme.onSurface;

    if (answered) {
      if (isCorrectOpt) {
        bg = _goodColor.withValues(alpha: 0.15);
        border = _goodColor;
        fg = _goodColor;
      } else if (selected) {
        bg = _againColor.withValues(alpha: 0.15);
        border = _againColor;
        fg = _againColor;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: answered
                ? null
                : () {
                    setState(() => _selected = idx);
                    widget.onAnswered(opt.word == widget.word);
                  },
            style: OutlinedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              side: BorderSide(
                  color: border, width: selected || isCorrectOpt ? 2 : 1),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              opt.definition.isEmpty ? opt.word : opt.definition,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// 四选一（看中文选英文单词）
class ChooseWordCard extends StatefulWidget {
  final String word;
  final String definition;
  final List<WordOption> options;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  /// 单词发音回调（null = 不显示）。仅在作答后随正确答案显示，防泄答案。
  final void Function(String word)? onPlayWord;

  const ChooseWordCard({
    super.key,
    required this.word,
    required this.definition,
    required this.options,
    required this.onAnswered,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
    this.onPlayWord,
  });

  @override
  State<ChooseWordCard> createState() => _ChooseWordCardState();
}

class _ChooseWordCardState extends State<ChooseWordCard> {
  int? _selected;

  Color get _goodColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingGoodDark
      : AppColors.ratingGood;
  Color get _againColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingAgainDark
      : AppColors.ratingAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = _selected != null;
    final correct =
        answered && widget.options[_selected!].word == widget.word;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DirectionChip(text: '选单词', color: AppColors.ratingEasy),
            const SizedBox(height: 16),
            Text(
              '选择与下列释义对应的单词',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // 中文释义题干（玻璃卡）
            GlassContainer(
              blur: 0,
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.definition,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 600;
              final options = widget.options.asMap().entries.map((e) {
                final idx = e.key;
                final opt = e.value;
                return _buildOption(theme, idx, opt, answered, correct);
              }).toList();
              if (wide) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.8,
                  children: options,
                );
              }
              return Column(children: options);
            }),
            if (answered) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      correct ? '回答正确！' : '正确答案：${widget.word}',
                      style: TextStyle(
                        color: correct ? _goodColor : _againColor,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (widget.onPlayWord != null)
                    WordPlayButton(
                      onPressed: () => widget.onPlayWord!(widget.word),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              GlassButton(
                onPressed: widget.onNext,
                label: widget.isLast ? '完成' : '下一题',
                tinted: true,
                height: 48,
                blur: 0,
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onSkip,
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('跳过'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
      ThemeData theme, int idx, WordOption opt, bool answered, bool correct) {
    final selected = _selected == idx;
    final isCorrectOpt = opt.word == widget.word;

    Color bg = Colors.transparent;
    Color border = theme.dividerColor;
    Color fg = theme.colorScheme.onSurface;

    if (answered) {
      if (isCorrectOpt) {
        bg = _goodColor.withValues(alpha: 0.15);
        border = _goodColor;
        fg = _goodColor;
      } else if (selected) {
        bg = _againColor.withValues(alpha: 0.15);
        border = _againColor;
        fg = _againColor;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: answered
                ? null
                : () {
                    setState(() => _selected = idx);
                    widget.onAnswered(opt.word == widget.word);
                  },
            style: OutlinedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              side: BorderSide(
                  color: border, width: selected || isCorrectOpt ? 2 : 1),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              opt.word,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          // 提交后显示该选项释义
          if (answered && opt.definition.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                opt.definition,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 默写卡片
class DictationCard extends StatefulWidget {
  final String word;
  final String definition;
  final bool showHint; // 是否显示首字母提示
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  /// 单词发音回调（null = 不显示）。仅在作答后随正确答案显示，防泄答案。
  final void Function(String word)? onPlayWord;

  const DictationCard({
    super.key,
    required this.word,
    required this.definition,
    this.showHint = true,
    required this.onAnswered,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
    this.onPlayWord,
  });

  @override
  State<DictationCard> createState() => _DictationCardState();
}

class _DictationCardState extends State<DictationCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _answered = false;
  bool _correct = false;

  Color get _goodColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingGoodDark
      : AppColors.ratingGood;
  Color get _againColor => Theme.of(context).brightness == Brightness.dark
      ? AppColors.ratingAgainDark
      : AppColors.ratingAgain;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  String _hint(String word) {
    if (word.isEmpty) return '';
    return '${word[0]}${'_' * (word.length - 1)}';
  }

  void _submit() {
    final ok = _normalize(_controller.text) == _normalize(widget.word) &&
        _controller.text.trim().isNotEmpty;
    setState(() {
      _answered = true;
      _correct = ok;
    });
    widget.onAnswered(ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DirectionChip(text: '默写', color: AppColors.ratingHard),
            const SizedBox(height: 16),
            Text(
              widget.showHint ? '根据释义和首字母提示默写单词' : '根据释义默写单词',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // 释义题干（玻璃卡）
            GlassContainer(
              blur: 0,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    widget.definition,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.showHint) ...[
                    const SizedBox(height: 8),
                    Text(
                      _hint(widget.word),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '共 ${widget.word.length} 个字母',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    hintText: '输入英文单词',
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: theme.colorScheme.primary, width: 2),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!_answered) _submit();
                  },
                  enabled: !_answered,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_answered) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _correct ? '正确！' : '正确答案：${widget.word}',
                      style: TextStyle(
                        color: _correct ? _goodColor : _againColor,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (widget.onPlayWord != null)
                    WordPlayButton(
                      onPressed: () => widget.onPlayWord!(widget.word),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              GlassButton(
                onPressed: widget.onNext,
                label: widget.isLast ? '完成' : '下一题',
                tinted: true,
                height: 48,
                blur: 0,
              ),
            ] else
              GlassButton(
                onPressed: _submit,
                label: '提交',
                tinted: true,
                height: 48,
                blur: 0,
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onSkip,
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('跳过'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方向标签
class _DirectionChip extends StatelessWidget {
  final String text;
  final Color color;
  const _DirectionChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
