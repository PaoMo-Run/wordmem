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

  /// 指定日期范围内新增的单词
  List<String> getWordsAddedBetween(DateTime start, DateTime end) =>
      _wordDao.getWordsAddedBetween(start, end).map((r) => r['word'] as String).toList();

  /// 词库全部单词（供"指定单词"多选）
  List<String> getAllWords() => _wordDao.getAllWordTexts();

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
