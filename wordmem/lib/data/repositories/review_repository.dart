import '../database/app_database.dart';
import '../database/word_dao.dart';
import '../database/review_dao.dart';
import '../../domain/models/review_rating.dart';
import '../../domain/services/fsrs_service.dart';

/// 复习仓库 - FSRS 排程 + 事务写入
class ReviewRepository {
  final AppDatabase _db;
  final WordDao _wordDao;
  final ReviewDao _reviewDao;
  final FsrsService _fsrs;

  ReviewRepository(this._db, this._wordDao, this._reviewDao, this._fsrs);

  /// 获取待复习列表（新词 + 到期词）
  /// 到期词按 due 时间排序（优先复习最该复习的），新词随机打乱（避免按添加顺序出题）
  List<Map<String, dynamic>> getReviewQueue({int limit = 100}) {
    final now = DateTime.now().toUtc().toIso8601String();
    // 先取到期的新词和复习中的词
    final dueWords = _db.vocab
        .select(
          '''SELECT * FROM user_words
         WHERE due <= ? AND card_state != 'new'
         ORDER BY due ASC LIMIT ?''',
          [now, limit],
        )
        .map((r) => r as Map<String, dynamic>)
        .toList();
    // 再取新词（随机出题，不按添加顺序）
    final newWords = _db.vocab
        .select(
          """SELECT * FROM user_words
         WHERE card_state = 'new' AND due <= ?
         ORDER BY created_at ASC LIMIT ?""",
          [now, limit],
        )
        .map((r) => r as Map<String, dynamic>)
        .toList()
      ..shuffle();
    return [...dueWords, ...newWords];
  }

  /// 待复习数量
  int get pendingCount {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = _db.vocab.select(
      'SELECT COUNT(*) as c FROM user_words WHERE due <= ?',
      [now],
    ).first;
    return row['c'] as int;
  }

  /// 提交评分（事务操作）
  void submitReview(int userWordId, ReviewRating rating) {
    _db.transaction(() {
      // 1. 读取当前卡片状态
      final word = _wordDao.getById(userWordId);
      if (word == null) throw Exception('单词不存在');

      // 2. 构建 FSRS 卡片
      final card = FsrsCard.fromDbMap(word);

      // 3. 计算新状态
      final now = DateTime.now().toUtc();
      final result = _fsrs.review(card, rating, now);
      final newCard = result.card;

      // 4. 更新 user_words 卡片状态
      _wordDao.updateCardState(
        userWordId,
        cardState: newCard.state.value,
        stability: newCard.stability,
        difficulty: newCard.difficulty,
        reps: newCard.reps,
        lapses: newCard.lapses,
        due: newCard.due!.toIso8601String(),
        lastReview: now.toIso8601String(),
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
      );

      // 5. 插入复习记录
      _reviewDao.insert(
        userWordId: userWordId,
        rating: rating.value,
        state: card.state.value,
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
        reviewedAt: now.toIso8601String(),
      );
    });
  }

  /// 获取单词复习历史
  List<Map<String, dynamic>> getReviewHistory(int wordId) {
    return _reviewDao.getHistory(wordId);
  }

  /// 降级单词熟悉度（翻卡主观"很轻松"但后续选单词/默写出错时调用）。
  /// 用 again 评分重新排程（回退间隔 + 遗忘次数 +1），但不写复习历史，
  /// 避免与正式评分记录混淆。
  void demoteWord(int userWordId) {
    _db.transaction(() {
      final word = _wordDao.getById(userWordId);
      if (word == null) return;
      final card = FsrsCard.fromDbMap(word);
      final now = DateTime.now().toUtc();
      final result = _fsrs.review(card, ReviewRating.again, now);
      final newCard = result.card;
      _wordDao.updateCardState(
        userWordId,
        cardState: newCard.state.value,
        stability: newCard.stability,
        difficulty: newCard.difficulty,
        reps: newCard.reps,
        lapses: newCard.lapses,
        due: newCard.due!.toIso8601String(),
        lastReview: now.toIso8601String(),
        elapsedDays: newCard.elapsedDays,
        scheduledDays: newCard.scheduledDays,
      );
    });
  }
}
