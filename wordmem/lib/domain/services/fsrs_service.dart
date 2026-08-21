import 'dart:math' as math;
import '../../core/constants/app_constants.dart';
import '../models/review_rating.dart';

/// 卡片状态（数据结构，与具体算法无关）
class FsrsCard {
  final CardState state;
  final double stability;
  final double difficulty;
  final int reps;
  final int lapses;
  final DateTime? due;
  final DateTime? lastReview;
  final double elapsedDays;
  final double scheduledDays;

  const FsrsCard({
    this.state = CardState.newCard,
    this.stability = 0,
    this.difficulty = 0,
    this.reps = 0,
    this.lapses = 0,
    this.due,
    this.lastReview,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
  });

  FsrsCard copyWith({
    CardState? state,
    double? stability,
    double? difficulty,
    int? reps,
    int? lapses,
    DateTime? due,
    DateTime? lastReview,
    double? elapsedDays,
    double? scheduledDays,
  }) =>
      FsrsCard(
        state: state ?? this.state,
        stability: stability ?? this.stability,
        difficulty: difficulty ?? this.difficulty,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
        due: due ?? this.due,
        lastReview: lastReview ?? this.lastReview,
        elapsedDays: elapsedDays ?? this.elapsedDays,
        scheduledDays: scheduledDays ?? this.scheduledDays,
      );

  factory FsrsCard.fromDbMap(Map<String, dynamic> m) => FsrsCard(
        state: CardState.fromString(m['card_state'] as String? ?? 'new'),
        stability: (m['stability'] as num?)?.toDouble() ?? 0,
        difficulty: (m['difficulty'] as num?)?.toDouble() ?? 0,
        reps: (m['reps'] as int?) ?? 0,
        lapses: (m['lapses'] as int?) ?? 0,
        due: m['due'] != null ? DateTime.parse(m['due'] as String) : null,
        lastReview: m['last_review'] != null
            ? DateTime.parse(m['last_review'] as String)
            : null,
        elapsedDays: (m['elapsed_days'] as num?)?.toDouble() ?? 0,
        scheduledDays: (m['scheduled_days'] as num?)?.toDouble() ?? 0,
      );
}

/// 排程结果
class ScheduleResult {
  final FsrsCard card;
  final double retrievability;

  const ScheduleResult({required this.card, this.retrievability = 0});
}

