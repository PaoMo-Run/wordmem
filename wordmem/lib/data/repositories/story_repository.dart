import '../database/story_dao.dart';
import '../database/word_dao.dart';
import '../sources/dict_source.dart';
import '../../domain/models/story.dart';
import '../../domain/services/ai_story_service.dart';
import '../../domain/services/story_import_parser.dart';
import '../../infra/ai/ai_exception.dart';

/// 短文仓库 - 取词 / 富化 / 生成 / 导入 / 持久化编排
///
/// 生成策略：AI 优先；AI 不可用（未配置/网络失败/解析失败）时抛 [AiException]，
/// 由 UI 引导用户走「剪贴板中转」（复制提示词 → 其它 AI App 生成 → 粘贴导入）。
class StoryRepository {
  final StoryDao _storyDao;
  final WordDao _wordDao;
  final DictSource _dict;
  final AiStoryService? _aiService;
  final StoryImportParser _importParser;

  StoryRepository({
    required StoryDao storyDao,
    required WordDao wordDao,
    required DictSource dict,
    AiStoryService? aiService,
    StoryImportParser? importParser,
  })  : _storyDao = storyDao,
        _wordDao = wordDao,
        _dict = dict,
        _aiService = aiService,
        _importParser = importParser ?? StoryImportParser();

  /// 今日学习过的单词（新增 ∪ 复习，去重）
  List<String> getWordsStudiedToday() => _wordDao.getWordsStudiedToday();

