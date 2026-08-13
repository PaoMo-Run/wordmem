/// 词典单词模型（只读词典查询结果）
class DictWord {
  final String word;
  final String? phonetic;
  final String? pos;
  final String? translation;
  final String? definition;
  final String? exchange;
  final int collins;
  final int oxford;
  final String? tag;
  final int? bnc;
  final int? frq;

  const DictWord({
    required this.word,
    this.phonetic,
    this.pos,
    this.translation,
    this.definition,
    this.exchange,
    this.collins = 0,
    this.oxford = 0,
    this.tag,
    this.bnc,
    this.frq,
  });

  factory DictWord.fromMap(Map<String, dynamic> m) => DictWord(
        word: m['word'] as String,
        phonetic: m['phonetic'] as String?,
        pos: m['pos'] as String?,
        translation: m['translation'] as String?,
        definition: m['definition'] as String?,
        exchange: m['exchange'] as String?,
        collins: (m['collins'] as int?) ?? 0,
        oxford: (m['oxford'] as int?) ?? 0,
        tag: m['tag'] as String?,
        bnc: m['bnc'] as int?,
        frq: m['frq'] as int?,
      );

  /// 获取释义列表（按换行分割）
  List<String> get translationLines =>
      translation?.split('\n').where((s) => s.trim().isNotEmpty).toList() ?? [];

  /// 获取词性列表
  List<String> get posList =>
      pos?.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList() ?? [];

  /// 解析词形关系
  /// exchange 格式: "p:ran/d:run/i:running/3:runs"
  String? exchangeRelation(String input) {
    if (exchange == null) return null;
    final parts = exchange!.split('/');
    const typeMap = {
      'p': '过去式', 'd': '过去式', 'i': '现在分词',
      '3': '第三人称单数', 's': '复数', 'r': '比较级',
      't': '最高级', 'f': '第三人称单数',
    };
    for (final part in parts) {
      final seg = part.split(':');
      if (seg.length == 2 &&
          seg[1].toLowerCase() == input.toLowerCase()) {
        return typeMap[seg[0]] ?? seg[0];
      }
    }
    return null;
  }
}

/// 词典匹配结果（一个单词可能有多个义项）
class DictMatchResult {
  final DictWord dictWord;
  final String? exchangeRelation;

  const DictMatchResult({required this.dictWord, this.exchangeRelation});
}
