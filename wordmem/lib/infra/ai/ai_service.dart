import 'ai_exception.dart';

/// AI 消息角色
enum AiRole { system, user, assistant }

/// AI 对话消息
class AiMessage {
  final AiRole role;
  final String content;

  const AiMessage({required this.role, required this.content});

  String get roleName => switch (role) {
        AiRole.system => 'system',
        AiRole.user => 'user',
        AiRole.assistant => 'assistant',
      };
}

/// AI 单次请求
class AiRequest {
  final List<AiMessage> messages;
  final double temperature;
  final int maxTokens;

  const AiRequest({
    required this.messages,
    this.temperature = 0.7,
    this.maxTokens = 1024,
  });
}

/// AI 回复
class AiResponse {
  final String content;
  final int promptTokens;
  final int completionTokens;
  final String? model;

  const AiResponse({
    required this.content,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.model,
  });
}

/// AI 服务抽象接口。
///
/// 设计目标：统一端口，供「今日短文生成」「AI 陪练」等未来功能复用。
/// 实现采用 OpenAI 兼容协议，可插拔接入任意服务商（DeepSeek / GLM / Kimi / 通义 / 豆包等）。
abstract class AiService {
  /// 非流式对话补全
  Future<AiResponse> chat(AiRequest request);

  /// 流式对话补全（SSE），供未来 AI 陪练逐字输出使用
  Stream<String> chatStream(AiRequest request);

  /// 连通性测试：校验配置（baseUrl / apiKey / model）是否可用
  Future<void> testConnection();
}

/// 便捷构造函数：根据是否配置抛出对应错误
AiException aiNotConfigured() =>
    const AiException(AiErrorType.notConfigured, 'AI 尚未配置，请先在「设置 - AI 服务」中填写 API Key');
