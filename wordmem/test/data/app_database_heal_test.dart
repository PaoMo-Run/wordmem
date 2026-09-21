import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/data/database/app_database.dart';
import 'package:wordmem/data/repositories/review_repository.dart';

// 存量已掌握词 due 自愈（v2.1.7）判据单测。
//
// 这是**改存量数据**的自愈逻辑，所以测试重点不是"能改动"，
// 而是"改动面可以被证明只落在 fuse 遗留值上"：
// 正常抽检排期、超期词、脏数据，一律不得命中。
void main() {
  final now = DateTime.utc(2026, 9, 17, 12);
  String iso(Duration d) => now.add(d).toIso8601String();

  group('isLegacyMasteredDue（fuse 遗留值判据）', () {
    test('正常抽检排期一律不命中（答对 15 / 跳过 7 / 答错 3 天）', () {
      expect(AppDatabase.isLegacyMasteredDue(iso(const Duration(days: 15)), now),
          isFalse);
      expect(AppDatabase.isLegacyMasteredDue(iso(const Duration(days: 7)), now),
          isFalse);
      expect(AppDatabase.isLegacyMasteredDue(iso(const Duration(days: 3)), now),
          isFalse);
      expect(AppDatabase.isLegacyMasteredDue(iso(Duration.zero), now), isFalse);
    });

    test('超期词（due 在过去）不命中 —— 不动它', () {
      expect(
        AppDatabase.isLegacyMasteredDue(iso(const Duration(days: -400)), now),
        isFalse,
      );
    });

    test('阈值边界：365 天不命中、366 天命中（判据是 > 而非 >=）', () {
      expect(AppDatabase.isLegacyMasteredDue(iso(const Duration(days: 365)), now),
          isFalse);
      expect(AppDatabase.isLegacyMasteredDue(iso(const Duration(days: 366)), now),
          isTrue);
    });

    test('v2.1.5 fuse 的真实值命中（3650 天；含真机存档里的原值）', () {
      expect(
        AppDatabase.isLegacyMasteredDue(iso(const Duration(days: 3650)), now),
        isTrue,
      );
      expect(
        AppDatabase.isLegacyMasteredDue('2036-09-12T17:04:41.768954Z', now),
        isTrue,
        reason: '这是用户真机存档里 52 个已掌握词的原值',
      );
    });

    test('App 自己写的规范形状必须被接受（微秒 + Z）', () {
      expect(
        AppDatabase.isLegacyMasteredDue('2036-09-12T17:04:41.768954Z', now),
        isTrue,
        reason: '这是用户真机存档里 52 个已掌握词的原值',
      );
      expect(
        AppDatabase.isLegacyMasteredDue('2026-09-24T10:08:59.620502Z', now),
        isFalse,
        reason: '同一形状、正常排期（7 天后）→ 必须放过',
      );
    });

    test('脏数据一律不命中（宁可漏修，不可误修）', () {
      expect(AppDatabase.isLegacyMasteredDue(null, now), isFalse);
      expect(AppDatabase.isLegacyMasteredDue('', now), isFalse);
      expect(AppDatabase.isLegacyMasteredDue('garbage', now), isFalse);
      // 关键用例：DateTime.tryParse 会**宽松归一化** '2036-13-45' → 2037-02-14，
      // 距离现在一样「很远」。若只靠 tryParse 判断，这个坏字符串会被改掉；
      // 形状校验必须先拦住它。
      expect(AppDatabase.isLegacyMasteredDue('2036-13-45', now), isFalse);
      expect(
        AppDatabase.isLegacyMasteredDue('2036-09-12T17:04:41', now),
        isFalse,
        reason: '无时区后缀 → 形状不符',
      );
      expect(
        AppDatabase.isLegacyMasteredDue('2036-09-12 17:04:41Z', now),
        isFalse,
        reason: '空格分隔 → 形状不符',
      );
    });

    test('与本机时区无关：now 传本地时间也按 UTC 比较', () {
      final localNow = DateTime.utc(2026, 9, 17, 12).toLocal();
      expect(
        AppDatabase.isLegacyMasteredDue('2036-09-12T17:04:41.768954Z', localNow),
        isTrue,
      );
    });

    test('阈值必须比正常排期上限高一个数量级（误伤概率才是数学上的零）', () {
      final maxLegit =
          ReviewRepository.cooldownAfterCorrect(masteredPoolSize: 999);
      expect(
        AppDatabase.legacyMasteredDueThreshold.inDays,
        greaterThan(maxLegit.inDays * 20),
        reason: '阈值与正常排期之间要留出数量级差距',
      );
    });
  });
}
