// 注：词根匹配为纯 Dart 逻辑，但本测试统一使用 flutter_test 框架
// （与项目现有测试一致，便于在 flutter_tester 可用的环境跑全量测试）。
// 运行：flutter test test/root_matcher_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/services/root_matcher.dart';

WordRoot _root(String root, {List<String> variants = const []}) => WordRoot(
      root: root,
      variants: variants,
      meaning: '测试释义',
      meaningEn: 'test',
    );

void main() {
  group('RootMatcher.containsRoot', () {
    final matcher = RootMatcher();

    test('词根作为词素子串命中复合词（port -> transport/export/report）', () {
      final port = _root('port');
      expect(matcher.containsRoot('transport', port), isTrue);
      expect(matcher.containsRoot('export', port), isTrue);
      expect(matcher.containsRoot('report', port), isTrue);
      expect(matcher.containsRoot('support', port), isTrue);
    });

    test('含空格的多词条目不参与词根匹配（v1.4.13 修复）', () {
      final master = _root('master');
      // 历史 bug：master minimum equipment list 因含 master 被拉进词根群
      expect(
        matcher.containsRoot('master minimum equipment list', master),
        isFalse,
      );
      expect(matcher.containsRoot('angle of attack', _root('attack')), isFalse);
      expect(matcher.containsRoot('landing gear', _root('land')), isFalse);
    });

    test('变体参与匹配（spect -> inspect/respect 通过 spect 或 spic）', () {
      final spect = _root('spect', variants: ['spic']);
      expect(matcher.containsRoot('inspect', spect), isTrue);
      expect(matcher.containsRoot('respect', spect), isTrue);
      expect(matcher.containsRoot('suspicious', spect), isTrue);
    });

    test('词根长度 <3 不参与匹配', () {
      final short = _root('ab');
      expect(matcher.containsRoot('about', short), isFalse);
    });
  });

  group('RootMatcher.match', () {
    test('聚合同根词，少于 2 词的词根族不输出', () {
      final matcher = RootMatcher();
      final port = _root('port');
      final dict = _root('dict');
      final words = ['transport', 'export', 'dictate', 'report'];
      final matches = matcher.match(words, [port, dict]);
      final byRoot = {for (final m in matches) m.root.root: m.words};
      expect(byRoot['port'], containsAll(['transport', 'export', 'report']));
      expect(byRoot.containsKey('dict'), isFalse); // 只有 1 个词，不构成词根族
    });

    test('词组被排除在词根族之外', () {
      final matcher = RootMatcher();
      final master = _root('master');
      final words = ['master', 'master minimum equipment list'];
      final matches = matcher.match(words, [master]);
      expect(matches, isNotEmpty);
      expect(matches.first.words, ['master']); // 词组不在其中
    });
  });

  group('WordRoot.fromJson', () {
    test('解析完整字段并小写化词根', () {
      final r = WordRoot.fromJson({
        'root': 'Spect',
        'variants': ['Spic', 'Spectr'],
        'meaning': '看',
        'meaningEn': 'look',
        'examples': ['inspect', 'respect'],
      });
      expect(r.root, 'spect');
      expect(r.variants, ['spic', 'spectr']);
      expect(r.meaning, '看');
      expect(r.forms, containsAll(['spect', 'spic', 'spectr']));
    });

    test('缺失可选字段不报错', () {
      final r = WordRoot.fromJson({'root': 'port'});
      expect(r.root, 'port');
      expect(r.variants, isEmpty);
      expect(r.examples, isEmpty);
    });
  });
}
