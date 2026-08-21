import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';
import 'ai_exception.dart';
import 'ai_service.dart';

/// OpenAI 兼容协议实现。
///
/// 覆盖 DeepSeek / 智谱 GLM / Kimi / 通义千问 / 豆包（OpenAI 兼容端点）等，
/// 仅需配置 baseUrl + apiKey + model。
class OpenAiCompatibleService implements AiService {
  final AiConfig config;
  final http.Client _client;

  OpenAiCompatibleService(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Uri get _chatUri => Uri.parse('${config.baseUrl}/chat/completions');

  Map<String, Object?> _buildBody(AiRequest request, {bool stream = false}) {
    final body = <String, Object?>{
      'model': config.model,
      'messages': request.messages
          .map((m) => {'role': m.roleName, 'content': m.content})
          .toList(),
      'temperature': request.temperature,
      'max_tokens': request.maxTokens,
      'stream': stream,
    };
    // 深度思考：agnes 等平台通过 thinking 参数控制推理强度
    // （budget_tokens 越大，思考越深入，质量越高但耗时/消耗越大）
    if (request.enableThinking) {
      body['thinking'] = {
        'type': 'enabled',
        'budget_tokens': request.thinkingBudgetTokens,
      };
    }
    return body;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      };

  @override
  Future<AiResponse> chat(AiRequest request) async {
    _ensureConfigured();
    try {
      final resp = await _client
          .post(_chatUri, headers: _headers, body: jsonEncode(_buildBody(request)))
          .timeout(Duration(seconds: config.timeoutSeconds));
      return _parseChatResponse(resp);
    } on TimeoutException {
      throw const AiException(AiErrorType.timeout, 'AI 请求超时，请检查网络或稍后重试');
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException(AiErrorType.network, '网络请求失败: $e');
    }
  }

  @override
  Stream<String> chatStream(AiRequest request) async* {
    _ensureConfigured();
    final req = http.Request('POST', _chatUri)
      ..headers.addAll(_headers)
      ..body = jsonEncode(_buildBody(request, stream: true));

    http.StreamedResponse resp;
    try {
      resp = await _client
          .send(req)
          .timeout(Duration(seconds: config.timeoutSeconds));
    } on TimeoutException {
      throw const AiException(AiErrorType.timeout, 'AI 请求超时');
    } catch (e) {
      throw AiException(AiErrorType.network, '网络请求失败: $e');
    }

    if (resp.statusCode != 200) {
      final body = await resp.stream.bytesToString();
      throw _mapHttpError(resp.statusCode, body);
    }

    // 解析 SSE：data: {...} 或 data: [DONE]
    await for (final line
        in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta =
            ((choices.first as Map<String, dynamic>)['delta']
                    as Map<String, dynamic>?)?
                ['content'];
        if (delta is String && delta.isNotEmpty) yield delta;
      } catch (_) {
        // 忽略无法解析的 SSE 片段
      }
    }
  }

  @override
  Future<void> testConnection() async {
    _ensureConfigured();
    // 推理模型（如 agnes-2.5-flash）会先消耗 token 在思考过程（reasoning_content）上，
    // maxTokens 太小会导致正式内容（content）为空而被误判为无返回。
    // 使用 512 确保推理模型能正常输出正文。
    final resp = await chat(const AiRequest(
      messages: [AiMessage(role: AiRole.user, content: 'ping')],
      maxTokens: 512,
      temperature: 0,
    ));
    if (resp.content.trim().isEmpty) {
      throw const AiException(AiErrorType.parse, '连通性测试无返回内容');
    }
  }

  void _ensureConfigured() {
    if (!config.isConfigured) throw aiNotConfigured();
  }

  AiResponse _parseChatResponse(http.Response resp) {
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw const AiException(AiErrorType.parse, 'AI 返回格式异常：缺少 choices');
        }
        final content =
            (choices.first as Map<String, dynamic>)['message']?['content'] as String? ??
                '';
        final usage = data['usage'] as Map<String, dynamic>?;
        return AiResponse(
          content: content,
          promptTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
          completionTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
          model: data['model'] as String?,
        );
      } on AiException {
        rethrow;
      } catch (e) {
        throw AiException(AiErrorType.parse, 'AI 返回解析失败: $e');
      }
    }
    throw _mapHttpError(resp.statusCode, utf8.decode(resp.bodyBytes, allowMalformed: true));
  }

  AiException _mapHttpError(int statusCode, String body) {
    final brief = body.length > 300 ? body.substring(0, 300) : body;
    return switch (statusCode) {
      401 || 403 => AiException(
          AiErrorType.auth, 'API Key 无效或无权访问（HTTP $statusCode）: $brief'),
      429 => const AiException(AiErrorType.rateLimit, '请求过于频繁或额度用尽（HTTP 429）'),
      >= 500 => AiException(
          AiErrorType.server, 'AI 服务端错误（HTTP $statusCode）: $brief'),
      _ => AiException(AiErrorType.unknown, '请求失败（HTTP $statusCode）: $brief'),
    };
  }
}
