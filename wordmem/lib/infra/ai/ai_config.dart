/// AI 服务商预设（OpenAI 兼容端点）
class AiProviderPreset {
  final String name;
  final String baseUrl;
  final String defaultModel;
  const AiProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
  });
}

/// 内置服务商预设，均可通过 OpenAI 兼容协议接入
class AiPresets {
  static const deepseek = AiProviderPreset(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
  );
  static const glm = AiProviderPreset(
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-flash',
  );
  static const kimi = AiProviderPreset(
    name: 'Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
  );
  static const qwen = AiProviderPreset(
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
  );
  static const openai = AiProviderPreset(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
  );
  static const doubao = AiProviderPreset(
    name: '豆包',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModel: '',
  );

  static const all = [deepseek, glm, kimi, qwen, openai, doubao];
}

/// AI 接入配置（OpenAI 兼容协议，可指向任意服务商）
class AiConfig {
  final String providerName;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int timeoutSeconds;

  const AiConfig({
    required this.providerName,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeoutSeconds = 30,
  });

  /// 是否已配置完整（未来 AI 功能的统一开关判断）
  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  AiConfig copyWith({
    String? providerName,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? timeoutSeconds,
  }) {
    return AiConfig(
      providerName: providerName ?? this.providerName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }
}
