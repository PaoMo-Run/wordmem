import 'dart:convert';
import '../database/app_database.dart';
import '../database/word_dao.dart';
import '../sources/dict_source.dart';
import '../sources/synonym_dict_source.dart';
import '../../domain/models/word.dart';
import '../../domain/models/word_option.dart';
import '../../domain/models/synonym_quiz.dart';
import '../../domain/models/synonym_challenge.dart';
import '../../domain/services/fsrs_service.dart';
import '../../domain/services/synonym_detector.dart';

/// 单词仓库 - 管理词典匹配 + 个人词库写入
class WordRepository {
  final AppDatabase _db;
  final WordDao _wordDao;
  final DictSource _dictSource;
  final FsrsService _fsrs;

  WordRepository(this._db, this._wordDao, this._dictSource, this._fsrs);

  /// 词典匹配（添加单词时使用）
  DictMatchResult? matchWord(String input) {
    final dictWord = _dictSource.lookupWithExchange(input);
    if (dictWord == null) return null;

    // 检查词形关系
    String? relation;
    if (dictWord.word.toLowerCase() != input.toLowerCase()) {
      relation = dictWord.exchangeRelation(input);
      relation ??= '可能是 "${dictWord.word}" 的变形';
    }

    return DictMatchResult(dictWord: dictWord, exchangeRelation: relation);
  }

  /// 检查单词是否已在词库中
  bool exists(String word) => _wordDao.exists(word);

  /// 添加单词到个人词库
  int addWord({
    required String word,
    int senseId = 0,
    String? customDef,
    String note = '',
    String tags = '',
    bool isFavorite = false,
  }) {
    // 创建 FSRS 新卡片
    final now = DateTime.now().toUtc();
    final card = _fsrs.createNewCard(now);

    return _wordDao.insert(
      word: word,
      senseId: senseId,
      customDef: customDef,
      note: note,
      tags: tags,
      isFavorite: isFavorite,
      cardState: card.state.value,
      stability: card.stability,
      difficulty: card.difficulty,
      reps: card.reps,
      lapses: card.lapses,
      due: card.due!.toIso8601String(),
      lastReview: card.lastReview?.toIso8601String(),
      elapsedDays: card.elapsedDays,
      scheduledDays: card.scheduledDays,
    );
  }

  /// 更新单词信息
  void updateWord(int id, {
    String? customDef,
    String? note,
    String? tags,
    bool? isFavorite,
    int? senseId,
  }) {
    _wordDao.update(
      id,
      customDef: customDef,
      note: note,
      tags: tags,
      isFavorite: isFavorite,
      senseId: senseId,
    );
  }

  /// 删除单词
  void deleteWord(int id) => _wordDao.delete(id);

  /// 获取单词详情
  Map<String, dynamic>? getWord(int id) => _wordDao.getById(id);

  /// 获取所有单词（分页）
  List<Map<String, dynamic>> getAllWords({
    int offset = 0,
    int limit = 50,
    String? tagFilter,
    String? stateFilter,
    bool? favoriteOnly,
    String? sortBy,
  }) {
    return _wordDao.getAll(
      offset: offset,
      limit: limit,
      tagFilter: tagFilter,
      stateFilter: stateFilter,
      favoriteOnly: favoriteOnly,
      sortBy: sortBy,
    );
  }

  /// 搜索
  List<Map<String, dynamic>> search(String query) {
    return _wordDao.search(query);
  }

  /// 获取所有标签
  List<String> getAllTags() {
    // 委托给 review_dao 的方法，这里直接查
    final rows = _db.vocab
        .select('SELECT DISTINCT tags FROM user_words WHERE tags != ""');
    final tags = <String>{};
    for (final row in rows) {
      final t = row['tags'] as String;
      t.split(',').forEach((tag) {
        final trimmed = tag.trim();
        if (trimmed.isNotEmpty) tags.add(trimmed);
      });
    }
    return tags.toList()..sort();
  }

  /// 词典搜索（添加单词时）
  List<DictWord> searchDict(String query) {
    return _dictSource.search(query);
  }

  /// 词典总词数
  int get dictWordCount => _dictSource.wordCount;

  /// 查找单词的近义词（多级匹配）
  /// L1 中文词林义类层 + L2 释义中文关键词重叠层，任一命中即候选，
  /// 再经用户黑名单过滤，按相似度降序返回。
  List<Map<String, dynamic>> findSynonyms(int wordId) {
    final word = _wordDao.getById(wordId);
    if (word == null) return [];
    final def = ((word['custom_def'] as String?) ?? '').trim();
    if (def.isEmpty) return [];

    final keywords = SynonymDetector.extractKeywords(def);
    if (keywords.isEmpty) return [];

    final allWords = _wordDao.getAll(limit: 100000).toList();

    final result = <Map<String, dynamic>>[];
    for (final w in allWords) {
      if ((w['id'] as int) == wordId) continue;
      final wDef = ((w['custom_def'] as String?) ?? '').trim();
      if (wDef.isEmpty) continue;
      final wKeywords = SynonymDetector.extractKeywords(wDef);
      if (wKeywords.isEmpty) continue;
      // L2 义项重叠层 + L1 词林义类层，任一命中即视为近义词候选
      final overlap = keywords.intersection(wKeywords).isNotEmpty;
      final cilinMatch =
          SynonymDictSource.instance.areSynonymSets(keywords, wKeywords);
      if (overlap || cilinMatch) {
        result.add(w);
      }
    }

    // 过滤用户手动屏蔽的错词
    final blocked = _getSynonymBlacklist()[word['word'] as String] ?? const {};
    result.removeWhere((w) => blocked.contains(w['word'] as String));

    // 按相似度降序
    result.sort((a, b) {
      final db = ((b['custom_def'] as String?) ?? '');
      final da = ((a['custom_def'] as String?) ?? '');
      return SynonymDetector.similarity(def, db)
          .compareTo(SynonymDetector.similarity(def, da));
    });
    return result;
  }

