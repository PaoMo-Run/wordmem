import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';

/// AI 配置持久化。
///
/// - apiKey：存入系统安全存储（Android Keystore 加密），不落明文
/// - 其余（服务商/baseUrl/model/超时）：存入 SharedPreferences
class AiConfigStore {
  static const _kProvider = 'ai.provider';
  static const _kBaseUrl = 'ai.base_url';
  static const _kModel = 'ai.model';
  static const _kTimeout = 'ai.timeout';
  static const _kThinkingLevel = 'ai.thinking_level';
  static const _kEnableThinking = 'ai.enable_thinking';
  static const _kApiKey = 'ai.api_key';

  final FlutterSecureStorage _secure;
  final SharedPreferences? _prefs;

  AiConfigStore({FlutterSecureStorage? secure, SharedPreferences? prefs})
      : _secure = secure ?? const FlutterSecureStorage(),
        _prefs = prefs;

  /// 读取配置（未配置过则返回 DeepSeek 默认模板）
  Future<AiConfig> load() async {
    final p = _prefs;
    return AiConfig(
      providerName: p?.getString(_kProvider) ?? AiPresets.deepseek.name,
      baseUrl: p?.getString(_kBaseUrl) ?? AiPresets.deepseek.baseUrl,
      apiKey: await _secure.read(key: _kApiKey) ?? '',
      model: p?.getString(_kModel) ?? AiPresets.deepseek.defaultModel,
      timeoutSeconds: p?.getInt(_kTimeout) ?? 30,
      enableThinking: p?.getBool(_kEnableThinking) ?? true,
      thinkingLevel:
          AiThinkingLevel.fromName(p?.getString(_kThinkingLevel)),
    );
  }

  /// 保存配置（apiKey 为空时跳过写入，保留原值）
  Future<void> save(AiConfig config) async {
    final p = _prefs;
    await p?.setString(_kProvider, config.providerName);
    await p?.setString(_kBaseUrl, config.baseUrl);
    await p?.setString(_kModel, config.model);
    await p?.setInt(_kTimeout, config.timeoutSeconds);
    await p?.setBool(_kEnableThinking, config.enableThinking);
    await p?.setString(_kThinkingLevel, config.thinkingLevel.name);
    if (config.apiKey.isNotEmpty) {
      await _secure.write(key: _kApiKey, value: config.apiKey);
    }
  }

  /// 清除 API Key（不删除其他配置）
  Future<void> clearApiKey() async {
    await _secure.delete(key: _kApiKey);
  }
}
