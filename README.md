# 词记 (WordMem)

> 可离线运行的英语记单词与间隔复习 App（Android）

一款可离线运行的英语单词记忆应用：内置专业版词典、艾宾浩斯式 **T0–T7 八节点固定时间线**复习算法、熟练词抽检、近义词/词根群组挑战、AI 短文陪练、多阶段测验（英译汉 → 选单词 → 默写）、数据统计与备份恢复。核心学习功能**完全离线可用**；单词发音、AI 功能、从网络同步（WebDAV）为可选联网增强。

## 下载与当前版本

- **最新版**：**v2.1.6+24**（2026-09-16 发行：复习时间线重构为 **T0–T7 八节点** + 按节点解锁跳过；新增**熟练词抽检**防止已掌握词遗忘；熟练度改为 4 档中文标签「小试牛刀 → 初出茅庐 → 炉火纯青 → 登峰造极」；每个 50 词组结束均可上传云端；词库支持按到期时间排序、首页提示未来 3 小时到期词数）
- **安装包**：`wordmem-v2.1.6-release.apk`（正式签名，67.2MB，GitHub Releases 分发；本地归档于 `2.0发行准备/`）
- **平台**：Android（minSdk 26 / targetSdk 34 / compileSdk 36）
- **定位**：可离线运行。词库/复习/统计/备份全部本地存储；单词发音（在线音源 + 本地缓存）、AI 功能、从网络同步（用户自配 WebDAV 网盘）仅在主动使用时联网

---

## 功能特性

| 模块 | 说明 |
|------|------|
| 学习流导航 | 今日 / 复习中心 / 短文 / 词库 / 我的 五大板块；今日页快捷入口可自定义（最多 9 个，拖拽排序）；首页顶部卡片提示**未来 3 小时将到期**的词数 |
| 今日复习 | 三段式测验：英译汉（选择题）→ 选单词（四选一）→ 默写，熟练度由三环节正确率综合评定；待复习词按 **50 词一组**分批；进度**每答一题自动保存**（中途退出可续）；作答后选项与反馈限高滚动，防长释义把按钮顶出屏幕；每组结束询问是否抽检熟练词、是否上传云端；全部结束后可**重做错题**（含抽检错词） |
| 复习算法 | **T0–T7 八节点固定时间线**：添加后 1 小时 → 3 小时 → 5 小时 → 12 小时 → 1 天 → 2 天 → 2 天（约 5.9 天走完全程）。只有三环节**全对**才解锁跳过——第 1 次全对可跳过第 2 个节点（等 8h），第 3 次仍全对才可再跳过第 4 个节点（等 24h）；第 1 次没全对则全程不再跳过；任何答题结果都会推进到下一节点，超期不跳档也不补做 |
| 熟练度 | 按复习进度 **4 档**递增显示：**小试牛刀 → 初出茅庐 → 炉火纯青 → 登峰造极**（跳过节点会更快升档） |
| 熟练词抽检 | 已掌握词不再「永久毕业」：每完成一组复习可随机抽 **5 个**做默写复查（也可从自选复习页手动发起）。按「**最久未抽优先**」调度，保证不会有词被长期漏掉；答对间隔 15 天，答错进入 3 天复检窗口，重测或复检再错则退回第 3 档重走周期 |
| 词库管理 | 搜索（英文 / 中文释义）、筛选（收藏 / 新词 / 学习中 / 复习中 / 短文测试 / 航空专业词）、**排序（按添加时间 / 按到期时间 / 按字母）** |
| 词群记忆 | **近义词挑战**（词林聚类 + 干扰项，群卡片显示核心释义、专属群测试）+ **词根挑战**（同根词卡片 → 逐题 → 汇总） |
| 内置词典 | 专业版词典 v5（15529 词，含 423 航空专业词，两轮 AI 校对 + pro_av 标签净化），支持「按新词典刷新词库释义」 |
| 近义词检测 | 基于哈工大同义词词林（4.5 万词条）的多级匹配（词林义类 → 释义关键词重叠 → 用户黑名单） |
| 短文 & AI 陪练 | 短文一句一题（理解/巩固/拓展三模式）；可配置 OpenAI 兼容 API 或使用内置免费 AI 服务 |
| 文本批量导入 | 粘贴批量导入，自动匹配词典释义；支持从测试数据包恢复 |
| 备份/恢复 | 导出 zip（含 SHA-256 校验），导入支持「覆盖 / 续写」两种模式 |
| 从网络同步 | 通过 WebDAV（支持坚果云）手动上传/下载备份快照：水位 + parent 链判定新旧、防呆确认、云端保留最近 10 份本机快照（列表按时间倒序只展示最近 5 份，更多以汇总提示代替），支持删除云端备份；每个 50 词组复习结束都会询问是否上传；换设备「先上传 → 再下载」接力 |
| 统计 | 学习趋势折线图、掌握状态分布、连续学习天数、本周复习量 |
| 提醒通知 | 本地通知，每日复习提醒（无网络依赖） |
| 平板适配 | 宽屏内容限宽居中，主框架切换为侧边导航栏 |

