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
                      Text('可离线运行的记单词 App · FSRS 间隔复习',
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
1. 词记（WordMem）是一款可离线运行的记单词应用。核心功能（词库、复习、学习统计）完全离线可用，你的词库、复习记录、学习统计等数据默认仅存储在你的设备本地（SQLite 数据库），不会上传到任何服务器。
2. API Key、网盘账号与应用密码等敏感配置使用系统安全存储（Android Keystore）加密保存，仅在本机使用。

二、联网功能与数据传输
1. 仅当你主动使用「今日短文」「AI 陪练」等 AI 功能时，当日所选的学习数据（今日所学单词、掌握状态等）才会发送给你所选的服务商（如 DeepSeek、智谱、Kimi、通义千问、豆包、OpenAI 兼容服务、内置 Agens 免费服务等）用于生成内容。
2. 若你未配置自己的 API，应用默认使用内置的 Agens 免费服务；该服务为第三方免费额度，可能因用量限制而暂停，你可在「我的 - AI 服务」中随时更换为其他服务商。
3. 单词发音：仅当你点击喇叭按钮时，应用会将该单词的拼写文本发送给在线音源（有道、百度）获取发音音频，并在本地缓存供离线复用；此过程不发送其他任何数据。
4. 从网络同步：仅当你主动使用「从网络同步」时，应用才会通过 WebDAV 将你的备份（词库、复习记录等）上传到你自行配置的个人网盘（如坚果云），或从该网盘下载恢复；网盘账号与应用密码仅保存在你的设备上，不会包含在备份文件中。
5. 除上述功能外，应用不会在后台收集或上传任何个人数据。

三、第三方服务
1. 应用内置开源词典数据（ECDICT 系）与公开词根词缀资料，仅用于本地查询。
2. 应用不含广告 SDK 与第三方统计 SDK。

四、你的权利
你可以随时在「我的 - 数据」中导出或删除全部学习数据，或卸载应用彻底清除本地数据。

五、联系我们
如对本政策有疑问，可通过 GitHub 项目地址（Issues）与我们联系。

更新日期：2026-09-03''';
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
  _ChangelogEntry('2.1.11', '2026-09-23', [
    '新增「提前背」：首页「未来 3 小时有 N 个词将到期」旁可一键把这些词提前复习一轮（二次确认后开始），适合预知接下来没空复习的情况；复习结果正常记录并推进复习阶段',
  ]),
  _ChangelogEntry('2.1.10', '2026-09-22', [
    '词库新增「按上次复习时间」排序：可快速找出最近复习过、或最久没碰过的词；从未复习过的新词固定排在最后',
  ]),
  _ChangelogEntry('2.1.9', '2026-09-22', [
    '取消「熟练跳过」：所有词都必须完整走完 8 次复习，不再因答得好而少做测验',
    '新增每轮测验评分（满分 6 分）：三个环节每答错一次扣 1 分、超过限时再扣 1 分；0 分不熟悉、1–2 分刚弄懂、3–4 分已了解、5–6 分很清楚',
    '作答时显示圆形倒计时：英译汉与选单词 5 秒、默写 8 秒；锁屏或切后台回来会重新计时',
    '单词详情页「复习历史」重做：显示每次得分、超时次数与档位，熟练词抽检记录显示为「抽查正确 / 抽查失败」',
    '时间显示精确到小时（如「2天3小时前」），不再只显示「N天前」',
    '自选复习与今日复习流程统一：每组结束出本组统计页，可「下一组 / 完成」，有错题先问是否重测',
  ]),
  _ChangelogEntry('2.1.8', '2026-09-20', [
    '「本组完成」统计页改为每组结束都出现，页内用「下一组 / 完成 / 上传进度」决定下一步',
    '每组结束按「抽检 → 重测 → 统计页」的顺序询问，不再连弹两个弹窗',
    '错题重测提前到每组结束，答完回到本组统计页（不再攒到整轮末）',
    '三个测验环节各自打乱出题顺序，避免靠位置记答案',
    '删掉每题下方重复的「跳过」按钮（右上角「下一题」等价）；未作答时「下一题」高亮',
    '上传云端改为统计页按钮；未配置网盘时置灰并提示去哪里配置',
    '修复默写输入框被键盘遮挡（聚焦后自动滚到键盘上方，息屏回来重新定位）',
  ]),
];
