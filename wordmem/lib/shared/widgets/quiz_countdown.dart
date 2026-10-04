import 'dart:async';
import 'package:flutter/material.dart';

/// 作答倒计时（v2.1.8）
///
/// 职责全部集中在这里，页面只负责「取一次判定结果」：
/// 1. **计时**：每题开始时打点；[questionKey] 变化即视为换题、重新开始；
/// 2. **超时判定**：页面在该题作答/跳过的那一刻调 [QuizCountdownState.isOvertime]；
/// 3. **息屏 / 切后台回来自动重置**：用户中途有事（锁屏、接电话、切出去）
///    不该被扣掉超时分——监听生命周期，`resumed` 时重新打点继续倒数；
/// 4. **显示**：题干上方的圆形进度环（剩几秒 + 限时说明）。
///
/// ⚠️ 为什么判定放在这里，而不是各页面自己维护一个时间戳：
/// 三环节 + 自选复习 + 抽检共 4 处调用，且**「跳过」路径不经过卡片回调**
/// （页面点头部的「下一题」直接前进）。统一在这里暴露 `isOvertime`，
/// 任何路径都不会漏判，也不会出现四份各自实现的时间戳。
///
/// 用法：
/// ```dart
/// final _cdKey = GlobalKey<QuizCountdownState>();
/// ...
/// QuizCountdown(
///   key: _cdKey,
///   limit: AppConstants.quizTimeLimitChoice,
///   questionKey: '${_stage.name}-$_index-${_word['id']}',
///   frozen: _currentAnswered,
/// )
/// ...
/// final overtime = _cdKey.currentState?.isOvertime ?? false;
/// ```
class QuizCountdown extends StatefulWidget {
  const QuizCountdown({
    super.key,
    required this.limit,
    required this.questionKey,
    this.frozen = false,
  });

  /// 该题的作答限时（英译汉 / 选单词 5 秒，默写 8 秒）
  final Duration limit;

  /// 「当前是哪一题」的标识，变化即重新开始计时。
  /// 用 `'${stage}-$index-${wordId}'` 即可（同时覆盖换环节与换词）。
  final Object questionKey;

  /// 已作答 / 已跳过 → 停止计时并冻结在最终状态
  /// （避免用户看答案反馈时还在倒数，也避免把反馈时间算进下一题）
  final bool frozen;

  @override
  State<QuizCountdown> createState() => QuizCountdownState();
}

class QuizCountdownState extends State<QuizCountdown>
    with WidgetsBindingObserver {
  late DateTime _startedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _startTicker();
  }

  @override
  void didUpdateWidget(QuizCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedQuestion = oldWidget.questionKey != widget.questionKey;
    final unfrozen = oldWidget.frozen && !widget.frozen;
    if (changedQuestion || unfrozen) {
      restart();
    } else if (oldWidget.frozen != widget.frozen) {
      _startTicker(); // 冻结 → 停表；解冻 → 复表
      if (mounted) setState(() {});
    }
  }

  /// 重新开始计时（换题 / 息屏回来 / 页面主动调用）
  void restart() {
    _startedAt = DateTime.now();
    _startTicker();
    if (mounted) setState(() {});
  }

  void _startTicker() {
    _ticker?.cancel();
    if (widget.frozen) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        _ticker?.cancel();
        return;
      }
      setState(() {}); // 环与秒数都按「现在」实时算，不需要每帧存状态
    });
  }

  /// 从本题打点到现在经过的时间
  Duration get elapsed => DateTime.now().difference(_startedAt);

  /// 本题是否已超时 —— 页面在作答 / 跳过的那一刻取值
  bool get isOvertime => elapsed >= widget.limit;

  /// 剩余比例 0..1（超时后恒 0）
  double get remainingRatio {
    final total = widget.limit.inMilliseconds;
    if (total <= 0) return 0;
    final left = total - elapsed.inMilliseconds;
    return (left / total).clamp(0.0, 1.0);
  }

  /// 剩余整秒（向上取整：限时 5 秒时最初显示 5）
  int get remainingSeconds {
    final left = widget.limit.inMilliseconds - elapsed.inMilliseconds;
    if (left <= 0) return 0;
    return (left / 1000).ceil();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 仅处理「回到前台」：息屏 / 切后台期间不计时，回来后重新打点。
    // 注意只在未作答时重置——已作答的题应保留它当时的判定结果。
    if (state == AppLifecycleState.resumed && !widget.frozen) restart();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = remainingRatio;
    final overtime = isOvertime;

    // 配色：充裕 → 主色；剩余不足 40% → 警示；已超时 → 错误色
    final Color color;
    if (overtime) {
      color = scheme.error;
    } else if (ratio <= 0.4) {
      color = scheme.tertiary;
    } else {
      color = scheme.primary;
    }

    return Semantics(
      label: overtime
          ? '本题已超时'
          : '本题剩余 $remainingSeconds 秒，限时 ${widget.limit.inSeconds} 秒',
      child: SizedBox(
        // 固定高度：避免秒数从两位数变一位数时发生跳动
        height: 36,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 底环（未走完的轨道）
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 3,
                      color: scheme.onSurface.withValues(alpha: 0.12),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 3,
                      strokeCap: StrokeCap.round,
                      color: color,
                    ),
                  ),
                  Text(
                    '$remainingSeconds',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              overtime ? '已超时' : '限时 ${widget.limit.inSeconds} 秒',
              style: theme.textTheme.labelSmall?.copyWith(
                color: overtime
                    ? scheme.error
                    : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                fontWeight: overtime ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