---

## 技术栈

| 层 | 技术 | 版本 |
|----|------|------|
| 框架 | Flutter | 3.44.9（stable） |
| 语言 | Dart | 3.12.2 |
| 状态管理 | flutter_riverpod | ^2.6.1 |
| 路由 | go_router | ^14.8.1 |
| 数据库 | sqlite3 + sqlite3_flutter_libs | ^2.4.6 / ^0.5.28（**raw SQL，非 ORM**） |
| AI 接入 | http（OpenAI 兼容 Chat Completions） | ^1.6.0 |
| 通知 | flutter_local_notifications | ^18.0.1 |
| 时区 | timezone | ^0.9.4 |
| 文件选择 | file_picker | ^8.3.1 |
| 链接/版本 | url_launcher / package_info_plus | ^6.3.1 / ^8.0.2 |
| 路径 | path / path_provider | ^1.9.0 / ^2.1.5 |
| 压缩 | archive | ^3.6.1 |
| 校验 | crypto | ^3.0.6 |
| 偏好存储 | shared_preferences | ^2.3.5 |

### Android 构建配置

- compileSdk 36 / minSdk 26 / targetSdk 34
- NDK `29.0.14206865`
- Java 17 / Kotlin 1.9.24
- ABI：`arm64-v8a`, `armeabi-v7a`, `x86_64`
- `applicationId`：`com.wordmem.app`
- release 构建：正式签名（`android/key.properties`）+ R8 混淆 + 资源收缩

---

## 目录结构

```
wordmem/
  lib/
    main.dart                        # 入口
    app.dart                         # MaterialApp + 主题 + 路由
    core/
      constants/app_constants.dart   # 常量（版本号、词典版本、间隔等）
      theme/                         # 主题、颜色
      utils/                         # 字符串、标签工具
    data/
      database/                      # SQLite 连接 + DAO（word/review/stats/settings）
      repositories/                  # word / review / backup / import / story 仓储
      sources/                       # dict_source（ECDICT）+ synonym_dict_source（词林）
    domain/
      models/                        # word / review_rating / stats / synonym_* / word_option
      services/
        fsrs_service.dart            # T0–T7 八节点时间线排程（含跳过状态机）
        synonym_detector.dart        # 近义词多级检测
        root_matcher.dart            # 词根匹配
    features/
      today/                         # 今日页（复习 + 快捷入口）
      library/                       # 词库列表（含航空专业词筛选）
      review/                        # 复习中心 + 词群记忆（近义/词根挑战）
      story/                         # 短文 + AI 陪练
      stats/                         # 统计页
      settings/                      # 设置页（含刷新释义、AI 服务配置、关于）
      add_word/                      # 添加单词 / 文本导入
      word_detail/                   # 单词详情（词根群展示）
    infra/
      ai/                            # AI 接入（配置 + OpenAI 兼容服务 + 安全存储 API Key）
      notification_service.dart      # 本地通知
    shared/
      providers/app_providers.dart   # Riverpod Provider 汇总
      router/app_router.dart         # go_router 路由表
      widgets/                       # 通用组件
  assets/dict/
    ecdict_pro.db                    # 专业版词典（唯一内置，只读 SQLite，15529 词）
    synonym_cilin.json               # 哈工大同义词词林（4.5 万词条）
  android/                           # Android 工程（签名/混淆配置）
docs/                                # 设计文档（PRD / Architecture / UIUX）
```

> ⚠️ `docs/Architecture.md` 是早期设计文档，其中描述的 Drift ORM 与 FSRS 包方案已被实际代码取代（改用 raw sqlite3 + 艾宾浩斯算法），以 `lib/` 下代码为准。

---

## 环境要求与构建

完整环境搭建步骤见 **[ENV_SETUP.md](./ENV_SETUP.md)**。

```bash
cd wordmem
flutter pub get
flutter analyze          # 静态检查（0 issue 为发布门槛）
flutter build apk --release   # 正式包（签名 + R8）
flutter build apk --debug     # 调试包
```

> 💡 本机注意：含 Flutter 的命令请在 WorkBuddy 沙箱外运行（`dangerouslyDisableSandbox`），详见 `flutter-build-precheck` 技能。

---

## 发布与 CI

- **默认分支**：`main`（GitHub Actions CI：推送 main 自动跑 `flutter analyze` + `flutter test`，红灯不允许发布）
- **发布流程**：见 `docs` 与发布说明（tag `vX.Y.Z` → GitHub Release 上传 APK → 公布 SHA256）
- **词典数据**：数据改动须同步 `dictProVersion`（当前 `ecdict_pro_v5`），否则已安装用户不重载

---

## 相关文档

- [ENV_SETUP.md](./ENV_SETUP.md) — 环境重建指南（重装系统后必读）
- [AGENTS.md](./AGENTS.md) — AI 编码代理（如 Codex）项目说明
- `docs/PRD.md` — 产品需求文档
- `docs/Architecture.md` — 架构设计（早期版本，部分过时）
- `docs/UIUX.md` — UI/UX 设计
