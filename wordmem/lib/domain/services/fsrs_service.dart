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
/// 固定复习间隔序列（v2.1.4 用户确认版）：
///   [45 分钟, 3 小时, 8 小时, 1 天, 2 天, 4 天, 7 天]
///   - 前 3 个为短期记忆检测节点（分钟/小时级）
///   - 后 4 个为长期记忆强化节点（天级）
/// - `reps` 表示当前所处的周期（0=新词，1=45分钟后，2=3小时后……
///   reps=7 对应 7 天后；完成第 7 周期且答对 → 永久掌握）
/// - `stability` 复用为"当前周期间隔天数"，用于遗忘曲线计算
/// - 遗忘曲线：R(t) = e^(-t/S)，S 为当前间隔（记忆强度）
///
/// 评分规则（v2.1.8：**评分不再驱动排期**）
/// - 所有词固定按 T0→T1→…→T7 顺序**完整走完 8 个节点**，每次测验推进一格
/// - `rating`（again/hard/good/easy）只作为复习记录的评分写入，不影响间隔
/// - 原「很轻松 → 跳过一档」的加速机制已于 v2.1.8 取消（记忆率下降的补救）
///
/// 状态映射：reps==0 → 新词，reps 1~3 → 学习中（小时级），
///           reps 4~7 → 复习中，完成第 8 次测验（reps 越过 T7）→ 已掌握（mastered）。
class FsrsService {
  /// T0–T7 八节点固定时间线（v2.1.6 用户确认版）。
  ///
  /// 下标 i = 「从 T{i} 到 T{i+1} 的等待时间」：
  ///   T0 -1h-> T1 -3h-> T2 -5h-> T3 -12h-> T4 -1d-> T5 -2d-> T6 -2d-> T7
  /// 累计：1h / 4h / 9h / 21h / 45h / 93h / 141h（约 5.9 天走完全程）。
  static const List<Duration> t0t7Intervals = [
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 5),
    Duration(hours: 12),
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 2),
  ];

  // v2.1.6：已移除原 `_masteredFuse`（掌握后把 due 推到 10 年后）。
  // 现在掌握即 due = now，词进入「熟练词抽检」池——由 due 的推进量管理
  // 抽检间隔（答对 15 天 / 答错 3 天 / 跳过 7 天，见 AppConstants）。

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
  /// （公开访问：熟练词抽检降级时需要按节点档位重排 due）
  Duration intervalForReps(int reps) {
    if (reps <= 0) return Duration.zero;
    final idx = math.min(reps - 1, t0t7Intervals.length - 1);
    return t0t7Intervals[idx];
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

    // ── T0–T7 固定推进（v2.1.8：**取消「熟练跳过」**）──
    //
    // 规则：**所有词都必须完整走完 8 个节点（T0..T7）**，每次测验固定推进一格。
    // 取消原因：原「三环节全对 → 跳过 T2 / T4」会让答得好的词少做 1~2 次测验，
    // 用户实测记忆率下降，故改为不跳档，八次一次不落。
    //
    // ⚠️ 因此 `rating` **不再参与任何排期计算**：它只按新的 0–6 分评分体系
    // 写进复习记录（供「单词详情 → 复习历史」展示），不影响下次间隔。
    // 这与「必须完整 8 次」是一体的：间隔固定，次数才固定。
    final next = card.reps + 1;
    final interval = intervalForReps(next);

    // 走完 T7 → 永久掌握，转入「熟练词抽检」池
    if (next > t0t7Intervals.length) {
      final mastered = card.copyWith(
        state: CardState.mastered,
        stability: t0t7Intervals.length.toDouble(),
        difficulty: 0, // 语义切换为「抽检失败计数」，从 0 开始
        reps: t0t7Intervals.length,
        lapses: card.lapses,
        due: now, // 立即进入抽检池
        lastReview: now,
        elapsedDays: elapsedDays,
        scheduledDays: 0,
      );
      return ScheduleResult(card: mastered, retrievability: retrievability);
    }

    final newStability = interval.inSeconds / 86400.0;
    // T1~T3 为小时级（学习中），T4 起进入天级（复习中）
    final newState = next <= 3 ? CardState.learning : CardState.review;

    final newCard = card.copyWith(
      state: newState,
      stability: newStability,
      // v2.1.8：未掌握词的 `difficulty` 不再承载「跳过加速态」，恒写 0
      // （已掌握词的 `difficulty` 仍是抽检失败计数，与本函数无关）
      difficulty: 0,
      reps: next,
      lapses: card.lapses,
      due: now.add(interval),
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
