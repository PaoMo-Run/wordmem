import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../../../domain/models/review_rating.dart';

/// 统一的测验卡片组件集合
///
/// 今日复习与自选复习共用：
/// 1. EnToZhCard   英译汉翻卡（看英文回想中文，翻面后评分）
/// 2. ChooseWordCard 四选一（看中文释义，选对应英文单词）
/// 3. DictationCard 默写（看中文释义/首字母提示，拼写英文）
/// 所有卡片均带"跳过"选项。

/// 英译汉翻卡卡片
class EnToZhCard extends StatefulWidget {
  final String word;
  final String definition;
  final String? note;
  final bool isNew;
  final int lapses;
  final void Function(ReviewRating rating) onRate;
  final VoidCallback onSkip;

  const EnToZhCard({
    super.key,
    required this.word,
    required this.definition,
    this.note,
    this.isNew = false,
    this.lapses = 0,
    required this.onRate,
    required this.onSkip,
  });

  @override
  State<EnToZhCard> createState() => _EnToZhCardState();
}

class _EnToZhCardState extends State<EnToZhCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal() {
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DirectionChip(text: '英译汉', color: AppColors.primary),
            const SizedBox(height: 16),
            if (widget.isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('新词', style: theme.textTheme.labelSmall),
              ),
            const SizedBox(height: 16),
            _buildFlipCard(theme),
            const SizedBox(height: 12),
            // 跳过
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

  /// 3D 翻转卡片：正面英文单词，背面释义 + 评分按钮
  Widget _buildFlipCard(ThemeData theme) {
    return SizedBox(
      height: 400,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final angle = _controller.value * math.pi;
          final isFront = angle < math.pi / 2;
          // 背面评分按钮在翻转后半段淡入
          final backOpacity =
              ((angle - math.pi / 2) / (math.pi / 5)).clamp(0.0, 1.0);
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            alignment: Alignment.center,
            child: isFront
                ? _frontFace(theme)
                : Opacity(opacity: backOpacity, child: _backFace(theme)),
          );
        },
      ),
    );
  }

  /// 正面：英文单词 + 显示释义按钮
  Widget _frontFace(ThemeData theme) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.word,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.touch_app_outlined,
            size: 32,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮查看释义',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _reveal,
              child: const Text('显示释义',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// 背面：释义 + 备注 + 四档评分按钮（整体再转 pi 抵消镜像）
  Widget _backFace(ThemeData theme) {
    return Transform(
      transform: Matrix4.identity()..rotateY(math.pi),
      alignment: Alignment.center,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.definition.isNotEmpty)
                  Text(
                    widget.definition,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                if ((widget.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.note!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (widget.lapses > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '已遗忘 ${widget.lapses} 次',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.ratingAgain,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // 四档评分按钮
                Row(
                  children: [
                    Expanded(
                      child: _RatingButton(
                        label: ReviewRating.again.label,
                        color: AppColors.ratingAgain,
                        onPressed: () => widget.onRate(ReviewRating.again),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RatingButton(
                        label: ReviewRating.hard.label,
                        color: AppColors.ratingHard,
                        onPressed: () => widget.onRate(ReviewRating.hard),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RatingButton(
                        label: ReviewRating.good.label,
                        color: AppColors.ratingGood,
                        onPressed: () => widget.onRate(ReviewRating.good),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RatingButton(
                        label: ReviewRating.easy.label,
                        color: AppColors.ratingEasy,
                        onPressed: () => widget.onRate(ReviewRating.easy),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 四选一（看中文选英文单词）
class ChooseWordCard extends StatefulWidget {
  final String word;
  final String definition;
  final List<String> options;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  const ChooseWordCard({
    super.key,
    required this.word,
    required this.definition,
    required this.options,
    required this.onAnswered,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
  });

  @override
  State<ChooseWordCard> createState() => _ChooseWordCardState();
}

class _ChooseWordCardState extends State<ChooseWordCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = _selected != null;
    final correct = answered && widget.options[_selected!] == widget.word;

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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.definition,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ...widget.options.asMap().entries.map((e) {
              final idx = e.key;
              final opt = e.value;
              return _buildOption(theme, idx, opt, answered, correct);
            }),
            if (answered) ...[
              const SizedBox(height: 8),
              Text(
                correct ? '回答正确！' : '正确答案：${widget.word}',
                style: TextStyle(
                  color: correct ? AppColors.ratingGood : AppColors.ratingAgain,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: widget.onNext,
                  child: Text(
                    widget.isLast ? '完成' : '下一题',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
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
      ThemeData theme, int idx, String opt, bool answered, bool correct) {
    final selected = _selected == idx;
    final isCorrectOpt = opt == widget.word;

    Color bg = Colors.transparent;
    Color border = theme.dividerColor;
    Color fg = theme.colorScheme.onSurface;

    if (answered) {
      if (isCorrectOpt) {
        bg = AppColors.ratingGood.withValues(alpha: 0.15);
        border = AppColors.ratingGood;
        fg = AppColors.ratingGood;
      } else if (selected) {
        bg = AppColors.ratingAgain.withValues(alpha: 0.15);
        border = AppColors.ratingAgain;
        fg = AppColors.ratingAgain;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: answered
            ? null
            : () {
                setState(() => _selected = idx);
                widget.onAnswered(opt == widget.word);
              },
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(
              color: border, width: selected || isCorrectOpt ? 2 : 1),
          minimumSize: const Size(double.infinity, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          opt,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
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

  const DictationCard({
    super.key,
    required this.word,
    required this.definition,
    this.showHint = true,
    required this.onAnswered,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
  });

  @override
  State<DictationCard> createState() => _DictationCardState();
}

class _DictationCardState extends State<DictationCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _answered = false;
  bool _correct = false;

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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
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
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
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
            const SizedBox(height: 16),
            if (_answered) ...[
              Text(
                _correct ? '正确！' : '正确答案：${widget.word}',
                style: TextStyle(
                  color:
                      _correct ? AppColors.ratingGood : AppColors.ratingAgain,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: widget.onNext,
                  child: Text(
                    widget.isLast ? '完成' : '下一题',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('提交',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
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
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// 评分按钮
class _RatingButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _RatingButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