  /// 屏蔽一个近义词（用户认为不是近义词，加入黑名单）
  void blockSynonym(int wordId, String blockedWord) {
    final word = _wordDao.getById(wordId);
    if (word == null) return;
    final sourceWord = word['word'] as String;
    final map = _getSynonymBlacklist();
    map.putIfAbsent(sourceWord, () => <String>{}).add(blockedWord);

    final list = <String>[];
    map.forEach((k, v) {
      for (final w in v) {
        list.add('$k|$w');
      }
    });
    _db.vocab.execute(
      '''INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at''',
      ['synonym_blacklist', jsonEncode(list),
          DateTime.now().toUtc().toIso8601String()],
    );
  }

  /// 读取近义词黑名单：源词 -> 被屏蔽的近义词集合
  Map<String, Set<String>> _getSynonymBlacklist() {
    final rows = _db.vocab
        .select("SELECT value FROM app_settings WHERE key = 'synonym_blacklist'");
    if (rows.isEmpty) return {};
    final raw = rows.first['value'] as String? ?? '';
    if (raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      final map = <String, Set<String>>{};
      for (final e in list) {
        final parts = e.toString().split('|');
        if (parts.length == 2) {
          map.putIfAbsent(parts[0], () => <String>{}).add(parts[1]);
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// 为指定单词生成一道近义词选择题（无近义词时返回 null）
  SynonymQuiz? buildSynonymQuiz(int wordId) {
    final word = _wordDao.getById(wordId);
    if (word == null) return null;

    final synonyms = findSynonyms(wordId);
    if (synonyms.isEmpty) return null;

    final correct = synonyms.first['word'] as String;

    // 干扰项：词库中非本词、非近义词的随机单词
    final exclude = synonyms.map((s) => s['word'] as String).toSet()
      ..add(word['word'] as String);
    final allWords = _wordDao.getAll(limit: 100000).toList()..shuffle();

    final distractors = <String>[];
    for (final w in allWords) {
      if (distractors.length >= 3) break;
      final wWord = w['word'] as String;
      if (exclude.contains(wWord)) continue;
      distractors.add(wWord);
    }
    if (distractors.length < 3) return null; // 词库太小，无法出题

    final options = [correct, ...distractors]..shuffle();
    return SynonymQuiz(
      word: word['word'] as String,
      correct: correct,
      options: options,
    );
  }

  /// 生成"看中文选英文单词"四选一选项（正确单词 + 词典形似干扰项）。
  /// 每个选项携带释义，供提交后展示核对。
  List<WordOption> buildWordOptions(String correctWord, int total,
      {String? correctDef}) {
    final def = (correctDef != null && correctDef.isNotEmpty)
        ? correctDef
        : (_dictSource.lookup(correctWord)?.translation ?? '');
    final options = <WordOption>[
      WordOption(word: correctWord, definition: def),
    ];

    // 优先从整个词典挑选形似干扰项（考察识别能力）
    final similar =
        _dictSource.lookupSimilar(correctWord, limit: total - 1);
    for (final d in similar) {
      if (options.length >= total) break;
      options.add(WordOption(word: d.word, definition: d.translation ?? ''));
    }

    // 词典形似词不足时，从个人词库随机补足
    if (options.length < total) {
      final allWords = _wordDao.getAll(limit: 100000).toList()..shuffle();
      for (final w in allWords) {
        if (options.length >= total) break;
        final wWord = w['word'] as String;
        if (options.any((o) => o.word.toLowerCase() == wWord.toLowerCase())) {
          continue;
        }
        options.add(WordOption(
          word: wWord,
          definition: (w['custom_def'] as String?) ?? '',
        ));
      }
    }

    return options..shuffle();
  }

  /// 生成近义词挑战题列表（每道题：中文释义 + 8 词，含 2~4 个正确答案）
  List<SynonymChallenge> buildSynonymChallenges({int count = 10}) {
    final allWords = _wordDao.getAll(limit: 100000).toList()..shuffle();
    final challenges = <SynonymChallenge>[];

    for (final seed in allWords) {
      if (challenges.length >= count) break;
      final seedId = seed['id'] as int;
      final seedWord = seed['word'] as String;
      final def = ((seed['custom_def'] as String?) ?? '').trim();
      if (def.isEmpty) continue;

      final synonyms = findSynonyms(seedId);
      if (synonyms.isEmpty) continue;

      // 正确答案 = 种子词 + 近义词（最多 4 个）
      final correct = <String>[seedWord];
      for (final s in synonyms) {
        if (correct.length >= 4) break;
        final w = s['word'] as String;
        if (!correct.contains(w)) correct.add(w);
      }
      if (correct.length < 2) continue;

      // 干扰项
      final exclude = correct.toSet();
      final distractors = <String>[];
      for (final w in allWords) {
        if (distractors.length >= 8 - correct.length) break;
        final wWord = w['word'] as String;
        if (exclude.contains(wWord)) continue;
        distractors.add(wWord);
      }
      if (distractors.length < 8 - correct.length) continue; // 词库太小

      final options = [...correct, ...distractors]..shuffle();
      challenges.add(SynonymChallenge(
        definition: def,
        correct: correct,
        options: options,
      ));
    }
    return challenges;
  }
}
