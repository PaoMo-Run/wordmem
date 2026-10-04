import 'dart:convert';
import 'dart:math' as math;

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
  List<DictWord> searchDict(String query, {int limit = 20}) {
    return _dictSource.search(query, limit: limit);
  }

  /// 词典总词数
  int get dictWordCount => _dictSource.wordCount;

  /// 按词典最新释义批量刷新词库 custom_def（词典校对 v4 后用于旧词同步）。
  /// - 遍历 user_words，以词典 lookup 结果覆盖 custom_def
  /// - 仅当词典命中且释义与当前 custom_def 不同才更新
  /// - 返回实际刷新词数
  int refreshDefinitionsFromDict() {
    final all = _wordDao.getAll(limit: 100000);
    int updated = 0;
    for (final w in all) {
      final wordText = (w['word'] as String? ?? '').trim();
      if (wordText.isEmpty) continue;
      final dictWord = _dictSource.lookupWithExchange(wordText);
      if (dictWord == null) continue;
      final newDef = dictWord.translation ?? '';
      if (newDef.isEmpty) continue;
      final oldDef = (w['custom_def'] as String? ?? '').trim();
      if (oldDef == newDef) continue;
      _wordDao.update(w['id'] as int, customDef: newDef);
      updated++;
    }
    return updated;
  }

  /// 查找单词的近义词（多级匹配）
  /// L1 中文词林义类层 + L2 释义中文关键词重叠层，任一命中即候选，
  /// 再经用户黑名单过滤，按相似度降序返回。
  /// 近义词群（v2.1.7 重做；原先内联在 WordGroupMemoryPage 里）。
  ///
  /// **为什么重做**：旧实现是 `for (final w in words.take(40))` —— 只拿
  /// **最新添加的 40 个词**当种子，而近义词匹配本身是全库扫描的。词库 ≤40 词时
  /// 窗口等于全库（所以早期能出群），涨到 285 词后窗口只覆盖 14%，聚类词
  /// （base/basic/basis、vast/enormous/immense…）全在窗口外 → 群数为 0，
  /// 「近义词群」整块空白（真机反馈 2026-09-17）。
  ///
  /// 本版三点：
  /// - 种子扫**全部**词库，不再截断
  /// - 用倒排索引（核心词 → 词下标）算重叠：释义解析从 O(n²) 次降到 O(n) 次，
  ///   上千词的库也是毫秒级，因此才敢扫全库
  /// - 命中阈值见 [SynonymDetector.minSharedKeywords]；每群至少 [minMembers] 个近义词
  ///
  /// 返回结构（与旧实现一致，页面与熟悉度迁移依赖这三个键）：
  /// `{'id': 核心词, 'seed': 种子词, 'words': [种子, ...成员], 'def': 核心词}`。
  /// 按成员数降序返回，大簇优先展示。
  List<Map<String, dynamic>> buildSynonymGroups({
    int maxGroups = 30,
    int minMembers = 2,
  }) {
    // 1) 参与匹配的词：排除词组（含空格）与空释义
    final words = _wordDao.getAll(limit: 100000).where((w) {
      final text = (w['word'] as String? ?? '').trim();
      return text.isNotEmpty &&
          !text.contains(' ') &&
          ((w['custom_def'] as String?) ?? '').trim().isNotEmpty;
    }).toList();

    // 2) 一次遍历：解析核心词 + 建倒排索引
    final keywordsOf = <int, Set<String>>{};
    final byKeyword = <String, List<int>>{};
    for (var i = 0; i < words.length; i++) {
      final kws = SynonymDetector.extractKeywords(
          (words[i]['custom_def'] as String?) ?? '');
      if (kws.isEmpty) continue;
      keywordsOf[i] = kws;
      for (final k in kws) {
        (byKeyword[k] ??= <int>[]).add(i);
      }
    }

    // 3) 逐种子统计重叠数（走倒排索引，不做逐对解析）
    final groups = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (var i = 0; i < words.length; i++) {
      final kws = keywordsOf[i];
      if (kws == null) continue;

      final overlap = <int, int>{};
      for (final k in kws) {
        for (final j in byKeyword[k] ?? const <int>[]) {
          if (j == i) continue;
          overlap[j] = (overlap[j] ?? 0) + 1;
        }
      }
      final members = <int>[
        for (final e in overlap.entries)
          if (e.value >= SynonymDetector.minSharedKeywords) e.key,
      ];
      if (members.length < minMembers) continue;

      final w = words[i];
      // 群 ID 使用语义核心词（稳定）：成员/种子变化不影响 ID，熟悉度不丢
      final id =
          coreDefinition(w['custom_def'] as String?, w['word'] as String);
      if (seenIds.contains(id)) continue;
      seenIds.add(id);
      groups.add({
        'id': id,
        'seed': w['word'],
        'words': [w['word'], ...members.map((j) => words[j]['word'])],
        'def': id,
      });
      if (groups.length >= maxGroups) break;
    }

    // 4) 成员多的群排前面（大簇更有复习价值）
    groups.sort((a, b) =>
        (b['words'] as List).length.compareTo((a['words'] as List).length));
    return groups;
  }

  /// 近义词判定规则（2026-08-21 收紧 → v2.1.7 回调）：
  /// - 词组（含空格）不参与近义词匹配，只对单个英文单词生效
  /// - L2 释义关键词重叠 ≥ [SynonymDetector.minSharedKeywords]，或词林义类命中且有重叠
  List<Map<String, dynamic>> findSynonyms(int wordId) {
    final word = _wordDao.getById(wordId);
    if (word == null) return [];
    final wordText = (word['word'] as String? ?? '').trim();
    if (wordText.contains(' ')) return []; // 词组不做近义词匹配
    final def = ((word['custom_def'] as String?) ?? '').trim();
    if (def.isEmpty) return [];

    final keywords = SynonymDetector.extractKeywords(def);
    if (keywords.isEmpty) return [];

    final allWords = _wordDao.getAll(limit: 100000).toList();

    final result = <Map<String, dynamic>>[];
    for (final w in allWords) {
      if ((w['id'] as int) == wordId) continue;
      final wWord = (w['word'] as String? ?? '').trim();
      if (wWord.contains(' ')) continue; // 词组不做近义词匹配
      final wDef = ((w['custom_def'] as String?) ?? '').trim();
      if (wDef.isEmpty) continue;
      final wKeywords = SynonymDetector.extractKeywords(wDef);
      if (wKeywords.isEmpty) continue;
      // L2 义项重叠层 + L1 词林义类层
      final inter = keywords.intersection(wKeywords);
      final cilinMatch =
          SynonymDictSource.instance.areSynonymSets(keywords, wKeywords);
      // 命中：释义重叠 ≥ minSharedKeywords（v2.1.7 由 2 降为 1），或词林义类命中且有重叠
      if (inter.length >= SynonymDetector.minSharedKeywords ||
          (cilinMatch && inter.isNotEmpty)) {
        result.add(w);
      }
    }

    // 过滤用户手动屏蔽的错词
    final blocked = _getSynonymBlacklist()[wordText] ?? const {};
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
    blockSynonymByWord(word['word'] as String, blockedWord);
  }

  /// 按单词文本屏蔽一个近义词（无需 id，用于"把当前词移出词林"场景）
  void blockSynonymByWord(String sourceWord, String blockedWord) {
    final map = _getSynonymBlacklist();
    map.putIfAbsent(sourceWord, () => <String>{}).add(blockedWord);
    _savePairList('synonym_blacklist', map);
  }

  /// 屏蔽一个同根词（用户认为不是同根词，加入词根黑名单）
  void blockRootWord(String sourceWord, String blockedWord) {
    final map = getRootBlacklist();
    map.putIfAbsent(sourceWord, () => <String>{}).add(blockedWord);
    _savePairList('root_blacklist', map);
  }

  /// 把某个词从指定词根排除（该词不再属于这个词根，其它词根不受影响）
  void excludeFromRoot(String root, String word) {
    final map = getRootExcluded();
    map.putIfAbsent(root, () => <String>{}).add(word);
    _savePairList('root_excluded', map);
  }

  /// 读取词根排除表：词根 -> 被排除的单词集合
  Map<String, Set<String>> getRootExcluded() => _getPairList('root_excluded');

  /// 持久化"源 -> 集合"黑名单（格式：['a|b', 'c|d']）
  void _savePairList(String key, Map<String, Set<String>> map) {
    final list = <String>[];
    map.forEach((k, v) {
      for (final w in v) {
        list.add('$k|$w');
      }
    });
    _db.vocab.execute(
      '''INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at''',
      [key, jsonEncode(list),
          DateTime.now().toUtc().toIso8601String()],
    );
  }

  /// 读取"源 -> 集合"黑名单（格式：['a|b', 'c|d']）
  Map<String, Set<String>> _getPairList(String key) {
    final rows = _db.vocab
        .select('SELECT value FROM app_settings WHERE key = ?', [key]);
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

  /// 读取词根黑名单：源词 -> 被屏蔽的同根词集合
  Map<String, Set<String>> getRootBlacklist() => _getPairList('root_blacklist');

  /// 读取近义词黑名单：源词 -> 被屏蔽的近义词集合
  Map<String, Set<String>> _getSynonymBlacklist() =>
      _getPairList('synonym_blacklist');

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

  /// 为复习队列生成两环节四选一选项（v2.1.5 统一随机化）。
  ///
  /// 修复旧逻辑的可观察规律 bug：
  /// - 英译汉旧逻辑干扰项按队列顺序取前 3 个其它词 → 每题干扰项几乎固定；
  /// - 汉译英旧逻辑用形似词按编辑距离排序 → 规律性强。
  /// 新逻辑干扰项随机抽选，来源优先级：复习队列其它词（随机）→
  /// 个人词库随机 → 内置词典随机（兜底，保证队列很小时也能凑满 4 选项）。
  /// 每题独立打乱消费干扰池，避免小队列下各题共用同一组干扰项。
  Map<int, ReviewStageOptions> buildReviewStageOptions(
      List<Map<String, dynamic>> queue) {
    final random = math.Random();

    // 各词释义：custom_def 优先，回退词典 translation
    final defs = <int, String>{};
    final wordById = <int, String>{};
    for (final w in queue) {
      final id = w['id'] as int;
      wordById[id] = w['word'] as String;
      var def = ((w['custom_def'] as String?) ?? '').trim();
      if (def.isEmpty) {
        def = (_dictSource.lookup(w['word'] as String)?.translation ?? '').trim();
      }
      defs[id] = def;
    }

    // 随机干扰池（word -> definition），按优先级填充
    final pool = <WordOption>[];
    final poolSeen = <String>{};
    final poolCap = queue.length * 3 + 12;

    // 1) 复习队列其它词（打乱）
    final shuffledQueue = [...queue]..shuffle(random);
    for (final w in shuffledQueue) {
      if (pool.length >= poolCap) break;
      final word = w['word'] as String;
      if (!poolSeen.add(word.toLowerCase())) continue;
      pool.add(WordOption(word: word, definition: defs[w['id'] as int] ?? ''));
    }
    // 2) 个人词库随机补足
    if (pool.length < poolCap) {
      final userAll = _wordDao.getAll(limit: 100000).toList()..shuffle(random);
      for (final w in userAll) {
        if (pool.length >= poolCap) break;
        final word = w['word'] as String;
        if (!poolSeen.add(word.toLowerCase())) continue;
        var def = ((w['custom_def'] as String?) ?? '').trim();
        if (def.isEmpty) {
          def = (_dictSource.lookup(word)?.translation ?? '').trim();
        }
        pool.add(WordOption(word: word, definition: def));
      }
    }
    // 3) 内置词典随机兜底（保证队列很小时也能凑满 4 选项）
    if (pool.length < poolCap) {
      for (final d in _dictSource.randomWords(excludeWord: '', n: 60)) {
        if (pool.length >= poolCap) break;
        if (!poolSeen.add(d.word.toLowerCase())) continue;
        pool.add(WordOption(word: d.word, definition: d.translation ?? ''));
      }
    }

    final result = <int, ReviewStageOptions>{};
    for (final w in queue) {
      final id = w['id'] as int;
      final word = wordById[id]!;
      final correctDef = defs[id] ?? '';

      // 每题独立打乱干扰池，保证各题抽到的干扰项组合不同
      final shuffledPool = [...pool]..shuffle(random);

      // 汉译英：正确单词 + 3 个随机干扰（词不重复）
      final wo = <WordOption>[WordOption(word: word, definition: correctDef)];
      final usedWords = <String>{word.toLowerCase()};
      for (final cand in shuffledPool) {
        if (wo.length >= 4) break;
        if (usedWords.contains(cand.word.toLowerCase())) continue;
        usedWords.add(cand.word.toLowerCase());
        wo.add(cand);
      }

      // 英译汉：正确释义 + 3 个随机干扰（释义非空、互不重复）
      var enToZhOk = correctDef.isNotEmpty;
      final ez = <WordOption>[];
      if (enToZhOk) {
        ez.add(WordOption(word: word, definition: correctDef));
        final usedDefs = <String>{correctDef};
        for (final cand in shuffledPool) {
          if (ez.length >= 4) break;
          if (cand.word.toLowerCase() == word.toLowerCase()) continue;
          final d = cand.definition.trim();
          if (d.isEmpty || !usedDefs.add(d)) continue;
          ez.add(WordOption(word: cand.word, definition: d));
        }
        if (ez.length < 4) enToZhOk = false;
      }

      result[id] = ReviewStageOptions(
        wordOptions: wo..shuffle(random),
        enToZhOptions: ez..shuffle(random),
        enToZhAvailable: enToZhOk,
      );
    }
    return result;
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

  /// 提取中文释义的核心词（用于近义词群卡片标题）
  /// 优先取 SynonymDetector 提取的首个核心词，否则回退释义截断。
  String coreDefinition(String? customDef, String fallback) {
    final def = (customDef ?? '').trim();
    if (def.isEmpty) return fallback;
    final kws = SynonymDetector.extractKeywords(def);
    if (kws.isNotEmpty) return kws.first;
    return def.length > 12 ? '${def.substring(0, 12)}…' : def;
  }

  /// 读取每个近义词群的熟悉度（通过次数，0~4，4=已掌握）
  Map<String, int> getSynonymGroupMastery() => _readIntMap('synonym_group_mastery');

  /// 群 ID 从「成员列表串」升级为「语义核心词」后的旧数据迁移：
  /// - 旧键形如 "abandon|desert|forsake"（成员按字母排序拼接，含 |）
  /// - 新键为群的核心中文词（如 "放弃"）
  /// - 旧键成员与新群成员有交集 → mastery 继承到新键；多个旧群映射到同一新键时取最大值
  /// - 找不到归属的旧键原样保留（不丢数据）
  void migrateSynonymGroupMastery(List<Map<String, dynamic>> groups) {
    if (groups.isEmpty) return;
    final map = getSynonymGroupMastery();
    if (map.isEmpty) return;
    final hasOld = map.keys.any((k) => k.contains('|'));
    if (!hasOld) return;

    final membersByGroup = <String, Set<String>>{
      for (final g in groups)
        g['id'] as String:
            (g['words'] as List).cast<String>().map((w) => w.toLowerCase()).toSet(),
    };
    final migrated = <String, int>{};
    for (final e in map.entries) {
      final oldMembers = e.key.split('|').map((s) => s.toLowerCase()).toSet();
      String? target;
      for (final entry in membersByGroup.entries) {
        if (entry.value.any(oldMembers.contains)) {
          target = entry.key;
          break;
        }
      }
      final dest = target ?? e.key;
      final prev = migrated[dest] ?? 0;
      if (e.value > prev) migrated[dest] = e.value;
    }
    _saveIntMap('synonym_group_mastery', migrated);
  }

  /// 群挑战通过一次：熟悉度 +1（封顶 4），返回新值
  int bumpSynonymGroupMastery(String groupId) {
    final map = getSynonymGroupMastery();
    final cur = map[groupId] ?? 0;
    final next = cur >= 4 ? 4 : cur + 1;
    map[groupId] = next;
    _saveIntMap('synonym_group_mastery', map);
    return next;
  }

  /// 读取每个词根的熟悉度（通过次数，0~4，4=已掌握）
  Map<String, int> getRootMastery() => _readIntMap('root_mastery');

  /// 词根挑战通过一次：熟悉度 +1（封顶 4），返回新值
  int bumpRootMastery(String root) {
    final map = getRootMastery();
    final cur = map[root] ?? 0;
    final next = cur >= 4 ? 4 : cur + 1;
    map[root] = next;
    _saveIntMap('root_mastery', map);
    return next;
  }

  Map<String, int> _readIntMap(String key) {
    try {
      final rows =
          _db.vocab.select('SELECT value FROM app_settings WHERE key = ?', [key]);
      if (rows.isEmpty) return {};
      final raw = jsonDecode(rows.first['value'] as String)
          as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  void _saveIntMap(String key, Map<String, int> map) {
    _db.vocab.execute(
      'INSERT INTO app_settings (key, value, updated_at) '
      'VALUES (?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
      [key, jsonEncode(map), DateTime.now().toUtc().toIso8601String()],
    );
  }

  /// 为一个近义词群生成一道挑战题：
  /// - 正确项 = 组内词（去重，最多 5 个，保证至少 3 个干扰项）
  /// - 干扰项 = 词库内随机取，目标凑满 8 个；词库不足则降配
  /// - requiredCorrect = 正确项 < 3 时须全对，否则答对 3 个即通过
  /// - [exclude]：额外排除的干扰项候选（v2.2.0 需求3：拆子题时排除全群其他成员，
  ///   避免同群词在另一子题中充当干扰项——它们本身就是正确答案）
  /// 返回 null 表示该群无法出题（组内词为空）。
  Map<String, dynamic>? buildGroupChallenge(List<String> groupWords,
      {Set<String> exclude = const {}}) {
    final correct = <String>[];
    for (final w in groupWords) {
      if (correct.length >= 5) break;
      final t = w.trim();
      if (t.isNotEmpty && !correct.contains(t)) correct.add(t);
    }
    if (correct.isEmpty) return null;

    final allWords = _wordDao.getAll(limit: 100000).toList()..shuffle();
    final excludeAll = <String>{...exclude, ...correct};
    final distractors = <String>[];
    final target = 8 - correct.length;
    for (final w in allWords) {
      if (distractors.length >= target) break;
      final ww = w['word'] as String;
      if (excludeAll.contains(ww)) continue;
      distractors.add(ww);
    }

    final options = [...correct, ...distractors]..shuffle();
    return {
      'correct': correct,
      'options': options,
      'requiredCorrect': correct.length < 3 ? correct.length : 3,
    };
  }

  /// v2.2.0 需求3：把词群成员洗牌后切成 ≤[chunkSize] 的子题块，
  /// 保证 >5 词的群在题组内通过多道子题覆盖全部成员（块间不重复）。
  /// 纯函数（可注入 Random），供出题与测试共用。
  static List<List<String>> splitGroupIntoChunks(List<String> groupWords,
      {int chunkSize = 5, math.Random? random}) {
    final pool = groupWords
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList()
      ..shuffle(random);
    final chunks = <List<String>>[];
    for (var i = 0; i < pool.length; i += chunkSize) {
      final end =
          i + chunkSize > pool.length ? pool.length : i + chunkSize;
      chunks.add(pool.sublist(i, end));
    }
    return chunks;
  }

  /// v2.2.0 需求3：为一个词群生成完整题组（单卡题组制）——
  /// 成员洗牌切块后每块一道子题，覆盖全群；干扰项排除全群成员。
  /// 返回空列表表示该群无法出题。
  List<Map<String, dynamic>> buildGroupChallengeSession(
      List<String> groupWords,
      {math.Random? random}) {
    final all = groupWords
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet();
    final session = <Map<String, dynamic>>[];
    for (final chunk in splitGroupIntoChunks(groupWords, random: random)) {
      final challenge =
          buildGroupChallenge(chunk, exclude: all.difference(chunk.toSet()));
      if (challenge != null) session.add(challenge);
    }
    return session;
  }
}
