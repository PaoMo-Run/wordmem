import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import 'root_matcher.dart' show WordRoot;

/// 词根字典加载器（从 assets/data/word_roots.json 加载）
/// 独立成文件以持有 flutter rootBundle 依赖；
/// root_matcher.dart 保持纯 Dart，便于单元测试无需 flutter_tester。
class WordRootDict {
  static WordRootDict? _instance;

  /// 词根按字母长度降序排序：长的先匹配（避免 port 抢在 trans-port 的 port 之前误匹配）
  final List<WordRoot> roots;

  WordRootDict._(this.roots);

  static WordRootDict get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('WordRootDict 未加载，请先调用 load()');
    }
    return i;
  }

  static Future<WordRootDict> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/data/word_roots.json');
    final list = (jsonDecode(raw) as List)
        .map((e) => WordRoot.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.root.length.compareTo(a.root.length));
    _instance = WordRootDict._(list);
    return _instance!;
  }
}
