import 'package:sqlite3/sqlite3.dart';
import '../database/app_database.dart';
import '../../domain/models/word.dart';

/// 词典数据源（只读查询内置词典）
class DictSource {
  final AppDatabase _db;
  DictSource(this._db);

  Database get _d => _db.dict;

  /// 精确查询单词
  DictWord? lookup(String word) {
    final rows = _d.select(
      'SELECT * FROM dict_words WHERE word = ? COLLATE NOCASE LIMIT 1',
      [word],
    );
    if (rows.isNotEmpty) return DictWord.fromMap(rows.first);
    return null;
  }

  /// 词形反查
  /// 输入 "running" -> 返回 "run"（通过 exchange 字段反查）
  DictWord? lookupWithExchange(String word) {
    // 1. 先精确匹配
    var result = lookup(word);
    if (result != null) return result;

    // 2. 通过 exchange 字段反查 + 词干提取
    result = _lookupWithExchangeIn(_d, word);
    return result;
  }

  /// 在指定词典连接上做 exchange 反查 + 词干提取
  DictWord? _lookupWithExchangeIn(Database db, String word) {
    // exchange 格式: "p:ran/d:run/i:running/3:runs"
    final pattern = '%$word%';
    final rows = db.select(
      'SELECT * FROM dict_words WHERE exchange LIKE ? LIMIT 1',
      [pattern],
    );
    if (rows.isNotEmpty) {
      return DictWord.fromMap(rows.first);
    }
    // 尝试去掉常见后缀
    return _stemLookup(db, word);
  }

  /// 简单词干提取
  DictWord? _stemLookup(Database db, String word) {
    final w = word.toLowerCase();
    final candidates = <String>[];

    // -ing
    if (w.endsWith('ing') && w.length > 4) {
      candidates.add(w.substring(0, w.length - 3));
      if (w.endsWith('ing') && w.length > 5 && w[w.length - 4] == w[w.length - 5]) {
        candidates.add(w.substring(0, w.length - 4)); // running -> runn -> run
      }
    }
    // -ed
    if (w.endsWith('ed') && w.length > 3) {
      candidates.add(w.substring(0, w.length - 2));
      if (w.length > 4 && w[w.length - 3] == w[w.length - 4]) {
        candidates.add(w.substring(0, w.length - 3)); // stopped -> stop
      }
    }
    // -s
    if (w.endsWith('s') && w.length > 2) {
      candidates.add(w.substring(0, w.length - 1));
      if (w.endsWith('es') && w.length > 3) {
        candidates.add(w.substring(0, w.length - 2));
      }
    }
    // -ly
    if (w.endsWith('ly') && w.length > 3) {
      candidates.add(w.substring(0, w.length - 2));
    }
    // -er, -est
    if (w.endsWith('er') && w.length > 3) candidates.add(w.substring(0, w.length - 2));
    if (w.endsWith('est') && w.length > 4) candidates.add(w.substring(0, w.length - 3));

    for (final candidate in candidates) {
      final result = _lookupIn(db, candidate);
      if (result != null) return result;
    }
    return null;
  }

  /// 在指定词典连接上精确查询（不跨库，供词干反查内部使用）
  DictWord? _lookupIn(Database db, String word) {
    final rows = db.select(
      'SELECT * FROM dict_words WHERE word = ? COLLATE NOCASE LIMIT 1',
      [word],
    );
    if (rows.isEmpty) return null;
    return DictWord.fromMap(rows.first);
  }

  /// 模糊搜索
  /// - 含中文：按释义（translation）模糊匹配
  /// - 纯英文：单词前缀匹配优先 + 释义模糊匹配补充
  ///   （释义补充使缩写反查可用：搜 "AOA" 命中 "迎角（缩写 AOA）"）
  List<DictWord> search(String query, {int limit = 20}) {
    final q = query.trim();
    if (q.isEmpty) return [];
    final result = <DictWord>[];
    final seen = <String>{};
    for (final w in _searchIn(_d, q, limit: limit)) {
      if (seen.add(w.word.toLowerCase())) {
        result.add(w);
      }
    }
    return result.take(limit).toList();
  }

