/// 近义词检测工具
///
/// 基于中文释义的"义项"重叠做启发式检测：
/// 将释义按分隔符切成义项，提取每个义项的中文核心词（去掉"的/地/得"等虚词后缀），
/// 若两个单词共享核心词则判定为近义词候选。
///
/// 相比字符 bigram 方案，义项级匹配更精确，能显著降低误报。
/// 说明：仍是轻量启发式，非语义级判断，配合"用户删除错词"功能使用。
class SynonymDetector {
  SynonymDetector._();

  /// 虚词后缀（作为义项结尾时去掉，如"高兴的"→"高兴"）
  static const String _suffixes = '的地得等之';

  /// 单字虚词（过滤，避免"的/了/在"等造成误匹配）
  static const Set<String> _stopChars = {
    '的', '了', '在', '是', '和', '与', '或', '及', '而', '且',
    '并', '被', '把', '使', '让', '对', '从', '向', '于', '为',
    '之', '其', '这', '那', '等', '着', '过', '得', '地',
    '个', '种', '些', '所', '以', '因', '如', '若', '虽', '然',
    '但', '可', '能', '会', '要', '就', '都', '也', '还', '又',
    '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
    '人', '物', '事', '有', '无', '不', '没', '很', '更', '最',
  };

  /// 无意义的整词停用表
  static const Set<String> _stopWords = {
    '这个', '那个', '一个', '一种', '用于', '进行', '表示', '使得', '相关',
    '以及', '或者', '等等', '具有', '没有', '不是', '就是', '可以', '能够',
    '可能', '应该', '所有', '有的', '某些', '任何', '每个', '各种',
    '状态', '行为', '性质', '程度', '方式', '过程', '结果', '事物',
    '东西', '事情', '情况', '方面', '部分', '其他', '有关', '属于',
  };

  /// 提取释义中的中文核心词集合
  static Set<String> extractKeywords(String definition) {
    if (definition.isEmpty) return {};
    final result = <String>{};

    // 去掉词性标记（如 n. v. adj.）和括号内容
    var cleaned = definition.replaceAll(RegExp(r'[a-zA-Z]+\.'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'[（(【\[].*?[)）】\]]'), ' ');

    // 按义项分隔符切分
    final items = cleaned.split(RegExp(r'[；;，,、\n/]+'));
    for (var item in items) {
      item = item.trim();
      if (item.isEmpty) continue;
      // 提取纯中文（去掉残留英文、数字、标点）
      final cn = item.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
      if (cn.isEmpty) continue;

      // 去掉末尾虚词后缀（如"高兴的"→"高兴"）
      var core = cn;
      while (core.length > 1 && _suffixes.contains(core[core.length - 1])) {
        core = core.substring(0, core.length - 1);
      }
      if (core.isEmpty) continue;
      // 过滤停用词
      if (_stopWords.contains(core)) continue;
      // 单字且为虚词 → 过滤
      if (core.length == 1 && _stopChars.contains(core)) continue;
      result.add(core);
    }
    return result;
  }

  /// 判断两个释义是否互为近义词候选
  static bool isSynonym(String def1, String def2) {
    if (def1.isEmpty || def2.isEmpty) return false;
    final k1 = extractKeywords(def1);
    final k2 = extractKeywords(def2);
    if (k1.isEmpty || k2.isEmpty) return false;
    return k1.intersection(k2).isNotEmpty;
  }

  /// 计算两个释义的相似度（0-1，Jaccard），用于排序近义词候选
  static double similarity(String def1, String def2) {
    final k1 = extractKeywords(def1);
    final k2 = extractKeywords(def2);
    if (k1.isEmpty || k2.isEmpty) return 0;
    final inter = k1.intersection(k2).length;
    final union = k1.union(k2).length;
    return union == 0 ? 0 : inter / union;
  }
}
