import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/data/repositories/word_repository.dart';

/// v2.2.0 需求3：词群题组切块逻辑（单卡题组制，>5 词群拆子题覆盖全群）
void main() {
  group('WordRepository.splitGroupIntoChunks', () {
    test('空列表 → 无子题', () {
      expect(WordRepository.splitGroupIntoChunks([]), isEmpty);
    });

    test('全空白 → 无子题', () {
      expect(
        WordRepository.splitGroupIntoChunks(['', '   ']),
        isEmpty,
      );
    });

    test('空白剔除 + 重复去重 → 剩余单成员成一块', () {
      final chunks = WordRepository.splitGroupIntoChunks(
        ['', '  ', 'abandon', 'abandon'],
      );
      // 过滤空白、去重后只剩 abandon（单成员群仍可出一道子题）
      expect(chunks, [
        ['abandon'],
      ]);
    });

    test('5 词以内 → 单块', () {
      final chunks = WordRepository.splitGroupIntoChunks(
        ['a', 'b', 'c', 'd', 'e'],
      );
      expect(chunks.length, 1);
      expect(chunks.single.length, 5);
    });

    test('8 词 → 5/3 两块，覆盖全群且不重复', () {
      final words = List.generate(8, (i) => 'w$i');
      final chunks = WordRepository.splitGroupIntoChunks(words);
      expect(chunks.length, 2);
      expect(chunks[0].length, 5);
      expect(chunks[1].length, 3);
      final all = chunks.expand((c) => c).toSet();
      expect(all.length, 8); // 无重复、全覆盖
      expect(all.containsAll(words), isTrue);
    });

    test('12 词 → 5/5/2 三块', () {
      final words = List.generate(12, (i) => 'w$i');
      final chunks = WordRepository.splitGroupIntoChunks(words);
      expect(chunks.length, 3);
      expect(chunks.map((c) => c.length), [5, 5, 2]);
    });

    test('可注入 Random 保证确定性', () {
      final words = List.generate(7, (i) => 'w$i');
      final a = WordRepository.splitGroupIntoChunks(
        words,
        random: Random(20260930),
      );
      final b = WordRepository.splitGroupIntoChunks(
        words,
        random: Random(20260930),
      );
      expect(a.map((c) => c.join('|')), b.map((c) => c.join('|')));
    });
  });
}
