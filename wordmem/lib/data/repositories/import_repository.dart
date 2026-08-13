import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../database/word_dao.dart';
import '../sources/dict_source.dart';
import '../../domain/models/stats.dart';
import '../../core/utils/tag_utils.dart';

/// 文本批量导入仓库
class ImportRepository {
  final AppDatabase _db;
  final WordDao _wordDao;
  final DictSource _dictSource;

  ImportRepository(this._db, this._wordDao, this._dictSource);

  /// 从文本提取单词并匹配词典
  Future<TextImportResult> importFromText(String text) async {
    // 在 Isolate 中分词（大量文本时）
    final words = await compute(_extractWords, text);

    final matched = <String>[];
    final unmatched = <String>[];
    final seen = <String>{};

    for (final word in words) {
      if (seen.contains(word.toLowerCase())) continue;
      seen.add(word.toLowerCase());

      // 检查是否已在词库中
      if (_wordDao.exists(word)) continue;

      // 词典匹配
      final dictWord = _dictSource.lookupWithExchange(word);
      if (dictWord != null) {
        matched.add(dictWord.word);
      } else {
        unmatched.add(word);
      }
    }

    return TextImportResult(
      matchedWords: matched,
      unmatchedWords: unmatched,
      totalExtracted: words.length,
    );
  }

  /// 批量添加匹配到的单词（查词典填充释义和标签）
  void batchAddWords(List<String> words) {
    _db.transaction(() {
      for (final word in words) {
        if (!_wordDao.exists(word)) {
          // 查词典匹配释义和标签（与手动添加保持一致）
          final dictWord = _dictSource.lookupWithExchange(word);
          final now = DateTime.now().toUtc();
          _wordDao.insert(
            word: word,
            customDef: dictWord?.translation,
            tags: dictWord != null ? TagUtils.convertTags(dictWord.tag) : '',
            due: now.toIso8601String(),
          );
        }
      }
    });
  }
}

/// 分词（在 Isolate 中执行）
List<String> _extractWords(String text) {
  final words = <String>[];
  final regex = RegExp(r"[a-zA-Z][a-zA-Z'\-]*[a-zA-Z]|[a-zA-Z]");
  for (final match in regex.allMatches(text)) {
    final word = match.group(0)!;
    if (word.length >= 2) {
      words.add(word);
    }
  }
  return words;
}
