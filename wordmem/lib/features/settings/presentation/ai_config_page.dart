import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infra/ai/ai_config.dart';
import '../../../infra/ai/ai_exception.dart';
import '../../../shared/providers/app_providers.dart';

/// AI 服务配置页（AI 接入端口的管理入口）
class AiConfigPage extends ConsumerStatefulWidget {
  const AiConfigPage({super.key});

  @override
  ConsumerState<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends ConsumerState<AiConfigPage> {
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _obscureKey = true;
  bool _saving = false;
  bool _testing = false;
  String? _providerName;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(aiConfigProvider);
    _providerName = cfg.providerName;
    _baseUrlCtrl.text = cfg.baseUrl;
    _apiKeyCtrl.text = cfg.apiKey;
    _modelCtrl.text = cfg.model;
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(AiProviderPreset preset) {
    setState(() {
      _providerName = preset.name;
      _baseUrlCtrl.text = preset.baseUrl;
      _modelCtrl.text = preset.defaultModel;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = AiConfig(
        providerName: _providerName ?? AiPresets.deepseek.name,
        baseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
      );
      await ref.read(aiConfigProvider.notifier).save(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 配置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    try {
      // 先保存表单值，再基于最新配置发起连通性测试
      await _save();
      final service = ref.read(aiServiceProvider);
      await service.testConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功，AI 服务可用')),
        );
      }
    } on AiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('服务商', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _providerName,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '选择服务商',
            ),
            items: AiPresets.all
                .map((p) => DropdownMenuItem(value: p.name, child: Text(p.name)))
                .toList(),
            onChanged: (name) {
              if (name == null) return;
              _applyPreset(AiPresets.all.firstWhere((p) => p.name == name));
            },
          ),
          const SizedBox(height: 16),

          Text('API 地址 (Base URL)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'https://api.deepseek.com/v1',
            ),
          ),
          const SizedBox(height: 16),

          Text('模型 (Model)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'deepseek-chat',
            ),
          ),
          const SizedBox(height: 16),

          Text('API Key', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 隐私与使用说明
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '说明：\n'
                '1. 接入后，「今日短文」「AI 陪练」等功能可调用所选 AI 生成个性化内容。\n'
                '2. 仅当你主动使用 AI 功能时，学习数据（今日所学单词、掌握状态等）才会发送给所选服务商。\n'
                '3. API Key 加密存储在本机（Android Keystore），不会上传到任何服务器。\n'
                '4. 支持 DeepSeek / 智谱 GLM / Kimi / 通义千问 / 豆包（OpenAI 兼容协议）。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
