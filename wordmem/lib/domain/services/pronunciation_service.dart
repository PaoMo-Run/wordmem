import 'dart:async';

import 'package:http/http.dart' as http;

import '../../infra/audio/audio_file_player.dart';
import '../../infra/audio/tts_player.dart';
import 'tts_cache_store.dart';

/// 单词发音服务抽象（可替换实现）。
abstract class PronunciationService {
  /// 播放单词发音（级联：本地缓存 → 在线音源 → 系统 TTS）。
  Future<void> speak(String word);

  /// 停止当前播放。
  Future<void> stop();

  /// 释放底层资源。
  void dispose();
}

/// 在线发音源描述（可插拔，便于源失效时替换）。
class PronunciationSource {
  final String id;
  final Map<String, String> headers;
  final Uri Function(String word) buildUrl;

  const PronunciationSource({
    required this.id,
    required this.headers,
    required this.buildUrl,
  });
}

/// 内置默认源：有道 dictvoice（主，type=2 美音）→ 百度 gettts（备）。
///
/// 两者均为无官方授权的灰区接口；已接受的缓解措施：每词仅取一次
/// （本地缓存持久化）+ 5s 超时 + 浏览器 UA + 源列表可注入替换。
class PronunciationSources {
  PronunciationSources._();

  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// 有道词典发音（type=2 美音）。
  static final PronunciationSource youdao = PronunciationSource(
    id: 'youdao',
    headers: const {
      'User-Agent': _browserUa,
      'Referer': 'https://dict.youdao.com/',
    },
    buildUrl: (word) => Uri(
          scheme: 'https',
          host: 'dict.youdao.com',
          path: '/dictvoice',
          queryParameters: {'audio': word, 'type': '2'},
        ),
  );

  /// 百度翻译 TTS（spd=3 语速中等）。
  static final PronunciationSource baidu = PronunciationSource(
    id: 'baidu',
    headers: const {
      'User-Agent': _browserUa,
      'Referer': 'https://fanyi.baidu.com/',
    },
    buildUrl: (word) => Uri(
          scheme: 'https',
          host: 'fanyi.baidu.com',
          path: '/gettts',
          queryParameters: {
            'lan': 'en',
            'text': word,
            'spd': '3',
            'source': 'web',
          },
        ),
  );

  /// 默认源顺序（主 → 备）。
  static List<PronunciationSource> get defaults => [youdao, baidu];
}

/// 发音级联实现。
///
/// 状态机（speak）：
/// 1. stop-then-play：先停上一个再播（连续点词 = 打断旧的，不排队）；
/// 2. 负缓存命中 → 直接 TTS；
/// 3. 本地缓存命中（含魔数校验）→ 播文件；
/// 4. 在线源逐个尝试（5s 超时；200 且 >1000 字节且魔数合法才收）；
/// 5. 全部失败 → 词进负缓存（会话级）→ TTS 兜底；
/// 6. TTS 不可用（无英语语音包/异常）→ 永久跳过，静默返回。
class PronunciationCascade implements PronunciationService {
  PronunciationCascade({
    required TtsCacheStore cache,
    required http.Client client,
    required AudioFilePlayer filePlayer,
    required TtsPlayer ttsPlayer,
    List<PronunciationSource>? sources,
    Duration timeout = const Duration(seconds: 5),
    Duration negativeTtl = const Duration(minutes: 5),
    int minBytes = 1000,
  })  : _cache = cache,
        _client = client,
        _filePlayer = filePlayer,
        _ttsPlayer = ttsPlayer,
        _sources = sources ?? PronunciationSources.defaults,
        _timeout = timeout,
        _negativeTtl = negativeTtl,
        _minBytes = minBytes;

  final TtsCacheStore _cache;
  final http.Client _client;
  final AudioFilePlayer _filePlayer;
  final TtsPlayer _ttsPlayer;
  final List<PronunciationSource> _sources;
  final Duration _timeout;
  final Duration _negativeTtl;
  final int _minBytes;

