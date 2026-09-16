import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/models/review_rating.dart';
import 'package:wordmem/domain/services/fsrs_service.dart';

// T0–T7 八节点时间线与跳过规则单测（v2.1.6）。
//
// 时间线：T0 -1h-> T1 -3h-> T2 -5h-> T3 -12h-> T4 -1d-> T5 -2d-> T6 -2d-> T7
//        累计 1h / 4h / 9h / 21h / 45h / 93h / 141h（约 5.9 天）
//
// 规则：
// - 所有测验结果**都会推进**到下一个节点（取消"重做当前节点"）
// - **只有三环节全对（easy）才解锁跳过**
// - T1 全对 → 跳过 T2（等 8h = 被跳过的 3h + T3 的 5h）
// - T3 全对（且 T1 全对过）→ 跳过 T4（等 24h，不累计 T4 的 12h）
// - T1 未全对 → 全程禁止跳过
// - 超期不跳档、不补档；due 锚定本次实际测验时刻
void main() {
  late FsrsService svc;
  final t0 = DateTime.utc(2026, 9, 16, 12);

  setUp(() => svc = FsrsService());

  FsrsCard apply(FsrsCard card, ReviewRating rating, DateTime at) =>
      svc.review(card, rating, at).card;

  group('完整时间线（不跳过）', () {
    test('八节点逐档推进，due 与间隔表一致，走完 T7 才掌握', () {
      final intervals = FsrsService.t0t7Intervals;
      expect(intervals.length, 7);

      var card = svc.createNewCard(t0);
      var cursor = t0;

      for (var i = 0; i < intervals.length; i++) {
        card = apply(card, ReviewRating.good, cursor);
        expect(card.reps, i + 1,
            reason: '第 ${i + 1} 次测验后应停在节点 T${i + 1}');
        expect(card.due, cursor.add(intervals[i]),
            reason: 'T${i + 1} 的等待间隔应为 ${intervals[i]}');
        expect(card.state, isNot(CardState.mastered),
            reason: 'T7 未走完前不应判掌握');
        cursor = card.due!;
      }

      card = apply(card, ReviewRating.good, cursor);
      expect(card.state, CardState.mastered);
    });

    test('不跳过路径累计跨度为 141 小时（约 5.9 天）', () {
      var card = svc.createNewCard(t0);
      var cursor = t0;
      for (var i = 0; i < FsrsService.t0t7Intervals.length; i++) {
        card = apply(card, ReviewRating.good, cursor);
        cursor = card.due!;
      }
      expect(cursor.difference(t0).inHours, 141);
    });
  });

  group('跳过规则', () {
    test('T1 全对 → 跳过 T2，等 8h 直达 T3', () {
      var card = svc.createNewCard(t0);
      card = apply(card, ReviewRating.good, t0); // T0 → T1
      expect(card.reps, 1);

      card = apply(card, ReviewRating.easy, card.due!); // T1 全对
      expect(card.reps, 3, reason: '应跳过 T2 直达 T3');
      expect(card.skipState, 1);
      expect(
        card.due!.difference(card.lastReview!).inHours,
        8,
        reason: '被跳过的 T2 仍占 3h，加 T3 的 5h 合计 8h',
      );
    });

    test('T3 全对（且 T1 全对过）→ 跳过 T4，等 24h 直达 T5', () {
      var card = svc.createNewCard(t0);
      card = apply(card, ReviewRating.good, t0);
      card = apply(card, ReviewRating.easy, card.due!); // 跳 T2
      card = apply(card, ReviewRating.easy, card.due!); // T3 全对 → 跳 T4

      expect(card.reps, 5);
      expect(card.skipState, 2);
      expect(
        card.due!.difference(card.lastReview!).inHours,
        24,
        reason: '跳过 T4 直接按 T5 档等待 1 天（不累计 T4 的 12h）',
      );
    });

    test('T1 未全对 → 全程禁止跳过（T3 全对也不能跳 T4）', () {
      var card = svc.createNewCard(t0);
      card = apply(card, ReviewRating.good, t0); // T0 → T1
      card = apply(card, ReviewRating.good, card.due!); // T1 非全对 → T2
      expect(card.reps, 2);
      expect(card.skipState, 0);

      card = apply(card, ReviewRating.easy, card.due!); // T2 即使是全对
      expect(card.reps, 3, reason: 'T2 不参与跳过判定，正常推进');

      card = apply(card, ReviewRating.easy, card.due!); // T3 全对
      expect(card.reps, 4, reason: 'T1 未全对 → T3 全对也不允许跳 T4');
      expect(card.skipState, 0);
      expect(card.due!.difference(card.lastReview!).inHours, 12,
          reason: '走 T4 的正常间隔');
    });

    test('双跳过路径：reps 0→1→3→5→6→7，第 6 次测验即掌握', () {
      var card = svc.createNewCard(t0);
      final seen = <int>[];
      var cursor = t0;

      // 前 5 次：仍在复习路径中，不掌握
      for (var i = 0; i < 5; i++) {
        card = apply(card, ReviewRating.easy, cursor);
        seen.add(card.reps);
        expect(card.state, isNot(CardState.mastered));
        cursor = card.due!;
      }
      expect(seen, [1, 3, 5, 6, 7]);

      // 第 6 次：走完 T7 → 掌握
      card = apply(card, ReviewRating.easy, cursor);
      expect(card.state, CardState.mastered);
    });

    test('双跳过路径只剩 T5/T6/T7 时不再跳档', () {
      var card = FsrsCard(
        reps: 5,
        state: CardState.review,
        difficulty: 2,
        lastReview: t0,
        due: t0,
      );
      card = apply(card, ReviewRating.easy, t0);
      expect(card.reps, 6, reason: 'T6 是必测项');
      expect(card.due!.difference(t0).inDays, 2);
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
      expect(out.due, t0.add(const Duration(days: 1)));
    });
  });

  group('熟练度档位映射（4 档）', () {
    test('未跳过路径：每 2 个节点升 1 档', () {
      const expected = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4};
      expected.forEach((reps, level) {
        expect(
          MasteryStatus.levelOf(reps: reps, skipState: 0),
          level,
          reason: 'reps=$reps 应为 $level 档',
        );
      });
    });

    test('双跳过路径：T1 起即为 2 档、T6 为 3 档、T7 为 4 档', () {
      expect(MasteryStatus.levelOf(reps: 1, skipState: 0), 1); // T0
      expect(MasteryStatus.levelOf(reps: 3, skipState: 1), 2); // T1
      expect(MasteryStatus.levelOf(reps: 5, skipState: 2), 2); // T3
      expect(MasteryStatus.levelOf(reps: 6, skipState: 2), 3); // T5
      expect(MasteryStatus.levelOf(reps: 7, skipState: 2), 3); // T6
      expect(MasteryStatus.levelOf(reps: 8, skipState: 2), 4); // T7
    });

    test('新词（未开始）为最低档', () {
      expect(MasteryStatus.levelOf(reps: 0, skipState: 0), 1);
    });

    test('四档中文标签递增', () {
      expect(MasteryStatus.level1.label, '小试牛刀');
      expect(MasteryStatus.level2.label, '初出茅庐');
      expect(MasteryStatus.level3.label, '炉火纯青');
      expect(MasteryStatus.level4.label, '登峰造极');
    });
  });

  group('跳过资格撤销（T3 未全对）', () {
    test('T1 全对跳过 T2 后，T3 未全对 → skipState 撤销为 0', () {
      var card = svc.createNewCard(t0);
      card = apply(card, ReviewRating.good, t0); // T0 → T1
      card = apply(card, ReviewRating.easy, card.due!); // T1 全对 → 跳 T2
      expect(card.skipState, 1);
      expect(card.reps, 3);

      card = apply(card, ReviewRating.good, card.due!); // T3 未全对
      expect(card.skipState, 0, reason: '跳过资格被撤销');
      expect(card.reps, 4, reason: '按原路线走 T4');
      expect(card.due!.difference(card.lastReview!).inHours, 12);
    });

    test('撤销后按不跳过表继续，档位不跳变', () {
      expect(MasteryStatus.levelOf(reps: 4, skipState: 0), 2); // T3 完成
      expect(MasteryStatus.levelOf(reps: 5, skipState: 0), 3); // T4 完成
    });
  });

  group('skipState 语义（复用 difficulty）', () {
    test('未掌握时 skipState 读 difficulty；已掌握时恒为 0', () {
      const learning = FsrsCard(
        reps: 3,
        state: CardState.learning,
        difficulty: 1,
      );
      expect(learning.skipState, 1);

      const mastered = FsrsCard(state: CardState.mastered, difficulty: 1);
      expect(mastered.skipState, 0,
          reason: '已掌握时 difficulty 承载抽检失败计数，不再表示加速态');
    });

    test('掌握时 difficulty 被重置（切换为抽检计数语义）', () {
      var card = FsrsCard(
        reps: 7,
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
}
