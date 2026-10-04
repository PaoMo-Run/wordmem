import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/core/constants/app_constants.dart';
import 'package:wordmem/data/repositories/review_repository.dart';

// 抽检 / 出题顺序机制单测。
//
// 不变量：
// 1. 冷却期内不重复 —— 被抽中的词 due 推后，冷却期内不得再次出现
// 2. 时间权重 0.5 —— 时间倾向仍存在，但不再是硬排序（v2.1.7 恢复随机化）
// 3. 长期不遗漏 —— 连续抽取足够多次后，池中每个词都被抽到过
void main() {
  Map<String, dynamic> w(int id, int due) => {'id': id, 'due': due};

  List<int> idsOf(List<Map<String, dynamic>> rows) =>
      [for (final r in rows) r['id'] as int];

  group('epochMillisOf（时间解析）', () {
    test('ISO 串可解析；缺失/脏数据排到最后（约定 double.maxFinite）', () {
      expect(
        ReviewRepository.epochMillisOf('2026-09-17T04:00:00.000Z'),
        DateTime.parse('2026-09-17T04:00:00.000Z').millisecondsSinceEpoch,
      );
      expect(ReviewRepository.epochMillisOf(null), double.maxFinite);
      expect(ReviewRepository.epochMillisOf('not-a-date'), double.maxFinite);
    });
  });

  group('blendByTimeWeight（时间权重混合打分）', () {
    // 30 个词：id 越大 = 添加越晚（时间上越"优先"）
    final rows = <Map<String, dynamic>>[
      for (var i = 0; i < 30; i++)
        {
          'id': i,
          'created_at': DateTime.utc(2026, 9, 1)
              .add(Duration(hours: i))
              .toIso8601String(),
        },
    ];
    double timeOf(Map<String, dynamic> r) =>
        ReviewRepository.epochMillisOf(r['created_at']);

    test('timeWeight = 1.0 → 完全按时间（等价于 v2.1.6 的硬排序）', () {
      final ordered = ReviewRepository.blendByTimeWeight(
        rows,
        timeOf: timeOf,
        timeWeight: 1.0,
        ascending: false,
      );
      expect(idsOf(ordered), [for (var i = 29; i >= 0; i--) i]);
    });

    test('w = 0.5 时不再恒等于时间序 —— 随机化回归（v2.1.6 的 bug 是顺序恒等于时间序）',
        () {
      final pureTime = [for (var i = 29; i >= 0; i--) i].join(',');
      final rnd = Random(20260917);
      var diffRounds = 0;
      for (var i = 0; i < 20; i++) {
        final order = idsOf(ReviewRepository.blendByTimeWeight(
          rows,
          timeOf: timeOf,
          ascending: false,
          random: rnd,
        )).join(',');
        if (order != pureTime) diffRounds++;
      }
      expect(
        diffRounds,
        greaterThan(15),
        reason: '20 轮里绝大多数顺序都应与纯时间序不同，否则等于没有随机化',
      );
    });

    test('w = 0.5 时时间倾向仍保留：最近添加的词平均位置明显靠前，但不是恒定第一', () {
      final rnd = Random(7);
      var newestPos = 0;
      var oldestPos = 0;
      var newestIsFirst = 0;
      const rounds = 40;

      for (var i = 0; i < rounds; i++) {
        final ordered = ReviewRepository.blendByTimeWeight(
          rows,
          timeOf: timeOf,
          ascending: false,
          random: rnd,
        );
        final ids = idsOf(ordered);
        newestPos += ids.indexOf(29);
        oldestPos += ids.indexOf(0);
        if (ids.first == 29) newestIsFirst++;
      }

      expect(newestPos / rounds, lessThan(oldestPos / rounds),
          reason: '最新添加的词必须仍被时间倾向照顾');
      expect(newestIsFirst, lessThan(rounds),
          reason: '不能永远是第一，否则时间权重等于 1.0');
    });

    test('不可解析的时间排到最后，且不受排序方向影响（取负会把它顶到队首）', () {
      final withDirty = <Map<String, dynamic>>[
        {'id': 1, 'created_at': '2026-09-01T00:00:00.000Z'},
        {'id': 2, 'created_at': null},
        {'id': 3, 'created_at': 'garbage'},
        {'id': 4, 'created_at': '2026-09-05T00:00:00.000Z'},
      ];
      double t(Map<String, dynamic> r) =>
          ReviewRepository.epochMillisOf(r['created_at']);

      // 升序方向：脏数据在最后
      final asc = idsOf(ReviewRepository.blendByTimeWeight(
        withDirty,
        timeOf: t,
        timeWeight: 1.0,
      ));
      expect(asc, [1, 4, 2, 3]);

      // 降序方向：脏数据**仍然**在最后，不能因为取负而跑到最前面
      final desc = idsOf(ReviewRepository.blendByTimeWeight(
        withDirty,
        timeOf: t,
        timeWeight: 1.0,
        ascending: false,
      ));
      expect(desc, [4, 1, 2, 3]);
      expect(desc.sublist(2), [2, 3], reason: '脏数据必须在队尾');
    });

    test('无论权重多少都不漏词、不重复、不改元素个数', () {
      final rnd = Random(11);
      for (final weight in [0.0, 0.5, 1.0]) {
        final ordered = ReviewRepository.blendByTimeWeight(
          rows,
          timeOf: timeOf,
          timeWeight: weight,
          ascending: false,
          random: rnd,
        );
        expect(ordered.length, rows.length);
        expect(idsOf(ordered).toSet().length, rows.length, reason: '不得重复');
        expect(idsOf(ordered).toSet(), {for (var i = 0; i < 30; i++) i},
            reason: '不得漏词');
      }
    });

    test('边界：空表与单元素直接返回', () {
      expect(
          ReviewRepository.blendByTimeWeight(const [], timeOf: (_) => 0),
          isEmpty);
      final one = [w(1, 0)];
      expect(idsOf(ReviewRepository.blendByTimeWeight(one, timeOf: (_) => 0)),
          [1]);
    });
  });

  group('抽检间隔', () {
    final t = DateTime.utc(2026, 9, 16, 12);

    test('答对 10 天 / 答错 2 天 / 跳过 7 天（v2.2.0 定值）', () {
      expect(
        ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 10).inDays,
        10,
      );
      expect(ReviewRepository.dueAfterWrong(t).difference(t).inDays, 2);
      expect(ReviewRepository.dueAfterSkip(t).difference(t).inDays, 7);
    });

    test('池子不足单次抽检量时答对冷却期缩短到 7 天（阈值跟随抽检量）', () {
      expect(
        ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 4).inDays,
        7,
      );
      // v2.2.0：单次抽检量 5 → 10，短冷却阈值跟随 —— 池子 5~9 个也走短冷却
      expect(
        ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 5).inDays,
        7,
      );
      expect(
        ReviewRepository.cooldownAfterCorrect(
                masteredPoolSize: AppConstants.masteredQuizCount)
            .inDays,
        10,
      );
      expect(
        ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 0).inDays,
        7,
      );
    });

    test('跳过的间隔必须短于答对 —— 否则跳过的词会被长期搁置', () {
      final skip = ReviewRepository.dueAfterSkip(t).difference(t);
      final correct =
          ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 99);
      expect(skip < correct, isTrue);
    });

    test('答错复检间隔最短（要尽快验证是否真的忘了）', () {
      final wrong = ReviewRepository.dueAfterWrong(t).difference(t);
      final skip = ReviewRepository.dueAfterSkip(t).difference(t);
      expect(wrong < skip, isTrue);
    });
  });

  group('公平性模拟（时间权重 0.5）', () {
    const perRound = AppConstants.masteredQuizCount;

    test('500 个词 × 每轮抽 10：足够轮次后每个词都被抽到过（不漏词）', () {
      const n = 500;
      final rnd = Random(20260916);
      final items = [for (var i = 0; i < n; i++) w(i, rnd.nextInt(1000))];
      final picked = <int>{};

      for (var round = 0; round < 300; round++) {
        final ordered = ReviewRepository.blendByTimeWeight(
          items,
          timeOf: (r) => (r['due'] as int).toDouble(),
          random: rnd,
        );
        final chosen = ordered.take(perRound).toList();
        // due 推后 = 排到队尾（等价于真实的 due = now + 间隔）
        final maxDue = items.map((e) => e['due'] as int).reduce(max);
        for (final c in chosen) {
          picked.add(c['id'] as int);
          c['due'] = maxDue + 1;
        }
      }

      expect(
        picked.length,
        n,
        reason: '每个已掌握词都必须至少被抽到一次，不允许有词被长期漏掉',
      );
    });

    test('相邻两轮不会抽到同一批词（抽中的词 due 被推后）', () {
      const n = 100;
      final rnd = Random(42);
      final items = [for (var i = 0; i < n; i++) w(i, 0)];
      List<int>? lastPicked;

      for (var round = 0; round < 10; round++) {
        final ordered = ReviewRepository.blendByTimeWeight(
          items,
          timeOf: (r) => (r['due'] as int).toDouble(),
          random: rnd,
        );
        final ids = [for (final e in ordered.take(perRound)) e['id'] as int];

        if (lastPicked != null) {
          final overlap = ids.where(lastPicked.contains).length;
          expect(
            overlap,
            0,
            reason: '池子 $n 远大于单轮 $perRound 时，相邻两轮不应重叠',
          );
        }
        lastPicked = ids;

        final maxDue = items.map((e) => e['due'] as int).reduce(max);
        for (final c in ordered.take(perRound)) {
          c['due'] = maxDue + 1;
        }
      }
    });
  });

  group('二次失败判定（v2.1.6 修订；v2.2.0 打回目标改 T5）', () {
    test('首次答错只标记（不降级），第二次答错才打回 T5 重走周期', () {
      expect(ReviewRepository.shouldDemoteOnQuizWrong(0), isFalse);
      expect(ReviewRepository.shouldDemoteOnQuizWrong(1), isTrue);
    });

    test('重测答对走的是复检窗口（2 天），而不是洗白', () {
      // holdMasteredQuizWrongMark 使用 dueAfterWrong —— 语义上等同于
      // "保留失败标记 + 2 天后复检"，因此其间隔必须仍是 2 天
      final t = DateTime.utc(2026, 9, 16, 12);
      expect(ReviewRepository.dueAfterWrong(t).difference(t).inDays, 2);
    });
  });

  group('复合抽取权重（v2.2.0 需求2）', () {
    Map<String, dynamic> row(int id, int due, Object created) =>
        {'id': id, 'due': due, 'created_at': created};

    List<int> idsOf(List<Map<String, dynamic>> rows) =>
        [for (final r in rows) r['id'] as int];

    double dueOf(Map<String, dynamic> r) => (r['due'] as num).toDouble();
    double createdAtOf(Map<String, dynamic> r) =>
        (r['created_at'] as num).toDouble();

    test('权重常量与模拟定值一致（0.45 / 0.15 / 0.40）', () {
      expect(AppConstants.masteryQuizWeightDue, 0.45);
      expect(AppConstants.masteryQuizWeightCreated, 0.15);
      expect(AppConstants.masteryQuizWeightRandom, 0.40);
    });

    test('不漏词、不重复、不改元素个数', () {
      final rows = [row(1, 10, 100), row(2, 20, 90), row(3, 30, 80)];
      final out = ReviewRepository.blendMasteryQuizWeights(
        rows,
        dueOf: dueOf,
        createdAtOf: createdAtOf,
        random: Random(1),
      );
      expect(idsOf(out)..sort(), [1, 2, 3]);
    });

    test('单元素原样返回', () {
      expect(
        idsOf(ReviewRepository.blendMasteryQuizWeights(
          [row(1, 5, 5)],
          dueOf: dueOf,
          createdAtOf: createdAtOf,
        )),
        [1],
      );
    });

    test('脏时间维度垫尾：同 due 下 created_at 哨兵值的词排最后', () {
      // 三词 due 相同（due 名次并列 0），唯一区分维度是 created_at：
      // C(80) < B(90) < A(哨兵垫尾=1.0) —— 平均名次必须严格 C < B < A
      final rows = [
        row(0, 10, double.maxFinite), // A：created_at 脏
        row(1, 10, 90), // B
        row(2, 10, 80), // C
      ];
      final sumPos = List<double>.filled(3, 0);
      const rounds = 400;
      for (var i = 0; i < rounds; i++) {
        final out = ReviewRepository.blendMasteryQuizWeights(
          rows,
          dueOf: dueOf,
          createdAtOf: createdAtOf,
          random: Random(i),
        );
        for (var p = 0; p < out.length; p++) {
          sumPos[out[p]['id'] as int] += p;
        }
      }
      expect(sumPos[2] / rounds, lessThan(sumPos[1] / rounds),
          reason: 'created_at 较早的 C 平均名次应优于 B');
      expect(sumPos[1] / rounds, lessThan(sumPos[0] / rounds),
          reason: 'created_at 脏数据的 A 该维度垫尾，平均名次应劣于 B');
    });

    test('偏向性：添加最早 + 复习最久远的词整体排名显著靠前', () {
      // id 越小：添加越早（created_at 越小）、距上次复习越久（due 越小）
      final rows = [
        for (var i = 0; i < 8; i++) row(i, 10 + i * 10, i * 10),
      ];
      final sumPos = List<double>.filled(8, 0);
      const rounds = 400;
      for (var r = 0; r < rounds; r++) {
        final out = ReviewRepository.blendMasteryQuizWeights(
          rows,
          dueOf: dueOf,
          createdAtOf: createdAtOf,
          random: Random(r),
        );
        for (var pos = 0; pos < out.length; pos++) {
          sumPos[out[pos]['id'] as int] += pos;
        }
      }
      final earlyMean =
          (sumPos[0] + sumPos[1] + sumPos[2] + sumPos[3]) / (4 * rounds);
      final lateMean =
          (sumPos[4] + sumPos[5] + sumPos[6] + sumPos[7]) / (4 * rounds);
      expect(earlyMean, lessThan(lateMean),
          reason: '添加最早 + 复习最久远的前半组平均排名应显著优于后半组');
    });

    test('公平性：500 词足够轮次后每个词都被抽到（复合权重下不漏词）', () {
      const n = 500;
      final rnd = Random(20260930);
      final items = [
        for (var i = 0; i < n; i++)
          row(i, rnd.nextInt(1000), rnd.nextInt(1000)),
      ];
      final picked = <int>{};
      for (var round = 0; round < 300; round++) {
        final ordered = ReviewRepository.blendMasteryQuizWeights(
          items,
          dueOf: dueOf,
          createdAtOf: createdAtOf,
          random: rnd,
        );
        final chosen = ordered.take(AppConstants.masteredQuizCount).toList();
        final maxDue = items.map((e) => e['due'] as int).reduce(max);
        for (final c in chosen) {
          picked.add(c['id'] as int);
          c['due'] = maxDue + 1;
        }
      }
      expect(picked.length, n, reason: '复合权重下同样不允许漏词');
    });
  });

  group('抽检常量', () {
    test('单次抽检 10 词、答对 10 天、时间权重 0.5 —— 与用户定值一致', () {
      expect(AppConstants.masteredQuizCount, 10);
      expect(AppConstants.masteredQuizCorrectDays, 10);
      expect(AppConstants.orderTimeWeight, 0.5);
    });
  });

  // v2.1.7 修复回归：「冷却期内的词不得被返回」。
  // 原实现有一条 fallback——冷却期内候选不足单次抽检量时丢掉 due 条件硬凑数量，
  // 导致"已掌握词刚好凑满一轮"的用户每一轮抽检都抽到同一批词。
  group('冷却期不变量（v2.1.7 修复回归）', () {
    final now = DateTime.utc(2026, 9, 17, 12);
    Map<String, dynamic> d(int id, Duration offset) => {
          'id': id,
          'due': now.add(offset).toIso8601String(),
        };
    double dueOf(Map<String, dynamic> r) =>
        ReviewRepository.epochMillisOf(r['due']);

    test('冷却期内的词一律不放行：池子只有 5 个词时返回空，不再硬凑', () {
      // 复现场景：几个已掌握词刚被抽过一轮（due 推到冷却期后，原值 15 天）
      final mastered = [
        for (var i = 0; i < 5; i++) d(i, const Duration(days: 15)),
      ];

      final ready = ReviewRepository.filterQuizReady(mastered, now: now);
      expect(ready, isEmpty, reason: '冷却期内的词必须被全部挡住');
      expect(
        ReviewRepository.blendByTimeWeight(ready, timeOf: dueOf),
        isEmpty,
        reason: '本次应当不抽检，而不是无视 due 把同一批词还回来',
      );
    });

    test('只有冷却期已过的词进入候选，冷却中的词不参与抽取', () {
      final mastered = [
        d(1, const Duration(hours: -1)), // 已过冷却
        d(2, Duration.zero), // 恰好到期 → 可抽
        d(3, const Duration(days: 15)), // 冷却中
      ];

      final ready = ReviewRepository.filterQuizReady(mastered, now: now);
      expect(idsOf(ready), [1, 2]);

      final picked = ReviewRepository.blendByTimeWeight(
        ready,
        timeOf: dueOf,
        random: Random(1),
      );
      expect(idsOf(picked).toSet(), {1, 2});
      expect(
        picked.any((e) => e['id'] == 3),
        isFalse,
        reason: '冷却期内的词绝不能出现在抽检结果里',
      );
    });

    test('due 缺失或不可解析的词视为不可抽（宁可漏抽也不重复抽）', () {
      expect(
        ReviewRepository.isQuizReady({'id': 9, 'due': null}, now: now),
        isFalse,
      );
      expect(
        ReviewRepository.isQuizReady({'id': 9, 'due': 'not-a-date'}, now: now),
        isFalse,
      );
      expect(
        ReviewRepository.isQuizReady(d(9, Duration.zero), now: now),
        isTrue,
      );
    });

    test('真机场景模拟：10 个已掌握词、答对冷却 10 天 → 10 天内只应抽到一次', () {
      final items = [for (var i = 0; i < 10; i++) d(i, Duration.zero)];
      final rnd = Random(20260917);
      var days = 0;
      var offered = 0;

      for (var day = 0; day < 10; day++) {
        days++;
        final ready = ReviewRepository.filterQuizReady(
          items,
          now: now.add(Duration(days: day)),
        );
        final ordered = ReviewRepository.blendByTimeWeight(
          ready,
          timeOf: dueOf,
          random: rnd,
        );
        final picked = ordered.take(AppConstants.masteredQuizCount).toList();
        if (picked.isEmpty) continue;
        offered++;
        for (final c in picked) {
          // 等价于 submitMasteredQuiz(correct: true)：due = 当前时刻 + 冷却期
          c['due'] = now
              .add(Duration(days: day))
              .add(ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 10))
              .toIso8601String();
        }
      }

      expect(days, 10);
      expect(
        offered,
        1,
        reason: '10 个词走完一轮后进入冷却期，修复前这里会是 10（每天重复同一批）',
      );
    });
  });
}