/// 经典艾宾浩斯遗忘曲线复习算法（7 周期）
///
/// 固定复习间隔序列（用户确认版）：
///   [5 分钟, 30 分钟, 12 小时, 1 天, 2 天, 4 天, 7 天]
///   - 前 3 个为短期记忆检测节点（分钟/小时级）
///   - 后 4 个为长期记忆强化节点（天级）
/// - `reps` 表示当前所处的周期（0=新词，1=5分钟后，2=30分钟后……
///   reps=7 对应 7 天后；完成第 7 周期且答对 → 永久掌握）
/// - `stability` 复用为"当前周期间隔天数"，用于遗忘曲线计算
/// - 遗忘曲线：R(t) = e^(-t/S)，S 为当前间隔（记忆强度）
///
/// 评分规则（评分驱动周期推进 / 重做）：
/// - 没想起来 (again) → lapses+1，**重做当前周期**（1 分钟后即可再复习）
/// - 困难 (hard)      → 保持当前周期不变
/// - 正确 (good)      → 进入下一周期
/// - 很轻松 (easy)    → 跳过一档，加速（+2，封顶第 7 周期）
///
/// 状态映射：reps==0 → 新词，reps 1~2 → 学习中（分钟/小时级），
///           reps 3~7 → 复习中，完成第 7 周期 → 已掌握（mastered）。
class FsrsService {
  /// 经典艾宾浩斯 7 周期复习间隔（固定节点，不做目标记忆率微调）
  static const List<Duration> ebbinghausIntervals = [
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 12),
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 4),
    Duration(days: 7),
  ];

  /// 完成全部周期后标记掌握的远期保险时间（正常查询已排除 mastered）
  static const Duration _masteredFuse = Duration(days: 3650);

  late double _desiredRetention;

  FsrsService() {
    _desiredRetention = AppConstants.defaultDesiredRetention;
  }

  double get desiredRetention => _desiredRetention;

  /// 7 周期为固定节点，目标记忆率仅作展示存档，不参与间隔计算。
  void setDesiredRetention(double r) {
    _desiredRetention = r.clamp(
      AppConstants.minDesiredRetention,
      AppConstants.maxDesiredRetention,
    );
  }

  // ============================================================
  //  间隔计算
  // ============================================================

  /// 由复习周期返回基础间隔
  Duration _intervalForReps(int reps) {
    if (reps <= 0) return Duration.zero;
    final idx = math.min(reps - 1, ebbinghausIntervals.length - 1);
    return ebbinghausIntervals[idx];
  }

  /// 艾宾浩斯遗忘曲线 R(t) = e^(-t/S)
  double _forgettingCurve(double elapsedDays, double stability) {
    if (stability <= 0) return 0;
    return math.exp(-elapsedDays / stability).clamp(0.0, 1.0);
  }

  // ============================================================
  //  评分主流程
  // ============================================================

  ScheduleResult review(FsrsCard card, ReviewRating rating, DateTime now) {
    final elapsedDays = card.lastReview != null
        ? now.difference(card.lastReview!).inSeconds / 86400.0
        : 0.0;
    final retrievability = predictRetention(card, now);

    // 已掌握的词防御性处理（正常不会进入复习队列）
    if (card.state == CardState.mastered) {
      return ScheduleResult(card: card, retrievability: retrievability);
    }

    var reps = card.reps;
    var lapses = card.lapses;

    if (reps == 0) {
      // 新词首次复习：先进入第 1 周期（5 分钟）
      reps = 1;
      if (rating == ReviewRating.again) {
        lapses++;
        // 立即重做第 1 周期
      } else if (rating == ReviewRating.easy) {
        reps = 3; // 首次就很轻松，直接跳到 12 小时
      }
    } else {
      switch (rating) {
        case ReviewRating.again:
          lapses++;
          // 重做当前周期：reps 不变
          break;
        case ReviewRating.hard:
          // 保持当前周期
          break;
        case ReviewRating.good:
          reps += 1;
          break;
        case ReviewRating.easy:
          reps += 2; // 跳过一档加速
          break;
      }
    }

    // 完成全部 7 个周期且本轮回答正确 → 永久掌握
    if (reps >= ebbinghausIntervals.length &&
        rating != ReviewRating.again) {
      final mastered = card.copyWith(
        state: CardState.mastered,
        stability: ebbinghausIntervals.length.toDouble(),
        difficulty: 0,
        reps: ebbinghausIntervals.length,
        lapses: lapses,
        due: now.add(_masteredFuse),
        lastReview: now,
        elapsedDays: elapsedDays,
        scheduledDays: 0,
      );
      return ScheduleResult(card: mastered, retrievability: retrievability);
    }

    reps = reps.clamp(1, ebbinghausIntervals.length);

    final interval = _intervalForReps(reps);
    // again：重做当前周期，1 分钟后即可再次复习
    final newDue = rating == ReviewRating.again
        ? now.add(const Duration(minutes: 1))
        : now.add(interval);
    final newStability = interval.inSeconds / 86400.0;
    // reps 1~2 是分钟/小时级短间隔（学习中），reps>=3 进入天级（复习中）
    final newState = reps <= 2 ? CardState.learning : CardState.review;

    final newCard = card.copyWith(
      state: newState,
      stability: newStability,
      difficulty: 0,
      reps: reps,
      lapses: lapses,
      due: newDue,
      lastReview: now,
      elapsedDays: elapsedDays,
      scheduledDays: newStability,
    );

    return ScheduleResult(card: newCard, retrievability: retrievability);
  }

  /// 为新卡创建初始状态（立即可复习）
  FsrsCard createNewCard(DateTime now) {
    return FsrsCard(
      state: CardState.newCard,
      due: now,
      lastReview: null,
    );
  }

  /// 预测当前记忆保持率（艾宾浩斯遗忘曲线）
  double predictRetention(FsrsCard card, DateTime now) {
    if (card.lastReview == null) return 0;
    final elapsed = now.difference(card.lastReview!).inSeconds / 86400.0;
    return _forgettingCurve(elapsed, card.stability);
  }
}
