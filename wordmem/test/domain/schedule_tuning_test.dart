import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/core/constants/app_constants.dart';
import 'package:wordmem/domain/services/fsrs_service.dart';
import 'package:wordmem/domain/services/schedule_tuning.dart';

// 学习节奏配置单测（v2.2.0 阶段 C）。
//
// 覆盖：默认档取值来源、预设档倍率与取整、脏数据解析、越界钳制、
// FsrsService 时间线注入、toSettings/tryParse 往返、presetId 按值反推。
void main() {
  group('defaults()：全部取编译期常量，禁止硬编码', () {
    test('各字段 == AppConstants 现值 / t0t8Intervals', () {
      final d = ScheduleTuning.defaults();
      expect(
        d.timelineMinutes,
        [for (final v in FsrsService.t0t8Intervals) v.inMinutes],
      );
      expect(d.upcomingHours, AppConstants.upcomingDueWindowHours);
      expect(d.quizCount, AppConstants.masteredQuizCount);
      expect(d.quizCorrectDays, AppConstants.masteredQuizCorrectDays);
      expect(d.quizWrongDays, AppConstants.masteredQuizWrongDelay.inDays);
      expect(d.quizSkipDays, AppConstants.masteredQuizSkipDelay.inDays);
      expect(
        d.quizShortCooldownDays,
        AppConstants.masteredQuizShortCooldown.inDays,
      );
      expect(d.presetId, 'standard');
      expect(d.timelineMinutes.length, ScheduleTuning.timelineSegments);
    });
  });

  group('preset()：倍率作用于标准档，.round() 取整', () {
    test('intensive：时间线 ×0.5、抽检更频繁、冷却更短', () {
      final p = ScheduleTuning.preset('intensive');
      expect(p.timelineMinutes, [30, 90, 150, 360, 720, 720, 1440, 1440]);
      expect(p.upcomingHours, 6);
      expect(p.quizCount, (AppConstants.masteredQuizCount * 1.4).round());
      expect(
        p.quizCorrectDays,
        (AppConstants.masteredQuizCorrectDays * 0.6).round(),
      );
      expect(p.quizWrongDays, 1, reason: 'max(1, 2×0.5)');
      expect(p.quizSkipDays, (AppConstants.masteredQuizSkipDelay.inDays * 0.6).round());
    });

    test('relaxed：时间线 ×2、抽检更稀疏、冷却更长', () {
      final p = ScheduleTuning.preset('relaxed');
      expect(
        p.timelineMinutes,
        [for (final v in FsrsService.t0t8Intervals) v.inMinutes * 2],
      );
      expect(p.upcomingHours, 2);
      expect(p.quizCount, (AppConstants.masteredQuizCount * 0.6).round());
      expect(p.quizCorrectDays, AppConstants.masteredQuizCorrectDays * 2);
    });
  });

  group('tryParse：脏数据不抛异常', () {
    test('空 map / 版本不符 / 长度 7 / 非数字 → null', () {
      final good = ScheduleTuning.defaults().toSettings();

      expect(ScheduleTuning.tryParse({}), isNull);
      expect(ScheduleTuning.tryParse(good..remove('tune.version')), isNull);
      expect(
        ScheduleTuning.tryParse({...good, 'tune.version': '999'}),
        isNull,
      );
      expect(
        ScheduleTuning.tryParse({...good, 'tune.timeline': '[60,180,300,720,1440,1440,2880]'}),
        isNull,
        reason: '时间线长度不是 8 → 整体回落默认（节点数是硬约束）',
      );
      expect(
        ScheduleTuning.tryParse({...good, 'tune.quiz_count': 'abc'}),
        isNull,
      );
      expect(
        ScheduleTuning.tryParse({...good, 'tune.timeline': '"abc"'}),
        isNull,
        reason: '手改 db 写坏时间线 → 正常回落，绝不崩 App',
      );
    });

    test('越界数值解析不抛异常，结果被钳制回合法区间', () {
      final good = ScheduleTuning.defaults().toSettings();
      final parsed = ScheduleTuning.tryParse({
        ...good,
        'tune.quiz_count': '999',
        'tune.quiz_correct_days': '0',
      });
      expect(parsed, isNotNull);
      expect(parsed!.quizCount, ScheduleTuning.maxQuizCount);
      expect(parsed.quizCorrectDays, ScheduleTuning.minIntervalDays);
    });
  });

  group('clamped()：越界钳制', () {
    test('时间线长度不是 8 → 整体回落默认档', () {
      final bad = ScheduleTuning.defaults()
          .copyWith(timelineMinutes: [60, 180, 300]);
      final c = bad.clamped();
      expect(c.timelineMinutes.length, ScheduleTuning.timelineSegments);
      expect(
        c.timelineMinutes,
        ScheduleTuning.defaults().timelineMinutes,
        reason: '节点数绑死 8 段，长度不对整体回落',
      );
    });

    test('单段钳到 10 分钟 ~ 30 天；其余字段钳进各自区间', () {
      final c = ScheduleTuning.defaults()
          .copyWith(
            timelineMinutes: [for (var i = 0; i < 8; i++) 1],
          )
          .clamped();
      for (final m in c.timelineMinutes) {
        expect(m, ScheduleTuning.minSegmentMinutes);
      }
      expect(
        ScheduleTuning.defaults()
            .copyWith(quizCount: 0)
            .clamped()
            .quizCount,
        ScheduleTuning.minQuizCount,
      );
      expect(
        ScheduleTuning.defaults()
            .copyWith(quizCount: 999)
            .clamped()
            .quizCount,
        ScheduleTuning.maxQuizCount,
      );
      expect(
        ScheduleTuning.defaults()
            .copyWith(upcomingHours: 99)
            .clamped()
            .upcomingHours,
        ScheduleTuning.maxUpcomingHours,
      );
    });
  });

  group('FsrsService 时间线注入', () {
    test('intervalForReps 读实例 intervals，不读静态默认表', () {
      final custom = [
        for (var i = 1; i <= 8; i++) Duration(hours: 2 * i),
      ];
      final svc = FsrsService(custom);
      expect(svc.intervalForReps(1), const Duration(hours: 2));
      expect(svc.intervalForReps(8), const Duration(hours: 16));
      // 不传参 = 默认档（既有测试的编译约束）
      expect(FsrsService().intervalForReps(1),
          FsrsService.t0t8Intervals[0]);
    });
  });

  group('toSettings / tryParse 往返一致', () {
    test('三个预设档写读往返后字段一致', () {
      for (final id in const ['standard', 'intensive', 'relaxed']) {
        final t = ScheduleTuning.preset(id);
        final back = ScheduleTuning.tryParse(t.toSettings());
        expect(back, isNotNull, reason: '预设 $id 往返后必须可解析');
        expect(back!.timelineMinutes, t.timelineMinutes);
        expect(back.upcomingHours, t.upcomingHours);
        expect(back.quizCount, t.quizCount);
        expect(back.quizCorrectDays, t.quizCorrectDays);
        expect(back.quizWrongDays, t.quizWrongDays);
        expect(back.quizSkipDays, t.quizSkipDays);
        expect(back.quizShortCooldownDays, t.quizShortCooldownDays);
        expect(back.presetId, t.presetId);
      }
    });
  });

  group('resolvedPresetId：按值反推，展示不撒谎', () {
    test('预设值反推回对应档；手改一格 → custom', () {
      expect(ScheduleTuning.defaults().resolvedPresetId, 'standard');
      expect(ScheduleTuning.preset('intensive').resolvedPresetId,
          'intensive');
      expect(ScheduleTuning.preset('relaxed').resolvedPresetId, 'relaxed');

      // presetId 字段谎报 standard，但值是 intensive 改过一格 → 必须 custom
      final tampered = ScheduleTuning.preset('intensive')
          .copyWith(quizCount: 15, presetId: 'standard');
      expect(tampered.resolvedPresetId, 'custom');
    });

    test('presetDisplayName 中文回显', () {
      expect(ScheduleTuning.defaults().presetDisplayName, '标准');
      expect(
        ScheduleTuning.preset('intensive').copyWith().presetDisplayName,
        '密集',
      );
      expect(
        ScheduleTuning.preset('intensive')
            .copyWith(quizCount: 15)
            .presetDisplayName,
        '自定义',
      );
    });
  });
}
