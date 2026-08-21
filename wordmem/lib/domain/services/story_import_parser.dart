import 'dart:convert';
import '../models/story.dart';

/// 短文导入解析器：把用户从其它 AI App 复制/分享来的文本，
/// 自动解析为 Story（标题 / 英文正文 / 中文对照 / 重点词列表），
/// 用户无需手动填写任何一部分。
///
/// 兼容形态：
/// 1. JSON（{title, content, translation, words?}）
/// 2. 文本 + 【重点词】声明行（AI 按剪贴板提示词输出）
/// 3. 英文段落 + 中文段落（中英对照）
/// 4. 纯英文单段
///
/// 重点词解析优先级：JSON words 字段 → 【重点词】/Key words: 行 → 正文自动提取（兜底）
class StoryImportParser {
  /// 解析导入文本，返回 Story（source=manual，未入库）
  Story parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw ArgumentError('导入内容为空');
    }

    // 1. 尝试 JSON（含 words 字段优先）
    final jsonStory = _tryParseJson(text);
    if (jsonStory != null) return jsonStory;

    // 2. 尝试标记格式：标题--- / 英语正文--- / 正文翻译---
    final markupStory = _tryParseMarkup(text);
    if (markupStory != null) return markupStory;

    // 3. 尝试提取【重点词】声明行（从文本中移除后再拆正文）
    final declaredWords = _extractDeclaredWords(text);
    var cleanText = _removeDeclaredWordsLine(text);
    // 剔除「中文对照 / 翻译」等中英分隔标签行（独立成行时，避免混入翻译内容）
    cleanText = _removeSectionLabelLines(cleanText);

    // 3. 按行拆分，识别标题与正文
    final lines = cleanText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw ArgumentError('导入内容为空');
    }

    final blocks = _splitBlocks(cleanText);
    final enBlock = blocks.where(_isMostlyEnglish).join('\n').trim();
    final zhBlock = blocks.where((b) => !_isMostlyEnglish(b)).join('\n').trim();

    String title = '';
    String content;
    String translation = zhBlock;

    if (enBlock.isNotEmpty) {
      // 英文部分：首行若较短视为标题
      final enLines =
          enBlock.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (enLines.length > 1 && enLines.first.length <= 60) {
        title = enLines.first;
        content = enLines.skip(1).join('\n');
      } else {
        content = enBlock;
      }
    } else {
      // 没有英文块：整段作为正文
      content = cleanText;
    }

    if (content.isEmpty) {
      content = cleanText;
    }

    return Story(
      title: title,
      content: content,
      translation: translation,
      words: declaredWords.isNotEmpty ? declaredWords : _extractWords(content),
      source: StorySource.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// 解析标记格式：标题--- / 英语正文--- / 正文翻译---
  /// （兼容中文/英文标签变体；重点词仍从【重点词】声明行提取）
  Story? _tryParseMarkup(String raw) {
    // 先移除【重点词】声明行，避免混入正文/翻译（声明行单独提取）
    final clean = _removeDeclaredWordsLine(raw);
    final sections = <String, String>{};
    final regex = RegExp(
      r'^(标题|Title|英语正文|正文|English\s*Content|Content|正文翻译|中文翻译|翻译|Translation)\s*[—-]+\s*(.*)$',
      caseSensitive: false,
    );
    var currentKey = '';
    final buffer = StringBuffer();

    void flush() {
      if (currentKey.isNotEmpty) {
        sections[currentKey] = buffer.toString().trim();
      }
    }

    for (final line in clean.split(RegExp(r'\r?\n'))) {
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

    // 重点词：优先【重点词】声明行，否则正文提取
    final declared = _extractDeclaredWords(raw);
    final words = declared.isNotEmpty ? declared : _extractWords(content);

    return Story(
      title: title,
      content: content,
      translation: translation,
      words: words,
      source: StorySource.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// 尝试解析 JSON 形态（容忍 ```json 包裹与噪声）
  Story? _tryParseJson(String raw) {
    var start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    String? jsonStr;
    for (var i = start; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          jsonStr = raw.substring(start, i + 1);
          break;
        }
      }
    }
    if (jsonStr == null) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final content = (map['content'] as String? ?? '').trim();
      if (content.isEmpty) return null;

      // 优先取 JSON 中声明的 words
      List<String> words = const [];
      final wordsRaw = map['words'];
      if (wordsRaw is List) {
        words = wordsRaw
            .whereType<String>()
            .map((w) => w.trim())
            .where((w) => w.isNotEmpty)
            .toList();
      }
      if (words.isEmpty) {
        words = _extractWords(content);
      }

      return Story(
        title: (map['title'] as String? ?? '').trim(),
        content: content,
        translation: (map['translation'] as String? ?? '').trim(),
        words: words,
        source: StorySource.manual,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 提取【重点词】声明行中的单词列表（支持中英文标记）
  List<String> _extractDeclaredWords(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      // 匹配：【重点词】word1, word2... / Key words: word1, word2...
      final match = RegExp(r'^(?:【重点词】|重点词[:：]|Key\s*words?[:：])\s*(.+)$', caseSensitive: false)
          .firstMatch(trimmed);
      if (match == null) continue;
      final list = match.group(1) ?? '';
      final words = list
          .split(RegExp(r'[,，;；\s]+'))
          .map((w) => w.trim())
          .where((w) => RegExp("^[A-Za-z][A-Za-z'-]*\$").hasMatch(w))
          .toList();
      if (words.isNotEmpty) return words;
    }
    return const [];
  }

  /// 移除文本中的【重点词】声明行（避免它混入正文/翻译）
  String _removeDeclaredWordsLine(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final kept = lines.where((line) {
      final trimmed = line.trim();
      return !RegExp(r'^(?:【重点词】|重点词[:：]|Key\s*words?[:：])', caseSensitive: false)
          .hasMatch(trimmed);
    }).toList();
    return kept.join('\n');
  }

  /// 剔除中英分隔标签行（独立成行时）：中文对照 / 翻译 / 译文 / Translation 等。
  /// 这些行是 AI 输出的章节标记，不应进入翻译内容。
  String _removeSectionLabelLines(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final kept = lines.where((line) {
      final t = line.trim();
      return !RegExp(
        r'^(?:【?中文对照】?|【?中文翻译】?|【?翻译】?|【?译文】?|Chinese\s*Translation|English\s*Translation|Translation|【?正文】?|Content)$',
        caseSensitive: false,
      ).hasMatch(t);
    }).toList();
    return kept.join('\n');
  }

  /// 按空行拆块
  List<String> _splitBlocks(String text) {
    return text
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
  }

  /// 判断一块文本是否以英文为主
  bool _isMostlyEnglish(String block) {
    if (block.isEmpty) return false;
    final asciiLetters =
        block.replaceAll(RegExp(r'[^A-Za-z\s]'), '').trim();
    if (asciiLetters.isEmpty) return false;
    final cjk = block.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '').length;
    return cjk < block.length * 0.4;
  }

  /// 从正文提取单词（去重，保留出现顺序，限 25 个）
  List<String> _extractWords(String content) {
    final seen = <String>{};
    final result = <String>[];
    final matches =
        RegExp(r"[A-Za-z][A-Za-z'-]*").allMatches(content).toList();
    // 排除常见停用词，避免单词标签被虚词淹没
    const stop = {
      'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at',
      'for', 'with', 'by', 'from', 'as', 'is', 'are', 'was', 'were', 'be',
      'been', 'being', 'it', 'its', 'this', 'that', 'these', 'those', 'i',
      'you', 'he', 'she', 'we', 'they', 'my', 'your', 'his', 'her', 'our',
      'their', 'me', 'him', 'us', 'them', 'not', 'no', 'yes', 'do', 'does',
      'did', 'have', 'has', 'had', 'will', 'would', 'can', 'could', 'should',
      'may', 'might', 'must', 'there', 'here', 'what', 'which', 'who', 'when',
      'where', 'why', 'how', 'all', 'any', 'some', 'more', 'most', 'other',
      'about', 'into', 'than', 'then', 'so', 'if', 'because', 'just', 'very',
      'also', 'too', 'up', 'out', 'off', 'over', 'under', 'again', 'once',
      'only', 'own', 'same', 'such', 'each', 'both', 'one', 'two', 'three',
    };
    for (final m in matches) {
      final raw = m[0] ?? '';
      final w = raw.toLowerCase();
      if (stop.contains(w)) continue;
      if (seen.add(w)) {
        result.add(raw);
        if (result.length >= 25) break;
      }
    }
    return result;
  }
}
