# AGENTS.md — AI 编码代理项目说明

> 本文件供 AI 编码代理（Codex、Claude Code、Cursor 等）快速理解本项目。开始任何修改前请先阅读本文件与 [README.md](./README.md)。

## 项目概述

**词记 (WordMem)**：一个完全离线的 Android 英语词汇学习 App。用户添加单词后，通过「艾宾浩斯遗忘曲线」间隔复习算法排程，以三段式测验（英译汉 → 选单词 → 默写）巩固记忆，并支持近义词检测、统计与备份恢复。

- 版本：`1.2.0+12`
- 平台：Android only（minSdk 26 / targetSdk 34 / compileSdk 36）
- 定位：**本地优先**。核心学习功能完全离线（词库/复习/统计/备份均在本地）；AI 功能（短文生成 / AI 陪练）可选联网，仅在用户主动使用时调用所选 AI 服务商

---

## 技术栈（锁定版本）

| 层 | 技术 | 版本 |
|----|------|------|
| Flutter | stable | 3.44.9 |
| Dart | | 3.12.2 |
| 状态管理 | flutter_riverpod | ^2.6.1 |
| 路由 | go_router | ^14.8.1 |
| 数据库 | sqlite3 + sqlite3_flutter_libs | ^2.4.6 / ^0.5.28 |
| 通知 | flutter_local_notifications | ^18.0.1 |
| 其他 | file_picker / archive / crypto / shared_preferences / path / path_provider / timezone | 见 pubspec.yaml |
| AI（可选联网） | http（OpenAI 兼容协议） / flutter_secure_storage（API Key 加密存储） | ^1.6.0 / ^10.3.1 |

> ⚠️ **重要**：数据库用 **raw sqlite3（无 ORM）**，不是 Drift。`docs/Architecture.md` 里的 Drift 方案是早期设计，已废弃。

---

## 目录结构（核心）

```
wordmem/lib/
  main.dart / app.dart              # 入口、MaterialApp、路由
  core/constants/app_constants.dart # 版本号、复习间隔等常量
  core/theme/                       # 主题与颜色
  core/utils/                       # 字符串/标签工具
  data/database/                    # app_database + word/review/stats/settings DAO
  data/repositories/                # word / review / backup / import
  data/sources/                     # dict_source（ECDICT）、synonym_dict_source（词林）
  domain/models/                    # word / review_rating / stats / synonym_* / word_option
  domain/services/fsrs_service.dart # 艾宾浩斯遗忘曲线排程（文件名沿用 FSRS）
  domain/services/synonym_detector.dart # 近义词多级检测
  domain/services/learning_context_builder.dart # 学习上下文构建（喂给 AI 的数据端口）
  infra/ai/                         # AI 接入端口：ai_config / ai_service(抽象) / openai_compatible_service / ai_config_store
  features/{today,library,review,stats,settings,add_word,word_detail}/
  infra/notification_service.dart   # 本地通知
  shared/providers/app_providers.dart # 所有 Riverpod Provider
  shared/router/app_router.dart     # go_router 路由表
  shared/widgets/                   # 通用组件
wordmem/assets/dict/
  ecdict_mini.db                    # ECDICT 词典（只读，勿改）
  synonym_cilin.json                # 哈工大同义词词林（4.5 万词条）
wordmem/scripts/                    # Python 工具脚本
```

---

## 关键架构约定（务必遵守）

### 1. 复习算法：艾宾浩斯遗忘曲线（非 FSRS）

- 实现位于 `lib/domain/services/fsrs_service.dart`（文件名保留 `fsrs` 是历史遗留，**算法已是艾宾浩斯**）。
- 间隔序列：`[3小时, 8小时, 1天, 2天, 4天, 7天, 15天, 30天]`。
- 评分 `Again/Hard/Good/Easy` 驱动阶段推进/回退。
- 卡片状态映射：`reps<=1 → learning`，`reps>=2 → review`。

### 2. 近义词多级匹配

- 数据源：`assets/dict/synonym_cilin.json`（哈工大同义词词林，词 → 义类编码列表）。
- 匹配层级：**词林义类（前 5 位编码）→ 释义关键词重叠 → 用户黑名单**。
- 实现见 `synonym_detector.dart` + `synonym_dict_source.dart` + `word_repository.dart`。

### 3. 数据库（raw sqlite3）

- 个人词库 `vocabulary.db`（WAL 模式），词典 `ecdict_mini.db`（只读，assets 复制到文档目录）。
- 所有 SQL 通过 DAO 层（`lib/data/database/*_dao.dart`），不要在 UI 层直接写 SQL。
- 备份导入关闭数据库前必须先 `PRAGMA wal_checkpoint(TRUNCATE)` 并清理 `-wal/-shm` 残留文件（历史 bug 根因）。

### 4. 离线与联网边界（v1.3.0 起调整为「本地优先 + AI 可选联网」）

