import 'dart:math';
import '../models/story_quiz.dart';

/// 一个渲染单元：原文 token + 是否为空格 + 空格索引
class QuizToken {
  final String text;
  /// 是否是被挖空的空格
  final bool isBlank;
  /// 空格在 blanks 中的索引（isBlank=true 时有效）
  final int? blankIndex;

  const QuizToken({required this.text, this.isBlank = false, this.blankIndex});

  QuizToken.blank({required int index})
      : text = '',
        isBlank = true,
        blankIndex = index;
}

/// 出题结果：带挖空标记的完整 token 序列 + 空格列表
class QuizContent {
  final List<QuizToken> tokens;
  final List<QuizBlank> blanks;

  const QuizContent({required this.tokens, required this.blanks});

  bool get isEmpty => blanks.isEmpty;
}

/// 逐句出题结果（拓展模式：一句一题）
class QuizSentenceContent {
  /// 句子序号（1 起，按原文顺序）
  final int index;
  /// 该句英文原文
  final String sentence;
  /// 该句中文翻译（可能为空）
  final String translation;
  final List<QuizToken> tokens;
  final List<QuizBlank> blanks;

  const QuizSentenceContent({
    required this.index,
    required this.sentence,
    required this.translation,
    required this.tokens,
    required this.blanks,
  });
}

