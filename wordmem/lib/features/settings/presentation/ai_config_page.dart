import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infra/ai/ai_config.dart';
import '../../../infra/ai/ai_exception.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/widgets/glass.dart';

/// AI 服务配置页（AI 接入端口的管理入口）
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 玻璃卡。
class AiConfigPage extends ConsumerStatefulWidget {
  const AiConfigPage({super.key});

  @override
  ConsumerState<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends ConsumerState<AiConfigPage> {
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _providerName;
  bool _enableThinking = true;
  AiThinkingLevel _thinkingLevel = AiThinkingLevel.medium;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(aiConfigProvider);
    _providerName = cfg.providerName;
    _baseUrlCtrl.text = cfg.baseUrl;
    _apiKeyCtrl.text = cfg.apiKey;
    _modelCtrl.text = cfg.model;
    _enableThinking = cfg.enableThinking;
    _thinkingLevel = cfg.thinkingLevel;
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
        enableThinking: _enableThinking,
        thinkingLevel: _thinkingLevel,
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 服务设置'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const AppBackground(),
          AdaptiveContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 内置免费服务一键启用（tinted glass 强调）
                GlassContainer(
                  blur: 16,
                  tint: theme.colorScheme.primary,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                            '没有自己的 API？可一键启用内置免费服务（Agens Free），'
                            '默认未配置时也会自动使用'),
                      ),
                      const SizedBox(width: 8),
                      GlassButton(
                        onPressed: () {
                          final preset = AiPresets.agnes;
                          setState(() {
                            _providerName = preset.name;
                            _baseUrlCtrl.text = preset.baseUrl;
                            _modelCtrl.text = preset.defaultModel;
                            _apiKeyCtrl.text = preset.apiKey ?? '';
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已填入内置免费服务，点击「保存」生效')),
                          );
                        },
                        label: '一键使用',
                        height: 40,
                        radius: 12,
                        blur: 0,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

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
          // 与词库搜索框一致的最朴素配置：不设任何 keyboardType / autocorrect /
          // enableSuggestions，避免国产 ROM 上触发系统安全键盘
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'https://api.example.com/v1',
            ),
          ),
          const SizedBox(height: 16),

          Text('模型 (Model)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'model-name',
            ),
          ),
          const SizedBox(height: 16),

          Text('API Key', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyCtrl,
            // 普通键盘（不用系统安全键盘），便于复制粘贴 API Key
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'sk-...',
              helperText: '明文显示便于粘贴核对，仅加密存储在本机',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 16),

          // 深度思考总开关
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('深度思考'),
            subtitle: const Text(
                '生成短文前先深度推理，逻辑更连贯；若所用服务商不支持请关闭'),
            value: _enableThinking,
            onChanged: (v) => setState(() => _enableThinking = v),
          ),
          const SizedBox(height: 8),

          Text('思考强度', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<AiThinkingLevel>(
            segments: AiThinkingLevel.values
                .map((l) => ButtonSegment(
                      value: l,
                      label: Text(l.label),
                      icon: Icon(switch (l) {
                        AiThinkingLevel.medium => Icons.bolt_outlined,
                        AiThinkingLevel.high => Icons.bolt,
                        AiThinkingLevel.ultra => Icons.flash_on,
                      }),
                    ))
                .toList(),
            selected: {_thinkingLevel},
            onSelectionChanged: _enableThinking
                ? (s) => setState(() => _thinkingLevel = s.first)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            _enableThinking
                ? '思考强度越高，短文逻辑越连贯，但生成更慢、消耗更多。'
                    '建议：普通生成选「中」，对质量要求高选「高」或「极高」。'
                : '深度思考已关闭，生成速度更快；开启后可选思考强度。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  onPressed: _saving ? null : _save,
                  icon: Icons.save_outlined,
                  label: '保存',
                  tinted: true,
                  height: 48,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 隐私与使用说明
          GlassContainer(
            blur: 16,
            padding: const EdgeInsets.all(12),
            child: Text(
              '说明：\n'
              '1. 接入后，「今日短文」「AI 陪练」等功能可调用所选 AI 生成个性化内容。\n'
              '2. 仅当你主动使用 AI 功能时，学习数据（今日所学单词、掌握状态等）才会发送给所选服务商。\n'
              '3. API Key 加密存储在本机（Android Keystore），不会上传到任何服务器。\n'
              '4. 支持 DeepSeek / 智谱 GLM / Kimi / 通义千问 / 豆包 / OpenAI，'
              '或选择「自定义」接入任意 OpenAI 兼容服务。\n'
              '5. 未配置 API 时自动使用内置免费服务（Agens Free），可在任意服务商间切换。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      ),
      ],
    ),
  );
  }
}
