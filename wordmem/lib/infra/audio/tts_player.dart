import 'package:flutter_tts/flutter_tts.dart';

/// 系统 TTS 播放抽象（便于测试注入与替换实现）。
abstract class TtsPlayer {
  /// 懒初始化 + 英语语音可用性判定。
  ///
  /// 返回 false 表示系统无英语语音包（调用方应永久跳过 TTS 兜底）。
  Future<bool> ensureReady();

  /// 朗读单词文本。
  Future<void> speak(String word);

  /// 停止朗读。
  Future<void> stop();

  /// 释放底层资源。
  void dispose();
}

/// 基于 flutter_tts 的薄封装：懒初始化，`en-US` 不可用即进入不可用态。
class FlutterTtsPlayer implements TtsPlayer {
  FlutterTts? _tts;
  bool _ready = false;
  bool _unavailable = false;
  bool _disposed = false;

  FlutterTts get _engine => _tts ??= FlutterTts();

  @override
  Future<bool> ensureReady() async {
    if (_ready) return true;
    if (_unavailable || _disposed) return false;
    try {
      final tts = _engine;
      await tts.setLanguage('en-US');
      final available = await tts.isLanguageAvailable('en-US');
      if (available != true) {
        _unavailable = true;
        return false;
      }
      _ready = true;
      return true;
    } catch (_) {
      // 平台异常（如无 TTS 引擎）→ 不可用态
      _unavailable = true;
      return false;
    }
  }

  @override
  Future<void> speak(String word) async {
    if (_disposed || !_ready) return;
    try {
      await _engine.speak(word);
    } catch (_) {
      // 静默：TTS 兜底失败不影响主流程
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _tts?.stop();
    } catch (_) {
      // 静默
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // flutter_tts 无显式 dispose API，仅丢弃引用
    _tts = null;
  }
}
