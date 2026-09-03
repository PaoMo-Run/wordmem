import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wordmem/domain/services/tts_cache_store.dart';
import 'package:wordmem/domain/services/pronunciation_service.dart';
import 'package:wordmem/infra/audio/audio_file_player.dart';
import 'package:wordmem/infra/audio/tts_player.dart';

/// 按主机名路由的假 http 客户端（无 mock 库）。
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);
  final http.Response Function(Uri url) handler;

  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    final resp = handler(request.url);
    return http.StreamedResponse(
      Stream.value(resp.bodyBytes),
      resp.statusCode,
      contentLength: resp.bodyBytes.length,
      headers: resp.headers,
    );
  }
}

class _FakeFilePlayer implements AudioFilePlayer {
  final played = <String>[];
  @override
  Future<void> play(String path) async => played.add(path);
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

class _FakeTtsPlayer implements TtsPlayer {
  bool readyResult = true;
  bool ensureReadyCalled = false;
  final spoken = <String>[];
  @override
  Future<bool> ensureReady() async {
    ensureReadyCalled = true;
    return readyResult;
  }
  @override
  Future<void> speak(String word) async => spoken.add(word);
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

void main() {
  late Directory tmp;
  late TtsCacheStore store;

  // 合法 mp3：ID3 头 + >1000 字节填充
  final validMp3 = Uint8List.fromList(
    [0x49, 0x44, 0x33, 0x04, 0x00, 0x00, ...List.filled(2000, 0x11)],
  );
  // 帧同步头的合法 mp3
  final frameMp3 = Uint8List.fromList(
    [0xFF, 0xFB, 0x90, 0x00, ...List.filled(2000, 0x22)],
  );
  final htmlPage = Uint8List.fromList(
    '<html><body>403 Forbidden</body></html>'.codeUnits,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pron_cascade_test');
    store = TtsCacheStore(cacheDir: tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  PronunciationCascade buildCascade({
    required _FakeClient client,
    required _FakeFilePlayer filePlayer,
    required _FakeTtsPlayer ttsPlayer,
    Duration? negativeTtl,
  }) {
    return PronunciationCascade(
      cache: store,
      client: client,
      filePlayer: filePlayer,
      ttsPlayer: ttsPlayer,
      timeout: const Duration(seconds: 1),
      negativeTtl: negativeTtl ?? const Duration(minutes: 5),
    );
  }

  test('缓存命中不发网络请求', () async {
    await store.put('hello', validMp3);
    final client = _FakeClient(
      (url) => fail('不应发起请求'),
    );
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('hello');

    expect(client.requestCount, 0);
    expect(filePlayer.played.length, 1);
    expect(ttsPlayer.spoken, isEmpty);
    svc.dispose();
  });

  test('youdao 失败落 baidu，成功后写入缓存', () async {
    final client = _FakeClient((url) {
      if (url.host.contains('youdao')) {
        return http.Response.bytes(htmlPage, 403);
      }
      return http.Response.bytes(frameMp3, 200);
    });
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('world');

    expect(client.requestCount, 2);
    expect(filePlayer.played.length, 1);
    expect(ttsPlayer.spoken, isEmpty);
    // 第二次直接走缓存
    await svc.speak('world');
    expect(client.requestCount, 2);
    expect(filePlayer.played.length, 2);
    svc.dispose();
  });

  test('两源失败进 TTS，词进负缓存短路后续请求', () async {
    final client = _FakeClient((url) => http.Response.bytes(htmlPage, 404));
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('broken');
    expect(client.requestCount, 2);
    expect(ttsPlayer.spoken, ['broken']);

    // 负缓存命中：不再发请求
    await svc.speak('broken');
    expect(client.requestCount, 2);
    expect(ttsPlayer.spoken.length, 2);
    svc.dispose();
  });

  test('200 但魔数非法（HTML 页）被拒绝', () async {
    final client = _FakeClient((url) => http.Response.bytes(htmlPage, 200));
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('fake');

    expect(filePlayer.played, isEmpty);
    expect(ttsPlayer.spoken, ['fake']);
    expect(store.get('fake'), isNull); // 坏内容不落缓存
    svc.dispose();
  });

  test('200 但体长 ≤1000 字节被拒绝', () async {
    final short = Uint8List.fromList(
        [0x49, 0x44, 0x33, 0x00, ...List.filled(500, 0x33)]);
    final client = _FakeClient((url) => http.Response.bytes(short, 200));
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('short');

    expect(filePlayer.played, isEmpty);
    expect(ttsPlayer.spoken, ['short']);
    svc.dispose();
  });

  test('网络异常（连接失败）降级到下一源', () async {
    final client = _FakeClient((url) {
      if (url.host.contains('youdao')) {
        throw http.ClientException('connection refused');
      }
      return http.Response.bytes(validMp3, 200);
    });
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('neterr');

    expect(client.requestCount, 2);
    expect(filePlayer.played.length, 1);
    svc.dispose();
  });

  test('TTS 不可用（无英语语音包）时静默不崩', () async {
    final client = _FakeClient((url) => http.Response.bytes(htmlPage, 404));
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer()..readyResult = false;
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('silent');

    expect(ttsPlayer.ensureReadyCalled, isTrue);
    expect(ttsPlayer.spoken, isEmpty);
    expect(filePlayer.played, isEmpty);
    // 不可用态后不再调 ensureReady
    await svc.speak('silent');
    expect(ttsPlayer.ensureReadyCalled, isTrue);
    svc.dispose();
  });

  test('stop-then-play：连续点词不排队（每次 speak 前先 stop）', () async {
    final client = _FakeClient((url) => http.Response.bytes(validMp3, 200));
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    await svc.speak('apple');
    await svc.speak('banana');

    expect(filePlayer.played.length, 2);
    expect(filePlayer.played.last, contains(store.fileName('banana')));
    svc.dispose();
  });

  test('瞬时网络错误不记负缓存：断网后再点同词会重试在线源（网络恢复场景）',
      () async {
    // 可变 handler：首次全源连接失败（模拟断网），之后返回合法音频（模拟网络恢复）
    var offline = true;
    final client = _FakeClient((url) {
      if (offline) throw http.ClientException('no network');
      return http.Response.bytes(validMp3, 200);
    });
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
        client: client, filePlayer: filePlayer, ttsPlayer: ttsPlayer);

    // 断网：全源瞬时失败 → TTS 兜底，但不进负缓存
    await svc.speak('recover');
    expect(client.requestCount, 2);
    expect(ttsPlayer.spoken, ['recover']);
    expect(filePlayer.played, isEmpty);

    // 网络恢复后点同一词：必须重新发起请求并成功播放（首源即成功 → +1 请求）
    offline = false;
    await svc.speak('recover');
    expect(client.requestCount, 3, reason: '网络恢复后同词应重试在线源');
    expect(filePlayer.played.length, 1);
    expect(ttsPlayer.spoken.length, 1, reason: '不再走 TTS');
    svc.dispose();
  });

  test('服务端拒绝进负缓存但 TTL 过期后自动失效重试', () async {
    // 全源 404（服务端明确拒绝）
    final client = _FakeClient((url) => http.Response.bytes(htmlPage, 404));
    final filePlayer = _FakeFilePlayer();
    final ttsPlayer = _FakeTtsPlayer();
    final svc = buildCascade(
      client: client,
      filePlayer: filePlayer,
      ttsPlayer: ttsPlayer,
      negativeTtl: const Duration(milliseconds: 30),
    );

    await svc.speak('tempdown');
    expect(client.requestCount, 2);
    expect(ttsPlayer.spoken, ['tempdown']);

    // TTL 内：负缓存命中，不再发请求
    await svc.speak('tempdown');
    expect(client.requestCount, 2);

    // TTL 过期：自动失效重试（虽仍 404，但重新发起了请求）
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await svc.speak('tempdown');
    expect(client.requestCount, 4, reason: '负缓存 TTL 过期后应自动重试');
    svc.dispose();
  });
}
