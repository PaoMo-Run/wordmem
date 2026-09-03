import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/glass.dart';

/// 关于页：版本信息 + 更新日志 + GitHub 项目地址 + 隐私政策
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      // 读取失败时保留空字符串（显示占位）
    }
  }

  static const String _githubUrl = 'https://github.com/PaoMo-Run/wordmem';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败: $e')));
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final versionText =
        _version.isEmpty ? 'v2.0.0' : 'v$_version${_buildNumber.isNotEmpty ? ' ($_buildNumber)' : ''}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('关于词记'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              // 应用信息
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryLight,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: Text('词',
                            style: theme.textTheme.headlineLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      Text('词记 WordMem',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(versionText,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('离线英语词库 · FSRS 间隔复习',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('内置专业版词典 15529 词（含 426 航空专业词）',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),

              // 项目地址 / 隐私政策
              const _SectionHeader('更多信息'),
              GlassSection(
                children: [
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('GitHub 项目地址'),
                    subtitle: const Text(_githubUrl),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(_githubUrl),
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: const Text('复制项目地址'),
                    onTap: () => _copyToClipboard(_githubUrl),
                  ),
                  ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('隐私政策'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showPrivacy(),
                  ),
                ],
              ),

              // 更新日志
              const _SectionHeader('更新日志'),
              ..._changelog.map((v) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: GlassContainer(
                      // 长列表条目：静态玻璃（blur 0），避免 8 个实时模糊拖垮滚动
                      blur: 0,
                      elevated: false,
                      radius: 14,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('v${v.version} · ${v.date}',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          for (final item in v.items)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('· ',
                                      style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w800)),
                                  Expanded(
                                    child: Text(item,
                                        style: theme.textTheme.bodySmall),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
    );
  }

  /// 隐私政策（内置文本，覆盖数据收集与使用）
  void _showPrivacy() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('隐私政策',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    _privacyText,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(height: 1.7),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GlassButton(
                  onPressed: () => Navigator.pop(ctx),
                  label: '我知道了',
                  tinted: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const String _privacyText = '''
一、数据存储
1. 词记（WordMem）是一款离线优先的词汇学习应用。你的词库、复习记录、学习统计等全部数据默认仅存储在你的设备本地（SQLite 数据库），不会上传到任何服务器。
2. API Key 等敏感配置使用系统安全存储（Android Keystore）加密保存，仅在本机使用。

二、AI 功能与数据传输
1. 仅当你主动使用「今日短文」「AI 陪练」等 AI 功能时，当日所选的学习数据（今日所学单词、掌握状态等）才会发送给你所选的服务商（如 DeepSeek、智谱、Kimi、通义千问、豆包、OpenAI 兼容服务、内置 Agens 免费服务等）用于生成内容。
2. 若你未配置自己的 API，应用默认使用内置的 Agens 免费服务；该服务为第三方免费额度，可能因用量限制而暂停，你可在「我的 - AI 服务」中随时更换为其他服务商。
3. 除上述 AI 功能外，应用不会在后台收集或上传任何个人数据。

三、第三方服务
1. 应用内置开源词典数据（ECDICT 系）与公开词根词缀资料，仅用于离线查询。
2. 应用不含广告 SDK 与第三方统计 SDK。

四、你的权利
你可以随时在「我的 - 数据」中导出或删除全部学习数据，或卸载应用彻底清除本地数据。

五、联系我们
如对本政策有疑问，可通过 GitHub 项目地址（Issues）与我们联系。

更新日期：2026-08-20''';
}

/// 区块标题（与 settings_page / me_page 同款）
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 更新日志条目
class _ChangelogEntry {
  final String version;
  final String date;
  final List<String> items;
  const _ChangelogEntry(this.version, this.date, this.items);
}

/// 更新日志（新版本在上，仅保留最近 4 次）
const List<_ChangelogEntry> _changelog = [
  _ChangelogEntry('2.1.2', '2026-09-03', [
    '词典升级 v5：「航空专业词」标签净化——67 个通用词（primary/captain/right/control 等）移除航空标签，新添加的航空词不再混入通用词',
    '上述 67 词释义同步精简校对（主导词性单一化、义项 ≤4，与 v4 校对规则一致）',
  ]),
  _ChangelogEntry('2.1.1', '2026-09-03', [
    '新增单词发音：点击单词旁的喇叭即可播放（词库列表 / 复习卡片 / 单词详情 / 短文弹卡），音源为 本地缓存 → 有道 → 百度 → 系统语音 自动降级，同一单词仅需在线取一次',
    '发音开关移入「我的 - 偏好」，可随时关闭所有喇叭按钮',
    '修复自选复习英译汉作答后跳过答案展示、直接进入下一题的问题',
    '修复断网时点过发音的单词，网络恢复后仍无法重播的问题（需重启才恢复）',
  ]),
  _ChangelogEntry('2.0.1', '2026-08-31', [
    'v3→v11 全 App 视觉与交互重做：iOS 液体玻璃材质（GlassContainer/Button/Section/NavBar）全 App 落地，M3 规范化、teal 品牌种子 #00897B',
    '5 颗静态 aurora 光斑背景（修复「光斑从来显示不出」顽疾：原光斑尺寸 > 屏宽 + 6 颗重叠糊成平涂，改为小尺寸独立可辨），关闭 Impeller 回退 Skia（红米/HyperOS 兼容），切页换轻量 FadeForwards 450ms',
    '性能清理：18 个 push 页面 body 删冗余 AppBackground（消除双重渲染），空转 60fps AuroraTickerHost 删除，2 个死代码文件清理，20 个 widget 自动化测试通过',
    '布局：5 tab 底部 116px 避让悬浮 dock，词库分页改手动下滑加载（overscroll > 60px），今日短文按钮 Row→Wrap 修溢出',
    '玻璃交互：「开始测试」→「测试」+ GlassButton padding: 0 → horizontal: 18 真因修复（v5 调高度无效的根因）',
  ]),
  _ChangelogEntry('2.0.0', '2026-08-27', [
    '正式版发布：词典校对 v4 全面生效，词库释义更准确、词性更规范',
    '设置页新增「按新词典刷新词库释义」，旧词库可一键同步新释义',
    '修复短文页、词群记忆页在部分场景下的闪退问题',
    '更新日志新增完整版本记录，安装包改为 GitHub Releases 分发',
  ]),
];
