import 'dart:convert';

/// 内置 key 的轻量加密（XOR + Base64）。
/// 目的仅为防止源码里明文出现 key、抬高脚本抓取门槛；
/// 客户端无法做到真正不可逆加密，此实现并非安全边界。
class AiKeyCipher {
  AiKeyCipher._();

  /// XOR 掩码（两端一致的简单混淆，非安全用途）
  static const String _mask = 'w0rdmem@Agnes!2026';

  static String encrypt(String plain) {
    final bytes = plain.codeUnits;
    final mask = _mask.codeUnits;
    final out = List<int>.generate(
        bytes.length, (i) => bytes[i] ^ mask[i % mask.length]);
    return base64Encode(out);
  }

  static String decrypt(String encoded) {
    final bytes = base64Decode(encoded);
    final mask = _mask.codeUnits;
    final out = List<int>.generate(
        bytes.length, (i) => bytes[i] ^ mask[i % mask.length]);
    return String.fromCharCodes(out);
  }
}

/// AI 服务商预设（OpenAI 兼容端点）
class AiProviderPreset {
  final String name;
  final String baseUrl;
  final String defaultModel;
  /// 加密后的内置 API Key（XOR+Base64，可为空；解密见 [apiKey]）
  final String _apiKeyEncoded;
  const AiProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    String apiKeyEncoded = '',
  }) : _apiKeyEncoded = apiKeyEncoded;

  /// 内置 API Key（解密后；无内置 key 时为 null）
  String? get apiKey =>
      _apiKeyEncoded.isEmpty ? null : AiKeyCipher.decrypt(_apiKeyEncoded);
}

/// 内置服务商预设，均可通过 OpenAI 兼容协议接入
class AiPresets {
  /// 内置免费服务（Agens Free）：未配置 API 时的默认回退
  static const agnes = AiProviderPreset(
    name: 'Agens(Free)',
    baseUrl: 'https://apihub.agnes-ai.com/v1',
    defaultModel: 'agnes-2.5-flash',
    apiKeyEncoded: 'BFtfBj4IJyEJPlgSN1kDeGJZDXgAAwokDHUrI18OJ2txBEpXMVlKCQkqWxY2ECgSQ3hL',
  );
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

  /// 自定义服务商（任意 OpenAI 兼容端点，Base URL / Model 由用户填写）
  static const custom = AiProviderPreset(
    name: '自定义',
    baseUrl: '',
    defaultModel: '',
  );

  static const all = [agnes, deepseek, glm, kimi, qwen, openai, doubao, custom];
}

/// AI 思考强度档位（对应 agnes Thinking mode 的 budget_tokens）
enum AiThinkingLevel {
  /// 中：标准思考，适合大多数生成任务（2048 tokens）
  medium('中', 2048),
  /// 高：深度思考，复杂短文/多步推理（4096 tokens）
  high('高', 4096),
  /// 极高：最强思考，追求最高质量（8192 tokens）
  ultra('极高', 8192);

  final String label;
  final int budgetTokens;
  const AiThinkingLevel(this.label, this.budgetTokens);

  static AiThinkingLevel fromName(String? name) {
    return switch (name) {
      'high' => AiThinkingLevel.high,
      'ultra' => AiThinkingLevel.ultra,
      _ => AiThinkingLevel.medium,
    };
  }
}

/// AI 接入配置（OpenAI 兼容协议，可指向任意服务商）
class AiConfig {
  final String providerName;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int timeoutSeconds;
  /// 是否开启深度思考（总开关；部分服务商不支持 thinking 参数时关闭以免报错）
  final bool enableThinking;
  final AiThinkingLevel thinkingLevel;

  const AiConfig({
    required this.providerName,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeoutSeconds = 30,
    this.enableThinking = true,
    this.thinkingLevel = AiThinkingLevel.medium,
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
    bool? enableThinking,
    AiThinkingLevel? thinkingLevel,
  }) {
    return AiConfig(
      providerName: providerName ?? this.providerName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      enableThinking: enableThinking ?? this.enableThinking,
      thinkingLevel: thinkingLevel ?? this.thinkingLevel,
    );
  }
}
