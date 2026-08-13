# 词记 (WordMem)

> 离线英语词汇学习与间隔复习 App（Android）

一个完全离线的英语单词记忆应用，内置词典、艾宾浩斯遗忘曲线复习算法、近义词检测、多阶段测验（英译汉 → 选单词 → 默写）、数据统计与备份恢复。

## 当前版本

- **版本号**：`1.1.3+11`（见 `wordmem/pubspec.yaml`）
- **平台**：Android（minSdk 26 / targetSdk 34 / compileSdk 36）
- **定位**：完全离线，无任何网络请求（`AndroidManifest.xml` 不声明 `INTERNET` 权限）

---

## 功能特性

| 模块 | 说明 |
|------|------|
| 今日复习 | 三段式测验：英译汉（翻卡）→ 选单词（四选一）→ 默写 |
| 复习算法 | 艾宾浩斯遗忘曲线，间隔 `3h → 8h → 1d → 2d → 4d → 7d → 15d → 30d`，评分驱动（Again/Hard/Good/Easy） |
| 熟悉度联动 | 翻卡选「很轻松」但后续选单词/默写出错时，自动降级该词排程 |
| 选单词 | 干扰项从整本词典按编辑距离挑选「形似词」，提交后显示各选项释义 |
| 近义词挑战 | 基于哈工大同义词词林的多级匹配（词林义类 → 释义关键词重叠 → 用户黑名单） |
| 文本批量导入 | 支持粘贴批量导入，自动匹配词典释义 |
| 备份/恢复 | 导出 zip（含 SHA-256 校验），导入支持「覆盖 / 续写」两种模式 |
| 统计 | 学习趋势折线图（近 7 天）、掌握状态分布、连续学习天数 |
| 提醒通知 | 本地通知，每日复习提醒（无网络依赖） |

---

## 技术栈

| 层 | 技术 | 版本 |
|----|------|------|
| 框架 | Flutter | 3.44.9（stable） |
| 语言 | Dart | 3.12.2 |
| 状态管理 | flutter_riverpod | ^2.6.1 |
| 路由 | go_router | ^14.8.1 |
| 数据库 | sqlite3 + sqlite3_flutter_libs | ^2.4.6 / ^0.5.28（**raw SQL，非 ORM**） |
| 通知 | flutter_local_notifications | ^18.0.1 |
| 时区 | timezone | ^0.9.4 |
| 文件选择 | file_picker | ^8.3.1 |
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

---

## 目录结构

```
wordmem/
  lib/
    main.dart                        # 入口
    app.dart                         # MaterialApp + 主题 + 路由
    core/
      constants/app_constants.dart   # 常量（版本号、间隔等）
      theme/                         # 主题、颜色
      utils/                         # 字符串、标签工具
    data/
      database/                      # SQLite 连接 + DAO（word/review/stats/settings）
      repositories/                  # word / review / backup / import 仓储
      sources/                       # dict_source（ECDICT）+ synonym_dict_source（词林）
    domain/
      models/                        # word / review_rating / stats / synonym_* / word_option
      services/
        fsrs_service.dart            # 艾宾浩斯遗忘曲线排程（文件名沿用旧名 FSRS）
        synonym_detector.dart        # 近义词多级检测
    features/
      today/                         # 今日页
      library/                       # 词库列表
      review/                        # 复习 + 自选复习 + 近义词挑战
      stats/                         # 统计页
      settings/                      # 设置页
      add_word/                      # 添加单词 / 文本导入
      word_detail/                   # 单词详情
    infra/notification_service.dart  # 本地通知
    shared/
      providers/app_providers.dart   # Riverpod Provider 汇总
      router/app_router.dart         # go_router 路由表
      widgets/                       # 通用组件
  assets/dict/
    ecdict_mini.db                   # ECDICT 词典（只读 SQLite，5.2MB）
    synonym_cilin.json               # 哈工大同义词词林（4.5 万词条）
  scripts/
    make_test_backup.py              # 生成测试数据包
    prepare_dict.py                  # 词典数据准备
  android/                           # Android 工程
docs/                                # 设计文档（PRD / Architecture / UIUX）
```

> ⚠️ `docs/Architecture.md` 是早期设计文档，其中描述的 Drift ORM 与 FSRS 包方案已被实际代码取代（改用 raw sqlite3 + 艾宾浩斯算法），以 `lib/` 下代码为准。

---

## 环境要求与构建

完整环境搭建步骤见 **[ENV_SETUP.md](./ENV_SETUP.md)**。

```bash
cd wordmem
flutter pub get
flutter analyze
flutter build apk --debug          # 调试包
flutter build apk --release         # 发布包
```

---

## 相关文档

- [ENV_SETUP.md](./ENV_SETUP.md) — 环境重建指南（重装系统后必读）
- [AGENTS.md](./AGENTS.md) — AI 编码代理（如 Codex）项目说明
- `docs/PRD.md` — 产品需求文档
- `docs/Architecture.md` — 架构设计（早期版本，部分过时）
- `docs/UIUX.md` — UI/UX 设计