  /// 负缓存（会话级，不持久化）：word -> 记入时间。
  ///
  /// 仅在"所有被尝试的源均为服务端明确拒绝"（非 200 / 内容非音频，
  /// 如 403、接口变更）时记入；**瞬时网络错误（超时 / 连接失败，如断网）
  /// 不记入**——否则用户断网点过的词在网络恢复后仍被短路无法重播。
  /// 超过 [_negativeTtl] 自动失效，服务端临时故障也能自愈（无需重启）。
  final Map<String, DateTime> _failedWords = {};

  /// TTS 不可用态（永久跳过，直到 dispose 重建）。
  bool _ttsUnavailable = false;
  bool _disposed = false;

  @override
  Future<void> speak(String word) async {
    if (_disposed) return;
    final key = word.trim();
    if (key.isEmpty) return;

    // 0. 停止上一个再播（不排队）
    await stop();

    if (!_negativeHit(key)) {
      // 2. 本地缓存命中
      final cached = _cache.get(key);
      if (cached != null) {
        await _filePlayer.play(cached.path);
        return;
      }
      // 3. 在线源逐个尝试
      final (bytes, serverRejected) = await _fetch(key);
      if (bytes != null) {
        try {
          final f = await _cache.put(key, bytes);
          await _filePlayer.play(f.path);
          return;
        } catch (_) {
          // 缓存写失败（如目录不可写）→ 继续走 TTS 兜底
        }
      } else if (serverRejected) {
        // 4. 所有源均明确拒绝 → 进负缓存（TTL 内暂不重试）
        _failedWords[key] = DateTime.now();
      }
    }

    // 5. TTS 兜底
    await _speakWithTts(key);
  }

  /// 在线源尝试。返回 (字节, 是否全部为服务端拒绝)。
  ///
  /// - 任一源成功 → (bytes, false)；
  /// - 存在瞬时网络错误（超时 / 连接失败）→ (null, false)——不记负缓存，
  ///   网络恢复后同词可自动重试；
  /// - 全部源均为服务端明确拒绝（非 200 / 非音频内容）→ (null, true)。
  Future<(List<int>?, bool)> _fetch(String word) async {
    var sawServerRejection = false;
    var sawTransient = false;
    for (final source in _sources) {
      try {
        final resp = await _client
            .get(source.buildUrl(word), headers: source.headers)
            .timeout(_timeout);
        if (resp.statusCode == 200 &&
            resp.bodyBytes.length > _minBytes &&
            isLikelyMp3(resp.bodyBytes)) {
          return (resp.bodyBytes, false);
        }
        // 服务端有响应但无效（4xx/5xx/错误页）→ 源侧故障
        sawServerRejection = true;
      } on TimeoutException {
        // 超时：环境瞬时问题，不算源拒绝
        sawTransient = true;
      } catch (_) {
        // 网络错误（SocketException / ClientException 等）：环境瞬时问题
        sawTransient = true;
      }
    }
    return (null, !sawTransient && sawServerRejection);
  }

  /// 负缓存命中判定（过期自动清除）。
  bool _negativeHit(String key) {
    final at = _failedWords[key];
    if (at == null) return false;
    if (DateTime.now().difference(at) > _negativeTtl) {
      _failedWords.remove(key);
      return false;
    }
    return true;
  }

  Future<void> _speakWithTts(String word) async {
    if (_ttsUnavailable) return; // 永久不可用态，静默返回
    final ok = await _ttsPlayer.ensureReady();
    if (!ok) {
      _ttsUnavailable = true;
      return;
    }
    await _ttsPlayer.speak(word);
  }

  @override
  Future<void> stop() async {
    await _filePlayer.stop();
    await _ttsPlayer.stop();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _filePlayer.dispose();
    _ttsPlayer.dispose();
  }
}
