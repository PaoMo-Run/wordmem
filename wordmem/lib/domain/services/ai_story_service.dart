import 'dart:convert';
import 'dart:math';
import '../models/story.dart';
import '../../infra/ai/ai_config.dart';
import '../../infra/ai/ai_exception.dart';
import '../../infra/ai/ai_service.dart';

/// AI 短文生成服务。
///
/// 事实逻辑保证（三重约束）：
/// 1. **Prompt 硬约束**：要求 AI 只写真实存在、符合常识的事实，禁止虚构人物/事件/数据；
/// 2. **词义注入**：把每个目标词的词典释义一并给 AI，让它按真实含义造句；
/// 3. **逻辑连贯约束**：统一叙事主线 + 过渡衔接，禁止话题跳跃。
///
/// 支持按配置开启深度思考（Thinking mode），提高短文逻辑质量。
class AiStoryService {
  final AiService _ai;
  final bool _enableThinking;
  final AiThinkingLevel _thinkingLevel;

  AiStoryService(
    this._ai, {
    bool enableThinking = true,
    AiThinkingLevel thinkingLevel = AiThinkingLevel.medium,
  })  : _enableThinking = enableThinking,
        _thinkingLevel = thinkingLevel;

  static const _maxWords = 25;

  /// 生成变体要求（每次随机选一条注入 prompt，保证多次生成内容不同）
  static const _variants = [
    '请尝试以一个学生的日常生活为开头展开这篇短文。',
    '请尝试以时间顺序（从早到晚）来组织这篇短文。',
    '请尝试以一个具体场景（如课堂、公园、家庭晚餐）为中心展开。',
    '请尝试使用一个贯穿全文的核心情节来串联所有单词。',
    '请尝试以"我"的第一人称视角来写这篇短文。',
    '请尝试围绕一次小活动（如做实验、郊游、做饭）来组织内容。',
  ];

  /// 基于指定单词生成短文（AI 生成；失败抛异常由调用方引导剪贴板中转）
  Future<Story> generate(List<StoryWord> words, {String? title}) async {
    if (words.isEmpty) {
      throw const AiException(AiErrorType.parse, '没有可用的单词');
    }
    // 打乱单词顺序，让每次生成的内容不同
    final limited = words.take(_maxWords).toList()..shuffle(Random());

    final messages = [
      AiMessage(
        role: AiRole.system,
        content: _systemPrompt(),
      ),
      AiMessage(
        role: AiRole.user,
        content: _userPrompt(limited, title),
      ),
    ];

    final resp = await _ai.chat(AiRequest(
      messages: messages,
      temperature: 0.9,
      // 思考 token 计入输出预算，需放大 maxTokens 以免正文被截断
      maxTokens: _enableThinking ? 1600 + _thinkingLevel.budgetTokens : 1600,
      enableThinking: _enableThinking,
      thinkingBudgetTokens: _thinkingLevel.budgetTokens,
    ));

    final content = resp.content.trim();
    if (content.isEmpty) {
      throw const AiException(AiErrorType.parse, 'AI 返回内容为空');
    }
    return _parseStory(content, limited);
  }

  String _systemPrompt() {
    return [
      '你是一位英语学习 App 的内容生成助手。',
      '你的任务是：根据用户给出的单词列表，写一篇**英文小短文**，并在其中自然地使用这些单词。',
      '',
      '【硬性要求 - 事实逻辑】',
      '1. 短文必须符合现实事实与常识，只能写真实存在的事物和普遍成立的事实；',
      '2. 严禁虚构具体人名、公司名、数据、新闻事件或未经证实的信息；',
      '3. 场景选择日常可信的生活/学习情境（如上学、运动、天气、家庭、学校活动等）；',
      '4. 不要编造与单词中文释义不符的用法；',
      '5. 若某个单词是抽象词或专业词，可以写"我在学习/我理解了这个词"这类元描述，不要强行编造细节。',
      '',
      '【硬性要求 - 逻辑连贯】',
      '1. 全文必须围绕一个统一的叙事主线或场景展开，禁止主题跳跃；',
      '2. 相邻句子之间必须有明确的逻辑联系（因果、转折、递进、时间先后、地点转换等），可用连接词自然衔接；',
      '3. 若需涉及多个不同方面（例如食物与科技），必须设计合理的过渡情节把它们串联起来（如"我们的科技课研究了校园午餐的营养搭配"），或先用 1-2 个中间句铺垫，禁止生硬拼接；',
      '4. 读完短文应能顺畅复述大意，任何一句都不能脱离上下文而显得突兀。',
      '',
      '【篇幅要求】',
      '1. 正文以 150 词为目标，在逻辑通顺的前提下尽量精简；',
      '2. 若为保持逻辑连贯需要更多过渡句，可适当超出（最多不超过 200 词），以表达自然为先，不要为凑字数而省略必要衔接。',
      '',
      '【格式要求】',
      '按以下标记格式输出，不要任何额外文字或 JSON：',
      '标题---英文标题-中文翻译标题',
      '英语正文---英文短文正文',
      '正文翻译---中文对照翻译（逐句对应）',
      '示例：',
      '标题---My School Life-我的校园生活',
      '英语正文---Every morning I go to school happily.',
      '正文翻译---每天早上我都开心地去上学。',
      '确保所有给定单词都出现在英语正文中，且拼写正确。',
    ].join('\n');
  }

