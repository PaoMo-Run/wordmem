import 'dart:convert';
import 'dart:math';

import '../../core/constants/app_constants.dart';
import 'fsrs_service.dart';

/// 学习节奏配置（v2.2.0 阶段 C）。
///
/// 把三类时间参数集中成一个可持久化的配置对象：
/// - **复习时间线** `timelineMinutes`：8 段（T0→T1 … T7→T8），单位分钟。
///   ⚠️ 节点数**固定 8 段 / 9 节点**：毕业判据 `next > 8`、`MasteryStatus.levelOf`
///   的 9 元素映射表、`clampLegacyRepsForT0T8` 全部与「8」绑定——本类在
///   [clamped] 里对长度做硬校验，长度不对整体回落默认，绝不放开节点数。
/// - **提前背窗口** `upcomingHours`（首页「即将到期」提示 + 提前背队列共用）。
/// - **熟练词抽检** 5 参数（单次词量 / 答对 / 答错 / 跳过 / 短冷却）。
///
/// 生效语义（不回溯）：`due` 是每次复习结算时现算的，改配置对全部词（含在飞
/// 的老词）生效，只是从「下一次结算」开始；已经写进 `due` 的那一格不变。
///
/// 持久化：`app_settings` 表、键前缀 `tune.`、值一律字符串（见 [toSettings]）。
/// 键缺失 / 版本不符 / 解析失败 / 越界 → 静默回落默认档，绝不因脏配置崩 App。
class ScheduleTuning {
  /// 时间线段数（T0→T1 … T7→T8）。**硬约束：不可放开**（见类注释）。
  static const int timelineSegments = 8;

  /// 单段时间线钳制：10 分钟 ~ 30 天
  static const int minSegmentMinutes = 10;
  static const int maxSegmentMinutes = 43200;

  /// 预设档「密集」时间线的构造层下限（标准 ×0.5 后每段不短于 30 分钟）。
  ///
  /// 与 [minSegmentMinutes]（10 分钟，自定义输入的最终闸）是两层：
  /// 当前标准档最小段是 1h，×0.5 = 30min 恰好不可达；未来标准档某段 < 1h 时
  /// 这层护栏才开始咬合。
  static const int presetMinSegmentMinutes = 30;

  /// 抽检单次词量钳制
  static const int minQuizCount = 1;
  static const int maxQuizCount = 20;

  /// 各「天」参数钳制
  static const int minIntervalDays = 1;
  static const int maxIntervalDays = 60;

  /// 提前背窗口钳制（小时）
  static const int minUpcomingHours = 1;
  static const int maxUpcomingHours = 24;

  /// 设置键版本：不符 → 整体回落默认（见 [tryParse]）
  static const int settingsVersion = 1;

  /// 8 段（T0→T1 … T7→T8），单位分钟
  final List<int> timelineMinutes;

  /// 提前背窗口（小时）
  final int upcomingHours;

  /// 抽检：单次词量 / 答对冷却 / 答错复检 / 跳过 / 短冷却（天）
  final int quizCount;
  final int quizCorrectDays;
  final int quizWrongDays;
  final int quizSkipDays;
  final int quizShortCooldownDays;

  /// 预设档标识：standard | intensive | relaxed | custom。
  ///
  /// ⚠️ 仅作 UI 回显的落库兜底；**展示时一律以 [resolvedPresetId] 反推为准**
  /// （手改一格 / 恢复旧备份 / 手改 db 都可能让本字段与实际值错位）。
  final String presetId;

  const ScheduleTuning({
    required this.timelineMinutes,
    required this.upcomingHours,
    required this.quizCount,
    required this.quizCorrectDays,
    required this.quizWrongDays,
    required this.quizSkipDays,
    required this.quizShortCooldownDays,
    required this.presetId,
  });

  // ───────────────── 默认档 / 预设档 ─────────────────

  /// 默认档：**全部取编译期常量**（时间线来自 `FsrsService.t0t8Intervals`，
  /// 其余来自 AppConstants——阶段 B 调完常量后这里自动跟随，禁止硬编码数值）。
  static ScheduleTuning defaults() => ScheduleTuning(
        timelineMinutes: [
          for (final d in FsrsService.t0t8Intervals) d.inMinutes,
        ],
        upcomingHours: AppConstants.upcomingDueWindowHours,
        quizCount: AppConstants.masteredQuizCount,
        quizCorrectDays: AppConstants.masteredQuizCorrectDays,
        quizWrongDays: AppConstants.masteredQuizWrongDelay.inDays,
        quizSkipDays: AppConstants.masteredQuizSkipDelay.inDays,
        quizShortCooldownDays: AppConstants.masteredQuizShortCooldown.inDays,
        presetId: 'standard',
      );