- **核心学习功能必须完全离线**：词库 / 复习 / 统计 / 备份 / 导入，不得引入网络依赖。
- **AI 功能（短文生成 / 陪练）可选联网**：`AndroidManifest.xml` 已声明 `INTERNET` 权限；网络调用一律走 `infra/ai/` 抽象层（`AiService` 接口 + OpenAI 兼容实现），禁止在 UI/业务层直接拼 HTTP。
- **AI 配置集中管理**：API Key 用 `flutter_secure_storage`（Android Keystore 加密）存储；`aiConfigProvider` 是全局唯一配置入口，新 AI 功能统一 `ref.read(aiServiceProvider)` 调用。
- **学习数据喂给 AI 的统一端口**：`LearningContextBuilder.buildToday()` 产出 `DailyLearningContext`（今日新增/复习/错词/掌握分布），所有 AI prompt 必须先注入该上下文，禁止各功能各自拼学习数据。
- 新增网络依赖前先确认走 `infra/ai/` 抽象，不破坏"核心离线"边界。

### 5. 编码与配色约定

- 中文 UI；代码注释可用中文。
- 颜色统一走 `lib/core/theme/colors.dart` 的 `AppColors`。
- 股票/涨跌无关；本 App 主题跟随系统深浅色。

---

## 构建与运行

```bash
cd wordmem
flutter pub get
flutter analyze      # 目标：0 error 0 warning（既有 info 级建议可忽略）
flutter build apk --debug
```

### 环境依赖（重装后必读）

完整步骤见 [ENV_SETUP.md](./ENV_SETUP.md)。要点：

- Flutter SDK `3.44.9`（`C:/flutter`）
- Android SDK（`C:/Android/Sdk`，含 NDK `29.0.14206865`、platform 36）
- Gradle 8.9（wrapper 已配置腾讯云镜像）
- JDK 17

---

## ⚠️ 编译前强制清理流程（每次 `flutter build` 前必须执行，不得跳过）

> 2026-08-15 实测：上一次编译残留的锁文件/产物会导致下次编译**静默卡死**（无输出、无进程、11 分钟无产物）。**本机环境规则：每次编译前先清理。**

1. **查残留进程**：确认无 `java/dart/flutter/gradle` 进程（`tasklist | grep -iE "java|dart|flutter|gradle"`），有则先终止
2. **清 flutter 锁文件**（用 Python `os.remove`，⚠️ `rm`/PowerShell 会被沙箱**静默拦截**——报成功但文件仍在）：
   - `D:/flutter/bin/cache/lockfile`
   - `D:/flutter/bin/cache/flutter.bat.lock`
   - `%APPDATA%/.dart-tool/dart-flutter-telemetry-session.json`（如存在）
3. **清编译产物**（`build/`、`.dart_tool/`、`android/.kotlin`，用 PowerShell `Remove-Item -Recurse -Force` 提权；⚠️ 批量删除 >50 文件会触发 safe-delete 确认弹窗，用户批准后执行）
4. **验证**：三目录不存在 + 无锁文件
5. **跑 `flutter --version`** 确认响应正常后再开始 build

---

## 已知历史问题（避免重蹈覆辙）

1. **编译卡死**：本机曾有「沙箱假删除 flutter 锁文件 + 遥测文件拒绝访问」问题。若 `flutter` 命令无响应或输出为空，按序处理：(a) 删除 `D:/flutter/bin/cache/lockfile`、`flutter.bat.lock`；(b) 删除 `%APPDATA%/.dart-tool/dart-flutter-telemetry-session.json`；(c) **根治**：把 `%APPDATA%/.dart-tool/dart-flutter-telemetry.config` 的 `reporting=1` 改为 `reporting=0`（禁用遥测上报，否则每次启动 flutter 都会重写 session 文件并再次卡死）。2026-08-15 实测：遥测开启时 `flutter --version`/`build` 静默失败（`Failed to set file modification time ... 拒绝访问`），禁用后恢复正常。
2. **网络代理**：本机配置了 `HTTP_PROXY/HTTPS_PROXY=127.0.0.1:7890`，若代理未运行会导致 Gradle 下载失败。Gradle 已配置 `-Djava.net.useSystemProxies=false` + 阿里云 Maven 镜像 + 腾讯云 Gradle 镜像（见 `android/gradle.properties`、`settings.gradle`、`build.gradle`、`gradle-wrapper.properties`）。注：AI 功能直连服务商 API，不走 Gradle 镜像。
3. **翻卡状态残留**：复习卡片（`quiz_cards.dart`）必须传 `key: ValueKey(wordId)`，否则换词时 State 复用导致「第二词直接显示释义」。
4. **统计图溢出**：`stats_page.dart` 学习趋势现为折线图（CustomPaint），仅展示近 7 天，勿改回密集柱状图。

---

## 版本号更新清单

改版本号需同步三处：
1. `wordmem/pubspec.yaml` 的 `version: x.y.z+NN`
2. `lib/core/constants/app_constants.dart` 的 `appVersion`
3. `lib/features/settings/presentation/settings_page.dart` 关于页展示

---

## 测试数据

- `词记测试数据包-100词.zip`（项目根目录）：100 词测试数据，含多状态/多日期/近义词组，用于验证复习、导入续写、近义词挑战、统计。
- 生成脚本：`wordmem/scripts/make_test_backup.py`。
