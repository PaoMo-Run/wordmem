import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/models/review_rating.dart';
import 'package:wordmem/domain/services/fsrs_service.dart';

// T0–T8 九节点时间线单测（v2.2.0）。
//
// 时间线：T0 -1h-> T1 -3h-> T2 -5h-> T3 -12h-> T4 -1d-> T5 -1d-> T6 -2d-> T7 -2d-> T8
//        累计 1h / 4h / 9h / 21h / 45h / 69h / 117h / 165h（约 6.9 天）
//
// 规则沿袭 v2.1.8（**取消「熟练跳过」**），v2.2.0 扩为九节点：
// - 所有词**必须完整走完 9 个节点**，每次测验固定推进一格——不因三环节全对跳档
// - `rating` 因此**不再参与排期计算**，只作为复习记录的评分写入
// - 超期不跳档、不补档；due 锚定本次实际测验时刻
// - 未掌握词的 `difficulty` 不再承载「跳过加速态」，恒为 0
void main() {
  late FsrsService svc;
  final t0 = DateTime.utc(2026, 9, 16, 12);

  setUp(() => svc = FsrsService());

  FsrsCard apply(FsrsCard card, ReviewRating rating, DateTime at) =>
      svc.review(card, rating, at).card;

  group('完整时间线（9 个节点一个不落）', () {
    test('九节点逐档推进，due 与间隔表一致，走完 T8 才掌握', () {
      final intervals = FsrsService.t0t8Intervals;
      expect(intervals.length, 8);

      var card = svc.createNewCard(t0);
      var cursor = t0;

      for (var i = 0; i < intervals.length; i++) {
        card = apply(card, ReviewRating.good, cursor);
        expect(card.reps, i + 1,
            reason: '第 ${i + 1} 次测验后应停在节点 T${i + 1}');
        expect(card.due, cursor.add(intervals[i]),
            reason: 'T${i + 1} 的等待间隔应为 ${intervals[i]}');
        expect(card.state, isNot(CardState.mastered),
            reason: 'T8 未走完前不应判掌握');
        cursor = card.due!;
      }

      // 第 9 次测验 → 越过 T8 → 掌握
      card = apply(card, ReviewRating.good, cursor);
      expect(card.state, CardState.mastered);
      expect(card.reps, 8, reason: 'mastered 落库 reps = 8');
    });

    test('必须做满 9 次测验才掌握', () {
      var card = svc.createNewCard(t0);
      var cursor = t0;
      for (var i = 1; i <= 8; i++) {
        card = apply(card, ReviewRating.easy, cursor);
        expect(card.state, isNot(CardState.mastered),
            reason: '第 $i 次测验后不应掌握（要满 9 次）');
        cursor = card.due!;
      }
      card = apply(card, ReviewRating.easy, cursor);
      expect(card.state, CardState.mastered, reason: '第 9 次测验后掌握');
    });

    test('全程累计跨度为 165 小时（约 6.9 天）', () {
      var card = svc.createNewCard(t0);
      var cursor = t0;
      for (var i = 0; i < FsrsService.t0t8Intervals.length; i++) {
        card = apply(card, ReviewRating.good, cursor);
        cursor = card.due!;
      }
      expect(cursor.difference(t0).inHours, 165);
    });

    test('第 8 次测验进入 T8（reps=8 review 态），不再像旧版直接掌握', () {
      // v2.1.x：reps=7 测验后 next=8 > 7 → 直接 mastered；
      // v2.2.0：next=8 ≤ 8 → 进入「等待 T8」的 review 态（reps=8 合法中间值）
      final card = FsrsCard(
        reps: 7,
        state: CardState.review,
        lastReview: t0,
        due: t0,
      );
      final out = apply(card, ReviewRating.good, t0);
      expect(out.reps, 8);
      expect(out.state, CardState.review,
          reason: 'v2.2.0 起第 8 次测验不毕业，须再走一次 T8');
      expect(out.due, t0.add(const Duration(days: 2)),
          reason: 'T7→T8 等待 2 天');
    });
  });

  group('取消跳过（v2.1.8）：任何评分都不跳档', () {
    test('T1 拿到 easy 也不再跳过 T2（原来会 1→3）', () {
      var card = svc.createNewCard(t0);
      card = apply(card, ReviewRating.good, t0); // T0 → T1
      expect(card.reps, 1);

      card = apply(card, ReviewRating.easy, card.due!); // 原来会直跳 T3
      expect(card.reps, 2, reason: 'v2.1.8 起固定推进一格，不得跳档');
      expect(
        card.due!.difference(card.lastReview!),
        FsrsService.t0t8Intervals[1],
        reason: '按 T2 档的 3 小时等待',
      );
    });

    test('T3 拿到 easy 也不再跳过 T4（原来会 3→5）', () {
      var card = FsrsCard(
        reps: 3,
        state: CardState.learning,
        difficulty: 1, // 存量遗留的「已跳过 T2」标记
        lastReview: t0,
        due: t0,
      );
      card = apply(card, ReviewRating.easy, t0);
      expect(card.reps, 4, reason: 'v2.1.8 起不得跳档');
      expect(card.due!.difference(t0), FsrsService.t0t8Intervals[3],
          reason: 'T4 档为 12 小时（v2.2.0）');
      expect(card.difficulty, 0, reason: '跳过加速态已废弃，未掌握词恒为 0');
      expect(card.state, CardState.learning, reason: 'T4 档 12h 仍属小时级（学习中）');
    });

    test('四种评分推进结果完全一致（评分不再参与排期）', () {
      final base = FsrsCard(
        reps: 2,
        state: CardState.learning,
        lastReview: t0,
        due: t0,
      );
      final expected = t0.add(FsrsService.t0t8Intervals[2]);
      for (final r in [
        ReviewRating.again,
        ReviewRating.hard,
        ReviewRating.good,
        ReviewRating.easy,
      ]) {
        final out = apply(base, r, t0);
        expect(out.reps, 3, reason: '$r 也应推进到下一节点');
        expect(out.due, expected, reason: '$r 的下次间隔应完全相同');
      }
    });

    test('存量已跳过词的 difficulty 会被清 0，但仍按当前 reps 继续', () {
      // 存量数据里 difficulty=2（当年跳了 T2+T4）且 reps=5
      var card = FsrsCard(
        reps: 5,
        state: CardState.review,
        difficulty: 2,
        lastReview: t0,
        due: t0,
      );
      card = apply(card, ReviewRating.good, t0);
      expect(card.reps, 6, reason: '按用户决定：只影响未来，不退回补做');
      expect(card.difficulty, 0);
    });
  });

  group('推进与超期', () {
    test('所有结果都推进（取消「重做当前节点」）', () {
      final base = FsrsCard(
        reps: 2,
        state: CardState.learning,
        lastReview: t0,
        due: t0,
      );
      for (final r in [
        ReviewRating.again,
        ReviewRating.hard,
        ReviewRating.good,
        ReviewRating.easy,
      ]) {
        final out = apply(base, r, t0);
        expect(out.reps, 3, reason: '$r 也应推进到下一节点');
      }
    });

    test('超期不跳档、不补档，due 按本次测验时刻顺延', () {
      final last = t0.subtract(const Duration(days: 30));
      final card = FsrsCard(
        reps: 1,
        state: CardState.learning,
        lastReview: last,
        due: last,
      );
      final out = apply(card, ReviewRating.good, t0);

      expect(out.reps, 2, reason: '超期只推进一档，不补做错过的节点');
      expect(out.due, t0.add(const Duration(hours: 3)),
          reason: 'due 锚定本次实际测验时刻，而非原定到期时刻');
    });

    test('due 始终 = 本次测验时刻 + 相应档位间隔', () {
      final card = FsrsCard(
        reps: 4,
        state: CardState.review,
        lastReview: t0,
        due: t0,
      );
      final out = apply(card, ReviewRating.good, t0);
      expect(out.due, t0.add(const Duration(days: 1)),
          reason: 'T5 档等待 1 天（v2.2.0：T4→T5 由 2d 改为 1d）');
    });
  });

  group('熟练度档位映射（v2.2.0 用户定稿 4-2-2-1 分段）', () {
    test('T0–T3 小试牛刀 / T4–T5 初出茅庐 / T6–T7 炉火纯青 / T8 登峰造极', () {
      const expected = {1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3, 8: 4};
      expected.forEach((reps, level) {
        expect(MasteryStatus.levelOf(reps: reps), level,
            reason: 'reps=$reps（处于 T$reps）应为 $level 档');
      });
    });

    test('reps=9（已越过 T8）与超大值兜底第 4 档（mastered 由 card_state 判定）', () {
      expect(MasteryStatus.levelOf(reps: 9), 4);
      expect(MasteryStatus.levelOf(reps: 100), 4);
    });

    test('新词（未开始）为最低档', () {
      expect(MasteryStatus.levelOf(reps: 0), 1);
    });

    test('四档中文标签递增', () {
      expect(MasteryStatus.level1.label, '小试牛刀');
      expect(MasteryStatus.level2.label, '初出茅庐');
      expect(MasteryStatus.level3.label, '炉火纯青');
      expect(MasteryStatus.level4.label, '登峰造极');
    });
  });

  group('difficulty 语义', () {
    test('未掌握词的 difficulty 恒为 0（跳过加速态已废弃）', () {
      var card = svc.createNewCard(t0);
      for (var i = 0; i < 5; i++) {
        card = apply(card, ReviewRating.easy, card.due ?? t0);
        expect(card.difficulty, 0, reason: '第 ${i + 1} 次测验后仍应为 0');
      }
    });

    test('掌握时 difficulty 被重置（切换为抽检失败计数语义）', () {
      var card = FsrsCard(
        reps: 8, // 处于 T8（v2.2.0 九节点的最后一次测验）
        state: CardState.review,
        difficulty: 2,
        lastReview: t0,
        due: t0,
      );
      card = apply(card, ReviewRating.good, t0);
      expect(card.state, CardState.mastered);
      expect(card.difficulty, 0);
      expect(card.due, t0, reason: '掌握即 due = now，立即进入抽检池');
    });
  });

  group('0–6 分评分体系（v2.1.8）', () {
    test('分档边界：0 / 1–2 / 3–4 / 5–6', () {
      expect(ScoreBand.of(0), ScoreBand.unfamiliar);
      expect(ScoreBand.of(1), ScoreBand.gettingThere);
      expect(ScoreBand.of(2), ScoreBand.gettingThere);
      expect(ScoreBand.of(3), ScoreBand.understood);
      expect(ScoreBand.of(4), ScoreBand.understood);
      expect(ScoreBand.of(5), ScoreBand.clear);
      expect(ScoreBand.of(6), ScoreBand.clear);
      // 越界保护（分数由页面 clamp，这里兜一层）
      expect(ScoreBand.of(-1), ScoreBand.unfamiliar);
      expect(ScoreBand.of(9), ScoreBand.clear);
    });

    test('分档文案与用户定稿一致', () {
      expect(ScoreBand.unfamiliar.label, '不熟悉');
      expect(ScoreBand.gettingThere.label, '刚弄懂');
      expect(ScoreBand.understood.label, '已了解');
      expect(ScoreBand.clear.label, '很清楚');
    });

    test('兼容映射回旧四档评分（review_logs.rating 仍在写）', () {
      expect(ScoreBand.unfamiliar.rating, ReviewRating.again);
      expect(ScoreBand.gettingThere.rating, ReviewRating.hard);
      expect(ScoreBand.understood.rating, ReviewRating.good);
      expect(ScoreBand.clear.rating, ReviewRating.easy);
    });

    test('满分 6 = 三环节 × 2 分：全错且全超时才是 0 分', () {
      // 页面侧算法：6 - 错(N) - 超时(M)，这里用分档端点验证语义
      expect(ScoreBand.of(6 - 0 - 0), ScoreBand.clear, reason: '全对不超时 → 6');
      expect(ScoreBand.of(6 - 1 - 0), ScoreBand.clear, reason: '错 1 次 → 5');
      expect(ScoreBand.of(6 - 3 - 0), ScoreBand.understood, reason: '三环节全错 → 3');
      expect(ScoreBand.of(6 - 3 - 3), ScoreBand.unfamiliar, reason: '全错+全超时 → 0');
    });
  });

  group('复习记录类型（v2.1.8）', () {
    test('kind 解析：quiz 与 review，未知值兜底为 review', () {
      expect(ReviewKind.fromString('quiz'), ReviewKind.quiz);
      expect(ReviewKind.fromString('review'), ReviewKind.review);
      expect(ReviewKind.fromString(null), ReviewKind.review);
      expect(ReviewKind.fromString('whatever'), ReviewKind.review);
    });
  });
}