  /// 预设档：**倍率作用于标准档现值**（不随手编数字），倍率结果一律
  /// `.round()` 取整（这是唯一的取整规则，测试断言以此为准）。
  static ScheduleTuning preset(String id) {
    switch (id) {
      case 'intensive':
        // 密集：时间线 ×0.5（构造层下限 30 分钟）；抽检更频繁、冷却更短
        return _fromStandard(
          presetId: 'intensive',
          timelineScale: 0.5,
          timelineClampMin: presetMinSegmentMinutes,
          upcomingHours: 6,
          quizCountScale: 1.4,
          quizCorrectScale: 0.6,
          quizWrongScale: 0.5,
          quizWrongMin: 1,
          quizSkipScale: 0.6,
          quizShortScale: 0.6,
        ).clamped();
      case 'relaxed':
        // 保守：时间线 ×2（上限 30 天）；抽检更稀疏、冷却更长
        return _fromStandard(
          presetId: 'relaxed',
          timelineScale: 2.0,
          timelineClampMax: maxSegmentMinutes,
          upcomingHours: 2,
          quizCountScale: 0.6,
          quizCorrectScale: 2.0,
          quizWrongScale: 1.5,
          quizSkipScale: 1.5,
          quizShortScale: 1.5,
        ).clamped();
      case 'standard':
      default:
        return defaults();
    }
  }

  /// 按倍率从标准档派生预设（集中一处，取整规则只有 [ScheduleTuning.preset]
  /// 文档里声明的 `.round()` 一种）。
  static ScheduleTuning _fromStandard({
    required String presetId,
    required double timelineScale,
    int? timelineClampMin,
    int? timelineClampMax,
    required int upcomingHours,
    required double quizCountScale,
    required double quizCorrectScale,
    required double quizWrongScale,
    int? quizWrongMin,
    required double quizSkipScale,
    required double quizShortScale,
  }) {
    int scaled(int base, double scale, {int? min, int? max}) {
      var v = (base * scale).round();
      if (min != null && v < min) v = min;
      if (max != null && v > max) v = max;
      return v;
    }

    final wrong = max(
      quizWrongMin ?? minIntervalDays,
      scaled(AppConstants.masteredQuizWrongDelay.inDays, quizWrongScale),
    );
    return ScheduleTuning(
      timelineMinutes: [
        for (final d in FsrsService.t0t8Intervals)
          scaled(d.inMinutes, timelineScale,
              min: timelineClampMin, max: timelineClampMax),
      ],
      upcomingHours: upcomingHours,
      quizCount:
          scaled(AppConstants.masteredQuizCount, quizCountScale),
      quizCorrectDays:
          scaled(AppConstants.masteredQuizCorrectDays, quizCorrectScale),
      quizWrongDays: wrong,
      quizSkipDays:
          scaled(AppConstants.masteredQuizSkipDelay.inDays, quizSkipScale),
      quizShortCooldownDays: scaled(
          AppConstants.masteredQuizShortCooldown.inDays, quizShortScale),
      presetId: presetId,
    );
  }

  // ───────────────── 解析 / 持久化 ─────────────────

  /// 从 `app_settings` 读出的键值对解析；任何不合法（版本不符 / 缺键 /
  /// 非数字 / 时间线长度不是 8）→ 返回 null，调用方回落 [defaults]。
  static ScheduleTuning? tryParse(Map<String, String> raw) {
    try {
      if (raw['tune.version'] != '$settingsVersion') return null;
      final timelineRaw = raw['tune.timeline'];
      if (timelineRaw == null) return null;
      final decoded = jsonDecode(timelineRaw);
      if (decoded is! List || decoded.length != timelineSegments) return null;
      final minutes = <int>[];
      for (final e in decoded) {
        if (e is! num) return null;
        minutes.add(e.round());
      }
      return ScheduleTuning(
        timelineMinutes: minutes,
        upcomingHours: int.parse(raw['tune.upcoming_hours']!),
        quizCount: int.parse(raw['tune.quiz_count']!),
        quizCorrectDays: int.parse(raw['tune.quiz_correct_days']!),
        quizWrongDays: int.parse(raw['tune.quiz_wrong_days']!),
        quizSkipDays: int.parse(raw['tune.quiz_skip_days']!),
        quizShortCooldownDays:
            int.parse(raw['tune.quiz_short_cooldown_days']!),
        presetId: raw['tune.preset'] ?? 'custom',
      ).clamped();
    } catch (_) {
      return null;
    }
  }

