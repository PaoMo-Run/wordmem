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

/// 艾宾浩斯遗忘曲线复习算法
///
/// 采用经典艾宾浩斯遗忘曲线（Ebbinghaus forgetting curve）思想：
/// - 固定复习间隔序列 [3h, 8h, 1d, 2d, 4d, 7d, 15d, 30d]
///   （记忆衰减最快的前期密集复习，先小时级检测再进入天级，后期拉长）
/// - `reps` 表示复习阶段（0=新词，1=3小时后，2=8小时后，3=1天……封顶 30 天）
/// - `stability` 复用为"当前间隔天数"，用于遗忘曲线计算
/// - 遗忘曲线：R(t) = e^(-t/S)，S 为当前间隔（记忆强度）
///
/// 评分规则（评分驱动阶段推进 / 回退）：
/// - 没想起来 (again) → 遗忘，lapses+1，回退到最短间隔（3 小时）
/// - 困难 (hard)      → 保持当前间隔不变
/// - 正确 (good)      → 进入下一档间隔
/// - 很轻松 (easy)    → 跳过一档，加速
///
/// 状态映射：reps==0 → 新词，reps 1~2 → 学习中（小时级），reps>=3 → 复习中。
class FsrsService {
  late double _desiredRetention;

  /// 艾宾浩斯复习间隔序列（前两项为小时级检测节点，其余为天）
  /// 3 小时 → 8 小时 → 1 天 → 2 天 → 4 天 → 7 天 → 15 天 → 30 天
  static const List<double> ebbinghausIntervals = [
    3 / 24, 8 / 24, 1, 2, 4, 7, 15, 30,
  ];

  FsrsService() {
    _desiredRetention = AppConstants.defaultDesiredRetention;
  }

  double get desiredRetention => _desiredRetention;

  void setDesiredRetention(double r) {
    _desiredRetention = r.clamp(
      AppConstants.minDesiredRetention,
      AppConstants.maxDesiredRetention,
    );
  }

  // ============================================================
  //  间隔计算
  // ============================================================

  /// 由复习阶段计算基础间隔（天）
  double _baseIntervalDays(int reps) {
    if (reps <= 0) return 0;
    final idx = math.min(reps - 1, ebbinghausIntervals.length - 1);
    return ebbinghausIntervals[idx];
  }

  /// 由复习阶段计算实际间隔（含目标记忆率微调：记忆率越高间隔越短）
  Duration _intervalForReps(int reps) {
    final base = _baseIntervalDays(reps);
    if (base <= 0) return Duration.zero;
    final adjusted =
        base * (AppConstants.defaultDesiredRetention / _desiredRetention);
    return Duration(seconds: (adjusted * 86400).round());
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

    var reps = card.reps;
    var lapses = card.lapses;

    if (card.reps == 0) {
      // 新词首次复习
      if (rating == ReviewRating.again) {
        lapses++;
        reps = 1;
      } else if (rating == ReviewRating.easy) {
        reps = 2; // 首次就很轻松，跳到 8 小时
      } else {
        reps = 1; // hard / good：从 3 小时开始
      }
    } else {
      if (rating == ReviewRating.again) {
        lapses++;
        reps = 1; // 遗忘回退到最短间隔
      } else if (rating == ReviewRating.good) {
        reps += 1; // 进入下一档
      } else if (rating == ReviewRating.easy) {
        reps += 2; // 跳过一档加速
      }
      // hard：保持不变
    }

    reps = math.max(reps, 1);

    final interval = _intervalForReps(reps);
    final newDue = now.add(interval);
    final newStability = _baseIntervalDays(reps);
    // reps 1~2 是小时级短间隔（3h/8h，学习中），reps>=3 进入天级（复习中）
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
      scheduledDays: interval.inSeconds / 86400.0,
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