/// 短文记忆测试出题引擎（纯本地规则，无需 AI）。
///
/// - 复习/巩固：仅挖空重点词（story.words）
/// - 拓展：挖空所有实词（排除停用虚词/连接词）
/// - 复习模式附带 4 选 1 干扰项；巩固/拓展为输入默写
class StoryQuizEngine {
  StoryQuizEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// 常用停用词（虚词/连接词/代词/助动词等，拓展模式不挖空）
  static const _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at',
    'for', 'with', 'by', 'from', 'as', 'is', 'are', 'was', 'were', 'be',
    'been', 'being', 'am', 'do', 'does', 'did', 'have', 'has', 'had',
    'will', 'would', 'can', 'could', 'should', 'may', 'might', 'must',
    'it', 'its', 'this', 'that', 'these', 'those', 'i', 'you', 'he',
    'she', 'we', 'they', 'my', 'your', 'his', 'her', 'our', 'their',
    'me', 'him', 'us', 'them', 'not', 'no', 'yes', 'so', 'if', 'then',
    'than', 'there', 'here', 'when', 'where', 'why', 'how', 'what',
    'which', 'who', 'whom', 'whose', 'all', 'any', 'some', 'more',
    'most', 'other', 'about', 'into', 'out', 'off', 'up', 'down',
    'over', 'under', 'again', 'once', 'just', 'very', 'too', 'also',
    'only', 'own', 'same', 'such', 'each', 'both', 'one', 'two',
  };

  /// 生成题目：返回带挖空标记的完整 token 序列 + 空格列表。
  ///
  /// [text] 短文正文；[highlightWords] 重点词（原文形态）
  QuizContent generate({
    required String text,
    required List<String> highlightWords,
    required StoryQuizMode mode,
  }) {
    // 重点词统一小写集合（供匹配）
    final hlLower = highlightWords.map((w) => w.toLowerCase()).toSet();

    // 按单词拆分（保留标点位置信息）
    final regex = RegExp(r"[A-Za-z][A-Za-z'-]*|[^A-Za-z]+");
    final tokens = <String>[];
    for (final m in regex.allMatches(text)) {
      tokens.add(m[0]!);
    }

    final blanks = <QuizBlank>[];
    final outTokens = <QuizToken>[];

    for (final token in tokens) {
      if (!RegExp(r'^[A-Za-z]').hasMatch(token)) {
        // 标点/空白：原样保留
        outTokens.add(QuizToken(text: token));
        continue;
      }
      final lower = token.toLowerCase();
      final shouldBlank = switch (mode) {
        StoryQuizMode.review || StoryQuizMode.consolidate =>
          hlLower.contains(lower),
        StoryQuizMode.extend => !_stopWords.contains(lower),
      };
      if (shouldBlank) {
        final idx = blanks.length;
        blanks.add(QuizBlank(
          word: token,
          sentence: _sentenceOf(text, token),
        ));
        outTokens.add(QuizToken.blank(index: idx));
      } else {
        outTokens.add(QuizToken(text: token));
      }
    }

    // 复习模式：为每个空格生成 4 选 1 干扰项
    if (mode == StoryQuizMode.review) {
      final pool = <String>{
        ...highlightWords,
        // 补充：短文中其他实词作为干扰项来源
        ...tokens.where((t) =>
            RegExp(r'^[A-Za-z]').hasMatch(t) &&
            !_stopWords.contains(t.toLowerCase())),
      }.where((w) => w.isNotEmpty).toList();

      for (var i = 0; i < blanks.length; i++) {
        final blank = blanks[i];
        final correct = blank.word;
        final distractors = <String>[];
        final candidates =
            pool.where((w) => w.toLowerCase() != correct.toLowerCase()).toList()
              ..shuffle(_random);
        for (final c in candidates) {
          if (distractors.length >= 3) break;
          if (distractors.any((d) => d.toLowerCase() == c.toLowerCase())) continue;
          distractors.add(c);
        }
        // 不足 3 个干扰项时降级为 3 选 1 / 2 选 1
        final options = <String>[correct, ...distractors]..shuffle(_random);
        blanks[i] = QuizBlank(
          word: blank.word,
          sentence: blank.sentence,
          options: options,
        );
      }
    }

    return QuizContent(tokens: outTokens, blanks: blanks);
  }

  /// 逐句生成题目（拓展模式：一句一题）。
  ///
  /// 按英文句子（. ! ?）拆分正文，每句独立挖空；
  /// [translation] 为短文的中文对照，按中文句号/换行尽量逐句对齐，
  /// 对齐不上的句子 translation 为空（页面显示"暂无翻译"）。
  List<QuizSentenceContent> generateSentences({
    required String text,
    required String translation,
    required List<String> highlightWords,
  }) {
    // 按 . ! ? + 空白 拆句（保留句号）
    final enSentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // 中文翻译按中文句号/换行拆段
    final zhSegments = translation
        .split(RegExp(r'(?<=[。！？!?])\s*|\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final result = <QuizSentenceContent>[];
    for (var i = 0; i < enSentences.length; i++) {
      final sentence = enSentences[i];
      // 逐句生成（复用内部挖空逻辑，全局空格索引）
      final content = _generateForSentence(
        sentence: sentence,
        highlightWords: highlightWords,
        globalOffset: result.fold<int>(
            0, (sum, s) => sum + s.blanks.length),
      );
      result.add(QuizSentenceContent(
        index: i + 1,
        sentence: sentence,
        translation: i < zhSegments.length ? zhSegments[i] : '',
        tokens: content.tokens,
        blanks: content.blanks,
      ));
    }
    return result;
  }

  /// 对单个句子挖空（供逐句模式调用；globalOffset 为前面句子累计空格数）
  QuizContent _generateForSentence({
    required String sentence,
    required List<String> highlightWords,
    required int globalOffset,
  }) {
    final regex = RegExp(r"[A-Za-z][A-Za-z'-]*|[^A-Za-z]+");
    final tokens = <String>[];
    for (final m in regex.allMatches(sentence)) {
      tokens.add(m[0]!);
    }

    final blanks = <QuizBlank>[];
    final outTokens = <QuizToken>[];
    for (final token in tokens) {
      if (!RegExp(r'^[A-Za-z]').hasMatch(token)) {
        outTokens.add(QuizToken(text: token));
        continue;
      }
      final lower = token.toLowerCase();
      // 拓展模式：挖掉所有实词
      final shouldBlank = !_stopWords.contains(lower);
      if (shouldBlank) {
        final idx = globalOffset + blanks.length;
        blanks.add(QuizBlank(word: token, sentence: sentence));
        outTokens.add(QuizToken.blank(index: idx));
      } else {
        outTokens.add(QuizToken(text: token));
      }
    }
    return QuizContent(tokens: outTokens, blanks: blanks);
  }

  /// 提取单词所在句子（简化：以 . ! ? 分句）
  String _sentenceOf(String text, String word) {
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (final s in sentences) {
      if (RegExp(word, caseSensitive: false).hasMatch(s)) return s.trim();
    }
    return text;
  }

  /// 判分：大小写容错（首字母大写差异算对），拼错才算错
  bool isCorrect(String userAnswer, String correctAnswer) {
    final u = userAnswer.trim().toLowerCase();
    final c = correctAnswer.trim().toLowerCase();
    if (u.isEmpty) return false;
    return u == c;
  }
}