  /// 写入 `app_settings` 的键值对（值一律字符串；与 [tryParse] 严格互逆）
  Map<String, String> toSettings() => {
        'tune.version': '$settingsVersion',
        'tune.preset': presetId,
        'tune.timeline': jsonEncode(timelineMinutes),
        'tune.upcoming_hours': '$upcomingHours',
        'tune.quiz_count': '$quizCount',
        'tune.quiz_correct_days': '$quizCorrectDays',
        'tune.quiz_wrong_days': '$quizWrongDays',
        'tune.quiz_skip_days': '$quizSkipDays',
        'tune.quiz_short_cooldown_days': '$quizShortCooldownDays',
      };

  /// 越界钳制；时间线长度不是 8 → **整体回落默认档**（节点数是硬约束）。
  ScheduleTuning clamped() {
    if (timelineMinutes.length != timelineSegments) return defaults();
    return ScheduleTuning(
      timelineMinutes: [
        for (final m in timelineMinutes)
          m.clamp(minSegmentMinutes, maxSegmentMinutes),
      ],
      upcomingHours:
          upcomingHours.clamp(minUpcomingHours, maxUpcomingHours),
      quizCount: quizCount.clamp(minQuizCount, maxQuizCount),
      quizCorrectDays:
          quizCorrectDays.clamp(minIntervalDays, maxIntervalDays),
      quizWrongDays: quizWrongDays.clamp(minIntervalDays, maxIntervalDays),
      quizSkipDays: quizSkipDays.clamp(minIntervalDays, maxIntervalDays),
      quizShortCooldownDays:
          quizShortCooldownDays.clamp(minIntervalDays, maxIntervalDays),
      presetId: presetId,
    );
  }

  /// 复制并替换字段（页面编辑草稿用；`presetId` 不传则保持原值，
  /// 手改字段后由 [resolvedPresetId] 反推展示，落库字段仅作兜底）。
  ScheduleTuning copyWith({
    List<int>? timelineMinutes,
    int? upcomingHours,
    int? quizCount,
    int? quizCorrectDays,
    int? quizWrongDays,
    int? quizSkipDays,
    int? quizShortCooldownDays,
    String? presetId,
  }) =>
      ScheduleTuning(
        timelineMinutes: timelineMinutes ?? this.timelineMinutes,
        upcomingHours: upcomingHours ?? this.upcomingHours,
        quizCount: quizCount ?? this.quizCount,
        quizCorrectDays: quizCorrectDays ?? this.quizCorrectDays,
        quizWrongDays: quizWrongDays ?? this.quizWrongDays,
        quizSkipDays: quizSkipDays ?? this.quizSkipDays,
        quizShortCooldownDays:
            quizShortCooldownDays ?? this.quizShortCooldownDays,
        presetId: presetId ?? this.presetId,
      );

  // ───────────────── 派生值 ─────────────────

  /// 时间线（分钟 → Duration），供 `FsrsService(intervals)` 注入
  List<Duration> get timeline =>
      [for (final m in timelineMinutes) Duration(minutes: m)];

  /// 按实际值反推预设归属：与某个预设**全字段一致** → 该预设；否则 custom。
  ///
  /// 这是 UI 展示的唯一口径（`presetId` 字段只是落库兜底），消灭
  /// 「手改一格仍显示标准 / 恢复备份后显示错档」的整类撒谎问题。
  String get resolvedPresetId {
    for (final id in const ['standard', 'intensive', 'relaxed']) {
      if (_sameValues(preset(id))) return id;
    }
    return 'custom';
  }

  /// 预设中文名（基于 [resolvedPresetId]，展示不撒谎）
  String get presetDisplayName => switch (resolvedPresetId) {
        'standard' => '标准',
        'intensive' => '密集',
        'relaxed' => '保守',
        _ => '自定义',
      };

  bool _sameValues(ScheduleTuning o) {
    if (timelineMinutes.length != o.timelineMinutes.length) return false;
    for (var i = 0; i < timelineMinutes.length; i++) {
      if (timelineMinutes[i] != o.timelineMinutes[i]) return false;
    }
    return upcomingHours == o.upcomingHours &&
        quizCount == o.quizCount &&
        quizCorrectDays == o.quizCorrectDays &&
        quizWrongDays == o.quizWrongDays &&
        quizSkipDays == o.quizSkipDays &&
        quizShortCooldownDays == o.quizShortCooldownDays;
  }
}
