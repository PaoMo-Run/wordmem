import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/services/synonym_detector.dart';

void main() {
  group('SynonymDetector.extractKeywords', () {
    test('提取 [n.] 新词性格式下的中文核心词', () {
      final kws = SynonymDetector.extractKeywords('[n.] 放弃, 抛弃, 遗弃');
      expect(kws, containsAll(['放弃', '抛弃', '遗弃']));
    });

    test('去掉虚词后缀（高兴的 -> 高兴）', () {
      final kws = SynonymDetector.extractKeywords('[a.] 高兴的, 快乐的');
      expect(kws, contains('高兴'));
      expect(kws, contains('快乐'));
    });

    test('过滤停用词', () {
      final kws = SynonymDetector.extractKeywords('表示, 进行, 相关');
      expect(kws, isEmpty);
    });

    test('空释义返回空集', () {
      expect(SynonymDetector.extractKeywords(''), isEmpty);
    });
  });

  group('SynonymDetector.isSynonym / similarity', () {
    test('共享核心词判定为近义词', () {
      expect(
        SynonymDetector.isSynonym('[a.] 高兴的, 快乐的', '[a.] 高兴的, 愉快的'),
        isTrue,
      );
    });

    test('无重叠不是近义词', () {
      expect(
        SynonymDetector.isSynonym('[n.] 桌子, 书桌', '[a.] 高兴的'),
        isFalse,
      );
    });

    test('相似度为 0-1 之间且对称', () {
      final s1 = SynonymDetector.similarity('[a.] 高兴的', '[a.] 高兴的, 快乐的');
      final s2 = SynonymDetector.similarity('[a.] 高兴的, 快乐的', '[a.] 高兴的');
      expect(s1, greaterThan(0));
      expect(s1, lessThanOrEqualTo(1));
      expect(s1, s2);
    });
  });
}
