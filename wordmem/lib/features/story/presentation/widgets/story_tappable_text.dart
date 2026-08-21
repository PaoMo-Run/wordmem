import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/word.dart';
import '../../../../shared/providers/app_providers.dart';

/// 可点词释义的短文正文。
///
/// - 正文按词拆分，**词典中存在**的单词才可点击（词库没有的不响应）；
/// - 点击弹出单词卡（单词 / 音标 / 词性 / 中文释义 / 词形变化）；
/// - [highlightWords] 中的自选词以下划线突出显示，点击行为与其他词一致。
class StoryTappableText extends ConsumerWidget {
  final String text;
  final Set<String> highlightWords;
  final TextStyle? style;
  final TextAlign? textAlign;

  const StoryTappableText({
    super.key,
    required this.text,
    this.highlightWords = const {},
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dict = ref.read(dictSourceProvider);
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;

    // 高亮词集合统一转小写，避免大小写差异导致画线不命中
    final highlightSet = highlightWords
        .map((w) => w.toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet();
    final primary = Theme.of(context).colorScheme.primary;

    final spans = <TextSpan>[];
    // 按英文单词 + 非单词片段拆分
    final regex = RegExp(r"[A-Za-z][A-Za-z'-]*|[^A-Za-z]+");
    for (final m in regex.allMatches(text)) {
      final token = m[0]!;
      if (RegExp(r'^[A-Za-z]').hasMatch(token)) {
        final lower = token.toLowerCase();
        final isHighlight = highlightSet.contains(lower);
        final hasDictEntry = dict.lookupWithExchange(token) != null;
        if (isHighlight) {
          // 重点词：整词一条实线 + 加粗，突出且美观
          spans.add(TextSpan(
            text: token,
            style: baseStyle?.copyWith(
              fontWeight: FontWeight.w600,
              color: hasDictEntry ? primary : null,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.solid,
              decorationColor: primary,
              decorationThickness: 1.5,
            ),
            recognizer: hasDictEntry
                ? (TapGestureRecognizer()
                  ..onTap = () =>
                      _showWordCard(context, ref, token, isHighlight))
                : null,
          ));
        } else {
          spans.add(TextSpan(
            text: token,
            style: baseStyle,
            recognizer: hasDictEntry
                ? (TapGestureRecognizer()
                  ..onTap = () =>
                      _showWordCard(context, ref, token, isHighlight))
                : null,
          ));
        }
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
      textAlign: textAlign,
    );
  }

  void _showWordCard(
      BuildContext context, WidgetRef ref, String word, bool isHighlight) {
    final dict = ref.read(dictSourceProvider);
    final entry = dict.lookupWithExchange(word);
    if (entry == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => _WordCardDialog(word: word, entry: entry, isHighlight: isHighlight),
    );
  }
}

class _WordCardDialog extends StatelessWidget {
  final String word;
  final DictWord entry;
  final bool isHighlight;

  const _WordCardDialog({
    required this.word,
    required this.entry,
    required this.isHighlight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defs = entry.translationLines;
    final phonetic = entry.phonetic;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.word,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (isHighlight)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '今日所学',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phonetic != null && phonetic.isNotEmpty) ...[
              Text(
                phonetic,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (entry.pos != null && entry.pos!.isNotEmpty) ...[
              Text(
                entry.pos!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (defs.isNotEmpty)
              ...defs.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    d,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
            if (entry.definition != null && entry.definition!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.definition!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
