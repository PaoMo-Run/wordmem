import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/data/database/app_database.dart';

// v2.2.0 T0–T8 迁移判据单测（`clampLegacyRepsForT0T8` 纯函数）。
//
// 这是**改存量数据**的迁移逻辑，测试重点与 v2.1.7 的 due 自愈一样：
// 不是"能改动"，而是"改动面可以被证明只落在真正需要钳制的行上"。
//
// 背景：九节点下 reps=8（等待 T8）是合法中间值；v2.1.x 八节点运行期
// 非 mastered 词的 reps 最多写到 7。存量里 reps>=8 的非 mastered 行
// 只可能是历史排期表/跨版本备份的遗留，统一钳回 7（重测 T7，绝不跳过）。
void main() {
  group('clampLegacyRepsForT0T8（v8 迁移判据）', () {
    test('非 mastered 且 reps>=8 → 钳回 7（重测 T7）', () {
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 8), 7);
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 9), 7);
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 50), 7);
      expect(AppDatabase.clampLegacyRepsForT0T8('learning', 8), 7);
      expect(AppDatabase.clampLegacyRepsForT0T8('new', 8), 7);
    });

    test('在途词（reps 1~7）原值保留，不受影响', () {
      expect(AppDatabase.clampLegacyRepsForT0T8('learning', 1), 1);
      expect(AppDatabase.clampLegacyRepsForT0T8('learning', 3), 3);
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 4), 4);
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 7), 7);
    });

    test('mastered 词一律不动（不强制补走 T8）', () {
      expect(AppDatabase.clampLegacyRepsForT0T8('mastered', 7), 7);
      expect(AppDatabase.clampLegacyRepsForT0T8('mastered', 8), 8);
      expect(AppDatabase.clampLegacyRepsForT0T8('mastered', 0), 0);
    });

    test('边界：reps=7 保留、reps=8 钳制（阈值是 >= 8）', () {
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 7), 7);
      expect(AppDatabase.clampLegacyRepsForT0T8('review', 8), 7);
    });
  });
}