  /// v2.2.0 需求4：当日新添加的单词（仅 created_at 今日零点起，不含纯复习词）。
  /// 按添加时间升序返回（最早添加的排前），供分段生成时批次稳定。
  List<String> getWordsAddedToday() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final rows = _wordDao.getWordsAddedBetween(start, now);
    return rows.map((r) => r['word'] as String).toList().reversed.toList();
  }

  /// 指定日期范围内新增的单词
  List<String> getWordsAddedBetween(DateTime start, DateTime end) =>
      _wordDao.getWordsAddedBetween(start, end).map((r) => r['word'] as String).toList();

  /// 词库全部单词（供"指定单词"多选）
  List<String> getAllWords() => _wordDao.getAllWordTexts();

  // ============ v2.2.0 需求4：分段生成 + 导入校验 ============

  /// 每篇短文的最大词数（与 AiStoryService._maxWords 一致）
  static const int storyBatchSize = 25;

  /// 把单词按每批 ≤[batchSize] 切成生成批次（保持给定顺序，纯函数可测）
  static List<List<String>> splitIntoBatches(List<String> words,
      {int batchSize = storyBatchSize}) {
    final batches = <List<String>>[];
    for (var i = 0; i < words.length; i += batchSize) {
      final end = i + batchSize > words.length ? words.length : i + batchSize;
      batches.add(words.sublist(i, end));
    }
    return batches;
  }

  /// 目标词的变形集合（含原词小写）：通过词典 exchange 字段展开
  /// （复数/过去式/现在分词/第三人称/比较级等），供导入正文匹配。
  Set<String> wordVariants(String word) {
    final variants = <String>{word.trim().toLowerCase()};
    final dict = _dict.lookupWithExchange(word.trim());
    final exchange = dict?.exchange;
    if (exchange != null && exchange.isNotEmpty) {
      // exchange 格式: "p:ran/d:run/i:running/3:runs"
      for (final part in exchange.split('/')) {
        final seg = part.split(':');
        if (seg.length == 2 && seg[1].trim().isNotEmpty) {
          variants.add(seg[1].trim().toLowerCase());
        }
      }
    }
    final surface = dict?.word.trim().toLowerCase() ?? '';
    if (surface.isNotEmpty) variants.add(surface);
    return variants;
  }

  /// 正文 token 归一化集合：小写 + 去所有格（dog's / dogs' → dog / dogs）
  static Set<String> tokenizeText(String text) {
    return RegExp(r"[A-Za-z][A-Za-z'-]*")
        .allMatches(text)
        .map((m) => m.group(0)!.toLowerCase())
        .map((t) => t.replaceAll(RegExp(r"'+s?$"), ''))
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  /// v2.2.0 需求4：校验导入短文已包含哪些目标词。
  /// 两档匹配：①精确（小写 + 所有格归一）②词典变形展开（复数/时态等）。
  Set<String> matchedWords(List<String> targets, String storyText) {
    final tokens = tokenizeText(storyText);
    final matched = <String>{};
    for (final t in targets) {
      if (wordVariants(t).any(tokens.contains)) matched.add(t);
    }
    return matched;
  }

  /// 富化：为单词列表补充词性与中文释义（词典优先，兜底原文）
  List<StoryWord> enrich(List<String> words) {
    final result = <StoryWord>[];
    for (final w in words) {
      final trimmed = w.trim();
      if (trimmed.isEmpty) continue;
      final dict = _dict.lookupWithExchange(trimmed);
      if (dict != null) {
        final translation = dict.translationLines.isNotEmpty
            ? dict.translationLines.join('；')
            : (dict.translation ?? '');
        result.add(StoryWord(
          word: dict.word,
          pos: dict.pos,
          translation: translation,
        ));
      } else {
        result.add(StoryWord(word: trimmed, translation: trimmed));
      }
    }
    return result;
  }

  /// 生成短文：AI 优先。
  /// AI 不可用时抛 [AiException]，由 UI 引导用户走剪贴板中转导入。
  Future<Story> generate(
    List<StoryWord> words, {
    String? title,
  }) async {
    final ai = _aiService;
    if (ai == null) {
      throw const AiException(AiErrorType.notConfigured,
          'AI 未配置，请先在「设置 - AI 服务」中配置，或使用剪贴板中转生成');
    }
    return ai.generate(words, title: title);
  }

  /// 流式生成短文（v2.1.4）：yield 累积的原始输出，结束后用 [parseAiStory] 解析。
  /// [words] 应先经 [limitWords] 截断，与解析时传同一集合。
  Stream<String> generateStream(
    List<StoryWord> words, {
    String? title,
  }) {
    final ai = _aiService;
    if (ai == null) {
      throw const AiException(AiErrorType.notConfigured,
          'AI 未配置，请先在「设置 - AI 服务」中配置，或使用剪贴板中转生成');
    }
    return ai.generateStream(words, title: title);
  }

  /// 流式路径：与 [generateStream] 配套的单词截断与原始输出解析
  List<StoryWord> limitWords(List<StoryWord> words) =>
      _aiService?.limitWords(words) ?? words;

  Story parseAiStory(String raw, List<StoryWord> words) {
    final ai = _aiService;
    if (ai == null) {
      throw const AiException(AiErrorType.notConfigured, 'AI 未配置');
    }
    return ai.parseStory(raw, words);
  }

  /// 构建「剪贴板中转」提示词：用户复制到其它 AI App，生成后粘贴回来
  String buildClipboardPrompt(List<StoryWord> words, {String? title}) {
    final buf = StringBuffer();
    buf.writeln('请根据以下单词写一篇英文短文，要求：');
    buf.writeln('1. 自然地使用所有给出的单词；');
    buf.writeln('2. 内容必须符合事实逻辑与现实常识，禁止虚构；');
    buf.writeln('3. 全文围绕一个统一主题展开，句子之间要有自然的逻辑连接，禁止话题突然跳跃；');
    buf.writeln('4. 如果必须涉及多个方面，用过渡句把它们自然地串联起来，不要生硬拼接；');
    buf.writeln('5. 篇幅以 150 词为目标，为保持逻辑连贯可适当超出（不超过 200 词）；');
    buf.writeln('6. 标题用双语：英文标题-中文翻译标题（中间用连字符 - 连接，不用括号）。');
    buf.writeln('');
    buf.writeln('【输出格式（严格按以下标记，每行一个标记，不要其他文字或 JSON）】');
    buf.writeln('标题---英文标题-中文翻译标题');
    buf.writeln('英语正文---英文短文正文');
    buf.writeln('正文翻译---中文对照翻译（逐句对应）');
    buf.writeln('');
    buf.writeln('【重点词声明】');
    buf.writeln('在最后单独输出一行重点词列表，格式为：');
    buf.writeln('【重点词】word1, word2, word3, ...');
    buf.writeln('要求：只列出你在短文中实际使用到的词；使用原文形态（与正文拼写一致，不要加引号或括号）；用英文逗号分隔。');
    buf.writeln('');
    buf.writeln('单词：');
    for (final w in words) {
      buf.writeln('- ${w.word}（${w.pos ?? '?'}）: ${w.translation.isEmpty ? '未提供释义' : w.translation}');
    }
    if (title != null && title.isNotEmpty) {
      buf.writeln('短文标题可参考：$title');
    }
    return buf.toString();
  }

  /// 解析用户从其它 AI App 复制/分享来的文本为 Story（不入库）
  Story parseImported(String raw) => _importParser.parse(raw);

  // ============ 持久化（记忆库） ============

  int save(Story story) => _storyDao.insert(story);

  void update(Story story) => _storyDao.update(story);

  void delete(int id) => _storyDao.delete(id);

  void setArchived(int id, bool archived) => _storyDao.setArchived(id, archived);

  Story? getById(int id) => _storyDao.getById(id);

  List<Story> getAll({bool? archived}) => _storyDao.getAll(archived: archived);

  int count() => _storyDao.count();
}