  /// 在指定词典连接上执行模糊搜索
  List<DictWord> _searchIn(Database db, String query, {int limit = 20}) {
    final q = query.trim();
    if (q.isEmpty) return [];
    // 转义 LIKE 通配符，避免用户输入的 % _ \ 被当作通配
    final escaped = q.replaceAll('\\', '\\\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final isChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
    if (isChinese) {
      final rows = db.select(
        'SELECT * FROM dict_words WHERE translation LIKE ? '
        'ESCAPE \'\\\' ORDER BY bnc ASC LIMIT ?',
        ['%$escaped%', limit],
      );
      return rows.map((r) => DictWord.fromMap(r)).toList();
    }

    // 英文：先按单词前缀匹配
    final byWord = db.select(
      'SELECT * FROM dict_words WHERE word LIKE ? '
      'ESCAPE \'\\\' ORDER BY bnc ASC LIMIT ?',
      ['${escaped.toLowerCase()}%', limit],
    );
    if (byWord.length >= limit) {
      return byWord.map((r) => DictWord.fromMap(r)).toList();
    }
    final seen = <String>{};
    final result = <DictWord>[];
    for (final r in byWord) {
      final w = DictWord.fromMap(r);
      if (seen.add(w.word)) result.add(w);
    }
    // 再补充释义命中（缩写反查：AOA -> 迎角（缩写 AOA））
    // 太短的查询（<3 字符）命中面过广，只搜单词前缀
    if (escaped.length >= 3) {
      final byTrans = db.select(
        'SELECT * FROM dict_words WHERE translation LIKE ? '
        'ESCAPE \'\\\' ORDER BY bnc ASC LIMIT ?',
        ['%$escaped%', limit],
      );
      for (final r in byTrans) {
        if (result.length >= limit) break;
        final w = DictWord.fromMap(r);
        if (seen.add(w.word)) result.add(w);
      }
    }
    return result;
  }

  /// 批量查询多个单词
  Map<String, DictWord> batchLookup(List<String> words) {
    final result = <String, DictWord>{};
    for (final word in words) {
      final dict = lookupWithExchange(word);
      if (dict != null) {
        result[word] = dict;
      }
    }
    return result;
  }

  /// 查找形似词（编辑距离相近的干扰项），用于选单词出题。
  /// 优先返回长度相近、拼写相近、首字母相同的词，避免与正确词同形。
  List<DictWord> lookupSimilar(String word, {int limit = 20}) {
    final w = word.toLowerCase();
    final len = w.length;
    if (w.isEmpty) return [];
    // 按长度 ±1 粗筛，按词频 bnc 升序取一批候选
    final rows = _d.select(
      '''SELECT * FROM dict_words
         WHERE length(word) BETWEEN ? AND ?
           AND lower(word) != ?
         ORDER BY bnc ASC LIMIT 400''',
      [len - 1, len + 1, w],
    );
    final candidates = rows.map((r) => DictWord.fromMap(r)).toList();
    // Dart 端按编辑距离排序（首字母相同优先）
    candidates.sort((a, b) {
      final da = _editDistance(w, a.word.toLowerCase());
      final db = _editDistance(w, b.word.toLowerCase());
      if (da != db) return da.compareTo(db);
      final sa = a.word.toLowerCase().startsWith(w[0]) ? 0 : 1;
      final sb = b.word.toLowerCase().startsWith(w[0]) ? 0 : 1;
      return sa.compareTo(sb);
    });
    return candidates.take(limit).toList();
  }

  /// 编辑距离（Levenshtein）
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final up = prev[j] + 1;
        final left = curr[j - 1] + 1;
        final diag = prev[j - 1] + cost;
        curr[j] = up < left ? (up < diag ? up : diag) : (left < diag ? left : diag);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return curr[b.length];
  }

  /// 词典总词数
  int get wordCount {
    final row = _d.select('SELECT COUNT(*) as c FROM dict_words').first;
    return row['c'] as int;
  }
}
