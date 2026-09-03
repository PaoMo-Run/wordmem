import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/services/pronunciation_service.dart';

void main() {
  group('youdao URL 构造', () {
    test('基础结构正确（美音 type=2）', () {
      final uri = PronunciationSources.youdao.buildUrl('hello');
      expect(uri.scheme, 'https');
      expect(uri.host, 'dict.youdao.com');
      expect(uri.path, '/dictvoice');
      expect(uri.queryParameters['audio'], 'hello');
      expect(uri.queryParameters['type'], '2');
    });

    test('特殊字符（空格/撇号/&）被正确编码不破坏 URL', () {
      final uri = PronunciationSources.youdao.buildUrl("a b'c&d");
      // 解码后等于原词
      expect(uri.queryParameters['audio'], "a b'c&d");
      // & 未被当作查询参数分隔符泄漏
      expect(uri.queryParameters.containsKey('d'), isFalse);
      expect(uri.queryParameters.length, 2);
    });
  });

  group('baidu URL 构造', () {
    test('基础结构正确（en/spd=3/web）', () {
      final uri = PronunciationSources.baidu.buildUrl('hello world');
      expect(uri.scheme, 'https');
      expect(uri.host, 'fanyi.baidu.com');
      expect(uri.path, '/gettts');
      expect(uri.queryParameters['lan'], 'en');
      expect(uri.queryParameters['text'], 'hello world');
      expect(uri.queryParameters['spd'], '3');
      expect(uri.queryParameters['source'], 'web');
      // encodeQueryComponent 语义：空格编码为 +
      expect(uri.toString(), contains('text=hello+world'));
    });

    test('特殊字符不破坏查询结构', () {
      final uri = PronunciationSources.baidu.buildUrl("it's & fine");
      expect(uri.queryParameters['text'], "it's & fine");
      expect(uri.queryParameters['lan'], 'en');
    });
  });

  group('请求头', () {
    test('两源均带浏览器 UA 与 Referer（防 403）', () {
      for (final s in PronunciationSources.defaults) {
        expect(s.headers['User-Agent'], startsWith('Mozilla/5.0'));
        expect(s.headers, isNotNull);
      }
      expect(PronunciationSources.youdao.headers['Referer'],
          contains('youdao'));
      expect(PronunciationSources.baidu.headers['Referer'], contains('baidu'));
    });
  });
}
