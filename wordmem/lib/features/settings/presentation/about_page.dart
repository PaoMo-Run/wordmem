import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
      appBar: AppBar(title: const Text('关于词记')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 应用信息
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B6FE0), Color(0xFF4F8CFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Text('词',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text('词记 WordMem',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(versionText,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                Text('离线英语词库 · 艾宾浩斯 7 周期复习',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                Text('内置专业版词典 15529 词（含 490 航空专业词）',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 项目地址 / 隐私政策
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GitHub 项目地址'),
                  subtitle: const Text(_githubUrl),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openUrl(_githubUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('复制项目地址'),
                  onTap: () => _copyToClipboard(_githubUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('隐私政策'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPrivacy(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 更新日志
          Text('更新日志', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._changelog.map((v) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
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
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('· ',
                                  style: TextStyle(
                                      color: Color(0xFF4F8CFF),
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
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('我知道了'),
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

/// 更新日志条目
class _ChangelogEntry {
  final String version;
  final String date;
  final List<String> items;
  const _ChangelogEntry(this.version, this.date, this.items);
}

/// 更新日志（新版本在上）
const List<_ChangelogEntry> _changelog = [
  _ChangelogEntry('2.0.0', '2026-08-27', [
    '正式版发布：词典校对 v4 全面生效，词库释义更准确、词性更规范',
    '设置页新增「按新词典刷新词库释义」，旧词库可一键同步新释义',
    '修复短文页、词群记忆页在部分场景下的闪退问题',
    '更新日志新增完整版本记录，安装包改为 GitHub Releases 分发',
  ]),
  _ChangelogEntry('1.4.14', '2026-08-27', [
    '词典校对 v4：15036 词 AI 联网校验，主导词性单一化（多词性词减少 88%）、释义精简至 ≤4 义',
    '近义词聚类优化：新增纯净分组（beautiful / odd / wrong 等），同义词识别更准确',
  ]),
  _ChangelogEntry('1.4.13', '2026-08-21', [
    '词典全面优化：6833 条混乱释义完成修复（剔除领域标签杂糅、词性精简、修正 AM/PETS/F 等错标），词性统一为 [n.] 方括号格式，修复 ECDICT 换行残留',
    '移除标准版词典，专业版（15529 词 · 含 490 航空专业词）成为唯一内置词典，安装包更小、启动更快',
    '修复单词详情页长单词溢出问题，卡片标题自动换行',
    '近义词群挑战提交后，每个选项下方显示对应单词释义，便于对照学习',
  ]),
  _ChangelogEntry('1.4.0', '2026-08-20', [
    '近义词群挑战升级：群卡片显示核心中文释义，群内专属测试（8 词 / 至少 3 干扰项 / 答对 3 个通过），每组独立熟悉度（通过 4 次达最高）',
    '内置免费 AI 服务（Agens Free）：未配置 API 时自动使用，AI 设置页可一键启用；短文页新增「查看离线提示词」按钮',
    '复习检测英译汉改为选择题，熟悉度由三个环节（英译汉 / 选单词 / 默写）正确率综合评定',
    '单词卡新增「词根群」展示（同根词 + 进入词根挑战），支持移除误匹配的同根词',
    '修复复习中心本周复习量柱状图与统计趋势图溢出问题',
    '平板横屏适配：宽屏内容限宽居中，主框架切换为侧边导航栏',
  ]),
  _ChangelogEntry('1.3.0', '2026-08-19', [
    '复习算法升级为经典艾宾浩斯 7 周期（5 分钟 / 30 分钟 / 12 小时 / 1 天 / 2 天 / 4 天 / 7 天），过完 7 周期即永久掌握',
    '全新「学习流」导航：今日 / 复习中心 / 短文 / 词库 / 我的',
    '新增「词群记忆」：近义词挑战 + 词根挑战（词根卡片 → 逐题 → 汇总）',
    '今日页快捷入口支持自定义（最多 8 个，拖拽排序）',
    '新增「专业版」词典（航空专业词汇），词库可按「航空专业词」筛选',
    'AI Key 输入改为普通键盘，方便复制粘贴',
    '新增「关于」页：版本信息 / 更新日志 / GitHub / 隐私政策',
  ]),
  _ChangelogEntry('1.2.0', '2026-08-14', [
    '短文拓展测试：一句一题、理解 / 巩固 / 拓展三种模式',
    'AI 深度思考开关与思考强度调节',
    '近义词挑战：从词库自动聚类易混淆词',
    '支持从文本批量导入单词',
  ]),
  _ChangelogEntry('1.1.3', '2026-08-08', [
    '底部导航改版，词库搜索与筛选增强',
    '复习统计与掌握状态可视化',
  ]),
];
