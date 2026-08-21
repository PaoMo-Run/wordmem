/// 词根条目
class WordRoot {
  final String root;
  final List<String> variants;
  final String meaning;
  final String meaningEn;
  final List<String> examples;

  const WordRoot({
    required this.root,
    this.variants = const [],
    required this.meaning,
    this.meaningEn = '',
    this.examples = const [],
  });

  /// 词根本身 + 变体（匹配用）
  List<String> get forms => [root, ...variants];

  factory WordRoot.fromJson(Map<String, dynamic> j) => WordRoot(
        root: (j['root'] as String).toLowerCase(),
        variants:
            ((j['variants'] as List?) ?? const []).map((e) => e.toString().toLowerCase()).toList(),
        meaning: (j['meaning'] as String?) ?? '',
        meaningEn: (j['meaningEn'] as String?) ?? '',
        examples: ((j['examples'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

/// 词根字典加载器（从 assets/data/word_roots.json 加载）见 word_root_dict.dart。
/// 拆分为独立文件（依赖 flutter rootBundle），保持本文件纯 Dart 以便单测无需 flutter_tester。

/// 词根匹配结果
class RootMatch {
  final WordRoot root;
  /// 用户词库中匹配到的单词（含词根的完整单词）
  final List<String> words;

  const RootMatch({required this.root, required this.words});

  bool get usable => words.length >= 2;
}

/// 词根匹配器：字母边界匹配（port 不误中 sport / transport）
class RootMatcher {
  /// 从用户词库中筛出含任一词根的单词
  /// [userWords] 用户词库单词（小写）
  List<RootMatch> match(List<String> userWords, List<WordRoot> roots) {
    final matches = <RootMatch>[];
    for (final root in roots) {
      final words = <String>[];
      for (final w in userWords) {
        if (containsRoot(w, root)) {
          words.add(w);
        }
      }
      if (words.length >= 2) {
        matches.add(RootMatch(root: root, words: words));
      }
    }
    return matches;
  }

  /// 词素子串匹配：词根作为单词的构词成分即可命中
  /// 例：port -> transport ✓, export ✓, report ✓, import ✓, support ✓
  /// 这样 inspect/respect(spect)、transport/export(port) 等复合词都能正确归类，
  /// 词根挑战才能真正触发（原"字母边界"逻辑会把它们全部排除）。
  /// 注：含空格的多词条目（如 "master minimum equipment list"）不参与词根匹配，
  /// 避免词组因含某词根被整体拉进词根家族。
  bool containsRoot(String word, WordRoot root) {
    if (word.contains(' ')) return false;
    final lower = word.toLowerCase();
    for (final form in root.forms) {
      if (form.length < 3) continue;
      if (lower.contains(form)) return true;
    }
    return false;
  }
}
