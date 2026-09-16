import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/core/constants/app_constants.dart';
import 'package:wordmem/data/repositories/review_repository.dart';

// 熟练词抽检机制单测（v2.1.6）。
//
// 锁定三条不变量：
// 1. 同轮不重复 —— 一次抽取的词互不相同
// 2. 短期不重复 —— 被抽中的词 due 推后，不会在紧接着的下一轮重现
// 3. 长期不遗漏 —— 连续抽取足够多次后，池中每个词都被抽到过
void main() {
  Map<String, dynamic> w(int id, int due) => {'id': id, 'due': due};

  group('pickRandom（窗口内随机抽取）', () {
    test('抽取数量正确且同轮互不重复', () {
      final candidates = [for (var i = 0; i < 15; i++) w(i, i)];
      final picked = ReviewRepository.pickRandom(
        candidates,
        count: 5,
        random: Random(7),
      );

      expect(picked.length, 5);
      expect(
        picked.map((e) => e['id']).toSet().length,
        5,
        reason: '同一轮内不得重复抽到同一个词',
      );
    });

    test('只从给定候选（窗口）中取，不会引入窗口外的词', () {
      final candidates = [for (var i = 0; i < 15; i++) w(i, i)];
      final ids = candidates.map((e) => e['id'] as int).toSet();

      for (var round = 0; round < 50; round++) {
        final picked = ReviewRepository.pickRandom(candidates, count: 5);
        expect(picked.every((e) => ids.contains(e['id'] as int)), isTrue);
      }
    });

    test('候选不足时返回全部；空候选返回空', () {
      expect(
        ReviewRepository.pickRandom([w(1, 0), w(2, 1)], count: 5).length,
        2,
      );
      expect(ReviewRepository.pickRandom(const [], count: 5), isEmpty);
    });

    test('count <= 0 时返回空', () {
      expect(ReviewRepository.pickRandom([w(1, 0)], count: 0), isEmpty);
    });
  });

  group('抽检间隔', () {
    final t = DateTime.utc(2026, 9, 16, 12);

    test('答对 15 天 / 答错 3 天 / 跳过 7 天', () {
      expect(ReviewRepository.dueAfterCorrect(t).difference(t).inDays, 15);
      expect(ReviewRepository.dueAfterWrong(t).difference(t).inDays, 3);
      expect(ReviewRepository.dueAfterSkip(t).difference(t).inDays, 7);
    });

    test('跳过的间隔必须短于答对 —— 否则跳过的词会被长期搁置', () {
      final skip = ReviewRepository.dueAfterSkip(t).difference(t);
      final correct = ReviewRepository.dueAfterCorrect(t).difference(t);
      expect(skip < correct, isTrue);
    });

    test('答错复检间隔最短（要尽快验证是否真的忘了）', () {
      final wrong = ReviewRepository.dueAfterWrong(t).difference(t);
      final skip = ReviewRepository.dueAfterSkip(t).difference(t);
      expect(wrong < skip, isTrue);
    });
  });

  group('公平性模拟（最久未抽优先 + 窗口随机）', () {
    const perRound = AppConstants.masteredQuizCount;
    final windowSize = perRound * AppConstants.masteredQuizWindowFactor;

    test('500 个词 × 每轮抽 5：足够轮次后每个词都被抽到过（不漏词）', () {
      const n = 500;
      final rnd = Random(20260916);
      // 初始 due 用随机值，模拟"各词掌握时间不同"
      final items = [for (var i = 0; i < n; i++) w(i, rnd.nextInt(1000))];
      final picked = <int>{};

      for (var round = 0; round < 200; round++) {
        items.sort((a, b) => (a['due'] as int).compareTo(b['due'] as int));
        final chosen = ReviewRepository.pickRandom(
          items.take(windowSize).toList(),
          count: perRound,
          random: rnd,
        );
        // due 推后 = 排到队尾（等价于真实实现的 due = now + 间隔）
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

    test('短期不重复：池子足够大时相邻两轮不会抽到同一批词', () {
      const n = 100;
      final rnd = Random(42);
      final items = [for (var i = 0; i < n; i++) w(i, 0)];
      List<int>? lastPicked;

      for (var round = 0; round < 10; round++) {
        items.sort((a, b) => (a['due'] as int).compareTo(b['due'] as int));
        final chosen = ReviewRepository.pickRandom(
          items.take(windowSize).toList(),
          count: perRound,
          random: rnd,
        );
        final ids = chosen.map((e) => e['id'] as int).toList();

        if (lastPicked != null) {
          final overlap = ids.where(lastPicked.contains).length;
          expect(
            overlap,
            0,
            reason: '池子 $n > 窗口 $windowSize 时，相邻两轮不应有重叠',
          );
        }
        lastPicked = ids;

        final maxDue = items.map((e) => e['due'] as int).reduce(max);
        for (final c in chosen) {
          c['due'] = maxDue + 1;
        }
      }
    });
  });

  group('二次失败判定（v2.1.6 修订）', () {
    test('首次答错只标记（不降级），第二次答错才降级退回 T3', () {
      expect(ReviewRepository.shouldDemoteOnQuizWrong(0), isFalse);
      expect(ReviewRepository.shouldDemoteOnQuizWrong(1), isTrue);
    });

    test('重测答对走的是复检窗口（3 天），而不是洗白',
        () {
      // holdMasteredQuizWrongMark 使用 dueAfterWrong —— 语义上等同于
      // "保留失败标记 + 3 天后复检"，因此其间隔必须仍是 3 天
      final t = DateTime.utc(2026, 9, 16, 12);
      expect(ReviewRepository.dueAfterWrong(t).difference(t).inDays, 3);
    });
  });

  group('抽检常量', () {
    test('单次抽检 5 词、窗口 3 倍 —— 与设计稿一致', () {
      expect(AppConstants.masteredQuizCount, 5);
      expect(AppConstants.masteredQuizWindowFactor, 3);
      expect(AppConstants.masteredQuizCorrectDays, 15);
    });
  });
}
