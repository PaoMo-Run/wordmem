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
    if (rows.isEmpty) return null;
    return DictWord.fromMap(rows.first);
  }

  /// 词形反查
  /// 输入 "running" -> 返回 "run"（通过 exchange 字段反查）
  DictWord? lookupWithExchange(String word) {
    // 1. 先精确匹配
    var result = lookup(word);
    if (result != null) return result;

    // 2. 通过 exchange 字段反查
    // exchange 格式: "p:ran/d:run/i:running/3:runs"
    final pattern = '%$word%';
    final rows = _d.select(
      'SELECT * FROM dict_words WHERE exchange LIKE ? LIMIT 1',
      [pattern],
    );
    if (rows.isNotEmpty) {
      return DictWord.fromMap(rows.first);
    }

    // 3. 尝试去掉常见后缀
    final stemResult = _stemLookup(word);
    return stemResult;
  }

  /// 简单词干提取
  DictWord? _stemLookup(String word) {
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
      final result = lookup(candidate);
      if (result != null) return result;
    }
    return null;
  }

  /// 模糊搜索（前缀匹配）
  List<DictWord> search(String query, {int limit = 20}) {
    final rows = _d.select(
      'SELECT * FROM dict_words WHERE word LIKE ? ORDER BY bnc ASC LIMIT ?',
      ['${query.toLowerCase()}%', limit],
    );
    return rows.map((r) => DictWord.fromMap(r)).toList();
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
