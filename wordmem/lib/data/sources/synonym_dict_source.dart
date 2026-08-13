import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// 中文同义词词林（哈工大信息检索研究中心扩展版）数据源。
///
/// 提供「中文核心词 → 义类编码」的查询，用于近义词多级匹配的 L1 层：
/// 两个中文核心词的义类编码前 5 位（小组级）相同即判定为近义，
/// 解决「高兴 / 愉快」这类中文表述不同但语义相同导致的漏报。
///
/// 数据：assets/dict/synonym_cilin.json（约 4.5 万词条，1.1MB）。
class SynonymDictSource {
  SynonymDictSource._();

  static final SynonymDictSource instance = SynonymDictSource._();

  Map<String, List<String>> _wordToCodes = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 加载词林数据（应用启动时调用一次，失败静默降级到义项重叠匹配）
  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/dict/synonym_cilin.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _wordToCodes =
          map.map((k, v) => MapEntry(k, (v as List).cast<String>()));
    } catch (_) {
      _wordToCodes = {};
    } finally {
      _loaded = true;
    }
  }

  /// 查询词的所有义类编码（未收录返回空列表）
  List<String> codesOf(String word) => _wordToCodes[word] ?? const [];

  /// 判断两个核心词集合是否存在词林近义关系（L1 层）
  bool areSynonymSets(Set<String> s1, Set<String> s2) {
    if (s1.isEmpty || s2.isEmpty) return false;
    for (final a in s1) {
      final ca = codesOf(a);
      if (ca.isEmpty) continue;
      for (final b in s2) {
        final cb = codesOf(b);
        if (cb.isEmpty) continue;
        for (final x in ca) {
          for (final y in cb) {
            if (_match(x, y)) return true;
          }
        }
      }
    }
    return false;
  }

  /// 义类编码前 5 位（小组级）相同即视为近义
  bool _match(String a, String b) {
    final len = a.length < b.length ? a.length : b.length;
    if (len < 5) return a == b;
    return a.substring(0, 5) == b.substring(0, 5);
  }
}
