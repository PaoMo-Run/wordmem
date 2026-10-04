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

/// 经典艾宾浩斯遗忘曲线复习算法（T0–T8 九节点）
///
/// 固定复习间隔序列（v2.2.0 用户确认版）：
///   [1 小时, 3 小时, 5 小时, 12 小时, 1 天, 1 天, 2 天, 2 天]
///   - 前 4 个为短期记忆检测节点（小时级）
///   - 后 4 个为长期记忆强化节点（天级）
/// - `reps` 表示下一个要执行的节点序号（0=新词，1=1小时后，2=3小时后……
///   reps=8 对应 T8；完成第 9 次测验（越过 T8）→ 已掌握）
/// - `stability` 复用为"当前周期间隔天数"，用于遗忘曲线计算
/// - 遗忘曲线：R(t) = e^(-t/S)，S 为当前间隔（记忆强度）
///
/// 评分规则（v2.1.8：**评分不再驱动排期**）
/// - 所有词固定按 T0→T1→…→T8 顺序**完整走完 9 个节点**，每次测验推进一格
/// - `rating`（again/hard/good/easy）只作为复习记录的评分写入，不影响间隔
/// - 原「很轻松 → 跳过一档」的加速机制已于 v2.1.8 取消（记忆率下降的补救）
///
/// 状态映射：reps==0 → 新词，reps 1~3 → 学习中（小时级），
///           reps 4~8 → 复习中，完成第 9 次测验（reps 越过 T8）→ 已掌握（mastered）。
class FsrsService {
  /// T0–T8 九节点固定时间线（v2.2.0 用户确认版）。
  ///
  /// 下标 i = 「从 T{i} 到 T{i+1} 的等待时间」：
  ///   T0 -1h-> T1 -3h-> T2 -5h-> T3 -12h-> T4 -1d-> T5 -1d-> T6 -2d-> T7 -2d-> T8
  /// 累计：1h / 4h / 9h / 21h / 45h / 69h / 117h / 165h（约 6.9 天走完全程）。
  static const List<Duration> t0t8Intervals = [
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 5),
    Duration(hours: 12),
    Duration(days: 1),
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 2),
  ];

  // v2.1.6：已移除原 `_masteredFuse`（掌握后把 due 推到 10 年后）。
  // 现在掌握即 due = now，词进入「熟练词抽检」池——由 due 的推进量管理
  // 抽检间隔（答对 10 天 / 答错 2 天 / 跳过 7 天，见 AppConstants）。

  /// 实际生效的时间线（v2.2.0 学习节奏可调）。
  ///
  /// 默认 = [t0t8Intervals]（编译期常量保留为「默认档」来源）；
  /// 构造时可注入自定义时间线（`ScheduleTuning.timeline`），长度恒为 8
  /// （节点数固定，见 ScheduleTuning.clamped 的钳制）。
  final List<Duration> intervals;

  late double _desiredRetention;

  /// [intervals] 可选：不传 = 默认时间线（现有测试与调用点零改动兼容）。
  FsrsService([List<Duration>? intervals])
      : intervals = intervals ?? t0t8Intervals {
    _desiredRetention = AppConstants.defaultDesiredRetention;
  }

  double get desiredRetention => _desiredRetention;

  /// 九节点为固定时间线，目标记忆率仅作展示存档，不参与间隔计算。
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
  /// （公开访问：熟练词抽检降级时需要按节点档位重排 due；
  /// 读 [intervals] —— 默认档或注入的自定义时间线）
  Duration intervalForReps(int reps) {
    if (reps <= 0) return Duration.zero;
    final idx = math.min(reps - 1, intervals.length - 1);
    return intervals[idx];
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

    // ── T0–T8 固定推进（v2.1.8 取消跳档；v2.2.0 扩为九节点）──
    //
    // 规则：**所有词都必须完整走完 9 个节点（T0..T8）**，每次测验固定推进一格。
    // 取消原因：原「三环节全对 → 跳过 T2 / T4」会让答得好的词少做 1~2 次测验，
    // 用户实测记忆率下降，故改为不跳档，九次一次不落。
    //
    // ⚠️ 因此 `rating` **不再参与任何排期计算**：它只按新的 0–6 分评分体系
    // 写进复习记录（供「单词详情 → 复习历史」展示），不影响下次间隔。
    // 这与「必须完整 9 次」是一体的：间隔固定，次数才固定。
    final next = card.reps + 1;
    final interval = intervalForReps(next);

    // 走完 T8 → 永久掌握，转入「熟练词抽检」池
    if (next > intervals.length) {
      final mastered = card.copyWith(
        state: CardState.mastered,
        stability: intervals.length.toDouble(),
        difficulty: 0, // 语义切换为「抽检失败计数」，从 0 开始
        reps: intervals.length,
        lapses: card.lapses,
        due: now, // 立即进入抽检池
        lastReview: now,
        elapsedDays: elapsedDays,
        scheduledDays: 0,
      );
      return ScheduleResult(card: mastered, retrievability: retrievability);
    }

    final newStability = interval.inSeconds / 86400.0;
    // T1~T4 为小时级（学习中），T5 起进入天级（复习中）（v2.2.0：T4 档为 12h）
    final newState = next <= 4 ? CardState.learning : CardState.review;

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
