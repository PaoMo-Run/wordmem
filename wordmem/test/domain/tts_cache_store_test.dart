import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/domain/services/tts_cache_store.dart';

/// matcher 包无 matchesRegex，用 predicate 等价实现。
Matcher _matches(RegExp re) =>
    predicate<String>(re.hasMatch, 'matches $re');

void main() {
  late Directory tmp;
  late TtsCacheStore store;

  const id3Bytes = [0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x01, 0x02];
  const frameBytes = [0xFF, 0xFB, 0x90, 0x00];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tts_cache_test');
    store = TtsCacheStore(cacheDir: tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('fileName 清洗', () {
    test('大写转小写并带 md5 后缀', () {
      expect(
        store.fileName('Hello'),
        _matches(RegExp(r'^hello-[0-9a-f]{8}\.mp3$')),
      );
    });

    test('撇号/空格等非 [a-z0-9] 字符被清洗', () {
      expect(
        store.fileName("don't stop"),
        _matches(RegExp(r'^dontstop-[0-9a-f]{8}\.mp3$')),
      );
    });

    test('同词不同大小写映射到同一文件', () {
      expect(store.fileName('Apple'), store.fileName('APPLE'));
    });

    test('清洗后同形的不同词不碰撞（md5 后缀区分）', () {
      // "a-b" 与 "ab" 清洗后同为 "ab"，但 md5(小写原词) 不同
      expect(store.fileName('a-b'), isNot(store.fileName('ab')));
    });

    test('全非法字符的词有稳定文件名', () {
      expect(store.fileName('你好'), store.fileName('你好'));
      expect(
        store.fileName('你好'),
        _matches(RegExp(r'^word-[0-9a-f]{8}\.mp3$')),
      );
    });
  });

  group('isLikelyMp3', () {
    test('ID3 头通过', () => expect(isLikelyMp3(id3Bytes), isTrue));
    test('帧同步头 0xFFEx 通过', () => expect(isLikelyMp3(frameBytes), isTrue));
    test('HTML 文本拒绝', () {
      expect(isLikelyMp3('<html>'.codeUnits), isFalse);
    });
    test('过短序列拒绝', () => expect(isLikelyMp3([0x49]), isFalse));
  });

  group('get / put', () {
    test('put 后 get 命中且内容一致', () async {
      await store.put('hello', id3Bytes);
      final f = store.get('hello');
      expect(f, isNotNull);
      expect(f!.readAsBytesSync(), id3Bytes);
    });

    test('未缓存的词返回 null', () {
      expect(store.get('nothing'), isNull);
    });

    test('坏文件（HTML 错误页）被魔数校验拒绝', () async {
      final f = File('${tmp.path}/${store.fileName('bad')}');
      await f.writeAsBytes('<html>error page</html>'.codeUnits);
      expect(store.get('bad'), isNull);
    });

    test('过短文件被拒绝', () async {
      final f = File('${tmp.path}/${store.fileName('tiny')}');
      await f.writeAsBytes([0x49]);
      expect(store.get('tiny'), isNull);
    });
  });

  group('trim', () {
    test('超出限额时按 mtime 从最旧裁剪至 80%', () async {
      // 10 个文件各 1000 字节；限额 6000 → 目标 4800 → 至少删 6 个最旧的
      for (var i = 0; i < 10; i++) {
        await store.put('w$i', [...id3Bytes, ...List.filled(992, 0x11)]);
      }
      // 手动设置 mtime 保证裁剪顺序确定
      final base = DateTime(2026, 9, 1);
      for (var i = 0; i < 10; i++) {
        File('${tmp.path}/${store.fileName('w$i')}')
            .setLastModifiedSync(base.add(Duration(minutes: i)));
      }
      await store.trim(maxBytes: 6000);
      final remaining = tmp
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tmp'))
          .toList();
      final total = remaining.fold<int>(0, (s, f) => s + f.lengthSync());
      expect(total, lessThanOrEqualTo(4800));
      // 最新的 4 个必须还在
      for (var i = 6; i < 10; i++) {
        expect(store.get('w$i'), isNotNull, reason: 'w$i 应保留');
      }
      // 最旧的 w0 应被裁掉
      expect(store.get('w0'), isNull);
    });

    test('未超限额不删除任何文件', () async {
      await store.put('a', id3Bytes);
      await store.trim();
      expect(store.get('a'), isNotNull);
    });
  });
}
