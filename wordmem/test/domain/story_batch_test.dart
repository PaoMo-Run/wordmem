import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/data/repositories/story_repository.dart';

/// v2.2.0 需求4：短文分段生成与导入校验的纯函数部分
void main() {
  group('StoryRepository.splitIntoBatches', () {
    test('空列表 → 无批次', () {
      expect(StoryRepository.splitIntoBatches([]), isEmpty);
    });

    test('25 词 → 单批', () {
      final b = StoryRepository.splitIntoBatches(List.generate(25, (i) => 'w$i'));
      expect(b.length, 1);
      expect(b.single.length, 25);
    });

    test('26 词 → 25/1 两批；80 词 → 25/25/25/5 四批', () {
      expect(
        StoryRepository.splitIntoBatches(List.generate(26, (i) => 'w$i'))
            .map((b) => b.length),
        [25, 1],
      );
      expect(
        StoryRepository.splitIntoBatches(List.generate(80, (i) => 'w$i'))
            .map((b) => b.length),
        [25, 25, 25, 5],
      );
    });

    test('保持给定顺序（当日新词按添加时间升序进入批次）', () {
      final b = StoryRepository.splitIntoBatches(['a', 'b', 'c']);
      expect(b.single, ['a', 'b', 'c']);
    });
  });

  group('StoryRepository.tokenizeText', () {
    test('小写化 + 去所有格', () {
      final tokens = StoryRepository.tokenizeText("The dog's bones were Dogs' toys.");
      expect(tokens.contains('dog'), isTrue);
      expect(tokens.contains('dogs'), isTrue);
      // 复数不做还原（bones 原样保留，变形匹配靠词典 exchange 档）
      expect(tokens.contains('bones'), isTrue);
      expect(tokens.contains('toys'), isTrue);
      expect(tokens.contains('the'), isTrue);
    });

    test('连字符词整体保留', () {
      final tokens = StoryRepository.tokenizeText('a state-of-the-art design');
      expect(tokens.contains('state-of-the-art'), isTrue);
    });
  });
}
