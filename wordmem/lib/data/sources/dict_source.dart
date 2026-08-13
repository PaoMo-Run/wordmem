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

  /// 词典总词数
  int get wordCount {
    final row = _d.select('SELECT COUNT(*) as c FROM dict_words').first;
    return row['c'] as int;
  }
}
