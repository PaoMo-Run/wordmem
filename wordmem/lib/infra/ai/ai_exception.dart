/// AI 服务错误类型
enum AiErrorType {
  /// 未配置 API Key / baseUrl / model
  notConfigured,
  /// 网络不可达 / 连接失败
  network,
  /// API Key 无效或无权限（401/403）
  auth,
  /// 触发限流或额度用尽（429）
  rateLimit,
  /// 服务端错误（5xx）
  server,
  /// 返回内容解析失败
  parse,
  /// 请求超时
  timeout,
  /// 其他未知错误
  unknown,
}

/// AI 服务异常
class AiException implements Exception {
  final AiErrorType type;
  final String message;

  const AiException(this.type, this.message);

  @override
  String toString() => 'AiException(${type.name}): $message';
}