  String _userPrompt(List<StoryWord> words, String? title) {
    final buf = StringBuffer();
    buf.writeln('请用以下单词写一篇英文短文：');
    for (final w in words) {
      buf.writeln(
          '- ${w.word}（${w.pos ?? '?'}）: ${w.translation.isEmpty ? '未提供释义' : w.translation}');
    }
    if (title != null && title.isNotEmpty) {
      buf.writeln('短文标题可参考：$title');
    }
    // 随机注入一条变体要求，保证多次生成内容不同
    buf.writeln(_variants[Random().nextInt(_variants.length)]);
    return buf.toString();
  }

  /// 解析 AI 返回的短文（优先标记格式，JSON 兜底）
  Story _parseStory(String raw, List<StoryWord> words) {
    // 1. 标记格式：标题--- / 英语正文--- / 正文翻译---
    final markup = _tryParseMarkup(raw);
    if (markup != null) {
      final title = markup['title'] ?? '';
      return Story(
        title: title.isEmpty ? 'AI 生成的短文' : title,
        content: markup['content'] ?? '',
        translation: markup['translation'] ?? '',
        words: words.map((w) => w.word).toList(),
        source: StorySource.ai,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // 2. JSON 兜底
    final jsonStr = _extractJson(raw);
    if (jsonStr == null) {
      throw const AiException(AiErrorType.parse, 'AI 返回格式无法解析（既不是标记格式也不是 JSON）');
    }
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final content = (map['content'] as String? ?? '').trim();
      if (content.isEmpty) {
        throw const AiException(AiErrorType.parse, 'AI 返回的正文为空');
      }
      return Story(
        title: (map['title'] as String? ?? '').trim().isEmpty
            ? 'AI 生成的短文'
            : (map['title'] as String).trim(),
        content: content,
        translation: (map['translation'] as String? ?? '').trim(),
        words: words.map((w) => w.word).toList(),
        source: StorySource.ai,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException(AiErrorType.parse, 'AI 内容解析失败: $e');
    }
  }

  /// 解析标记格式：标题--- / 英语正文--- / 正文翻译---（含中文/英文标签变体）
  Map<String, String>? _tryParseMarkup(String raw) {
    final sections = <String, String>{};
    final regex = RegExp(
      r'^(标题|Title|英语正文|正文|English\s*Content|Content|正文翻译|中文翻译|翻译|Translation)\s*[—-]+\s*(.*)$',
      caseSensitive: false,
      multiLine: true,
    );
    var currentKey = '';
    final buffer = StringBuffer();

    void flush() {
      if (currentKey.isNotEmpty) {
        sections[currentKey] = buffer.toString().trim();
      }
    }

    for (final line in raw.split('\n')) {
      final m = regex.firstMatch(line.trim());
      if (m != null) {
        flush();
        buffer.clear();
        currentKey = m.group(1)!.toLowerCase();
        final inline = (m.group(2) ?? '').trim();
        if (inline.isNotEmpty) buffer.write(inline);
      } else {
        buffer.write('\n$line');
      }
    }
    flush();

    String get(String key) => sections[key] ?? '';
    final title = get('标题').isNotEmpty ? get('标题') : get('title');
    final content = get('英语正文').isNotEmpty
        ? get('英语正文')
        : (get('正文').isNotEmpty ? get('正文') : get('content'));
    final translation = get('正文翻译').isNotEmpty
        ? get('正文翻译')
        : (get('中文翻译').isNotEmpty
            ? get('中文翻译')
            : get('translation'));

    if (content.isEmpty) return null;
    return {'title': title, 'content': content, 'translation': translation};
  }

  /// 从 AI 输出中提取 JSON 对象（去掉 ```json 包裹、取第一个 { ... } 平衡块）
  String? _extractJson(String raw) {
    var start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    for (var i = start; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return raw.substring(start, i + 1);
        }
      }
    }
    return null;
  }
}
