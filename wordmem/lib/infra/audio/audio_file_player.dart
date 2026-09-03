import 'package:audioplayers/audioplayers.dart';

/// 本地音频文件播放抽象（便于测试注入与替换底层实现）。
abstract class AudioFilePlayer {
  /// 播放本地音频文件（绝对路径）。
  Future<void> play(String path);

  /// 停止当前播放。
  Future<void> stop();

  /// 释放底层资源。
  void dispose();
}

/// 基于 audioplayers 的实现：单例 AudioPlayer，播放前先 stop。
///
/// 单例保证同一时刻只有一个发音在播（连续点词 = 打断旧的），
/// 与级联层的 stop-then-play 语义配合。
class AudioPlayersFilePlayer implements AudioFilePlayer {
  AudioPlayer? _player;
  bool _disposed = false;

  AudioPlayer get _p => _player ??= AudioPlayer();

  @override
  Future<void> play(String path) async {
    if (_disposed) return;
    try {
      await _p.stop();
      await _p.play(DeviceFileSource(path));
    } catch (_) {
      // 播放失败静默（文件损坏等）；级联层已做魔数校验，正常不会走到这里
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _player?.stop();
    } catch (_) {
      // 静默
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _player?.dispose();
    _player = null;
  }
}
