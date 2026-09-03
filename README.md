# 词记 (WordMem)

> 离线优先的英语词汇学习与间隔复习 App（Android）

一个完全离线的英语单词记忆应用：内置专业版词典、艾宾浩斯遗忘曲线复习算法、近义词/词根群组挑战、AI 短文陪练、多阶段测验（英译汉 → 选单词 → 默写）、数据统计与备份恢复。核心学习功能**完全离线**，AI 功能可选联网。

## 下载与当前版本

- **最新版**：**v2.1.2+20**（2026-09-03 打包，含词典 v5：pro_av 航空标签净化 490→423，67 个通用词脱航并完成义项校对）
- **安装包**：`wordmem-v2.1.2-release.apk`（正式签名，65.5MB，本地归档于 `2.0发行准备/`；GitHub Releases 分发待推送）
- **平台**：Android（minSdk 26 / targetSdk 34 / compileSdk 36）
- **定位**：离线优先。词库/复习/统计/备份全部本地存储；仅 AI 功能（短文生成 / AI 陪练）在主动使用时联网（`INTERNET` 权限仅为此声明）

---

## 功能特性

| 模块 | 说明 |
|------|------|
| 学习流导航 | 今日 / 复习中心 / 短文 / 词库 / 我的 五大板块；今日页快捷入口可自定义（最多 8 个，拖拽排序） |
| 今日复习 | 三段式测验：英译汉（选择题）→ 选单词（四选一）→ 默写，熟悉度由三环节正确率综合评定 |
| 复习算法 | 艾宾浩斯 7 周期（5 分钟 → 30 分钟 → 12 小时 → 1 天 → 2 天 → 4 天 → 7 天），过完 7 周期即永久掌握 |
| 词群记忆 | **近义词挑战**（词林聚类 + 干扰项，群卡片显示核心释义、专属群测试）+ **词根挑战**（同根词卡片 → 逐题 → 汇总） |
| 内置词典 | 专业版词典 v5（15529 词，含 423 航空专业词，两轮 AI 校对 + pro_av 标签净化），支持「按新词典刷新词库释义」 |
| 近义词检测 | 基于哈工大同义词词林（4.5 万词条）的多级匹配（词林义类 → 释义关键词重叠 → 用户黑名单） |
| 短文 & AI 陪练 | 短文一句一题（理解/巩固/拓展三模式）；可配置 OpenAI 兼容 API 或使用内置免费 AI 服务 |
| 文本批量导入 | 粘贴批量导入，自动匹配词典释义；支持从测试数据包恢复 |
| 备份/恢复 | 导出 zip（含 SHA-256 校验），导入支持「覆盖 / 续写」两种模式 |
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
        ebbinghaus_service.dart      # 艾宾浩斯 7 周期排程
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
