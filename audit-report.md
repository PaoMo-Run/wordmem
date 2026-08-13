# 方案审计报告 - 离线个人英语词库 App

> 审计人：大湾区靓仔（项目总监）
> 日期：2026-08-12
> 审计范围：产品定义、技术架构、数据设计、用户体验、风险与边界

---

## 一、总体评价

方案完成度高，核心决策合理：FSRS 算法选型正确、离线优先策略清晰、词典双层分离设计是亮点。但有 **3 个阻断级风险** 和 **7 个建议级优化** 需要在进入开发前解决。

| 维度 | 评分 | 判定 |
|------|------|------|
| 产品定义 | 8/10 | 范围清晰，缺导入和空状态 |
| 技术架构 | 6/10 | FSRS 集成路径需明确，FTS5 平台兼容性是坑 |
| 数据设计 | 7/10 | 双层设计好，缺迁移和恢复策略 |
| 用户体验 | 7/10 | UI 结构合理，缺空状态和词形展示 |
| 风险边界 | 5/10 | 缺数据库损坏恢复、事务完整性、隐私验证 |

---

## 二、阻断级风险（必须在 Spec 中解决）

### 阻断-1: FTS5 在 Android 上不可用

**问题**：方案写"SQLite + FTS5 全文搜索"，但 Android 系统自带的 SQLite **默认不包含 FTS5 模块**。iOS 11+ 自带的 SQLite 支持 FTS5，但 Android 不行。直接用 `sqflite` 或系统 SQLite 会报 `no such module: fts5`。

**解决方案**：使用 `sqlite3_flutter_libs` 包替代系统 SQLite。该包为 Android/iOS/macOS/Linux/Windows 捆绑了自带 FTS5 的 SQLite 原生库。配合 Drift 使用时，需在 `build.yaml` 中声明 sqlite 模块启用 fts5 扩展，Drift 代码生成器才能识别 FTS5 语法。

**附加问题**：FTS5 默认分词器不支持中文。搜索中文释义时需要 `sqlite3_simple`（Simple 分词器，支持中文和拼音）或对中文字段退化为 `LIKE '%query%'` 查询。

**建议**：
- 英文单词搜索：FTS5 + `unicode61` 分词器（支持大小写不敏感、变音符号折叠）
- 中文释义/备注搜索：`sqlite3_simple` 或 `LIKE` 降级方案
- 在 Spec 中锁定：`sqlite3_flutter_libs: ^0.5.x` + `drift: ^2.27.x` + `sqlite3_simple: ^1.0.x`

### 阻断-2: FSRS 参数优化路径需明确选择

**问题**：方案要求"基于个人复习历史本地优化"，但存在两条实现路径，复杂度差异巨大：

| 方案 | 包名 | 排程 | 参数优化 | 复杂度 | 依赖 |
|------|------|------|----------|--------|------|
| 纯 Dart | `fsrs` (pub.dev v2.0.1) | 支持 | 不支持 | 低 | 纯 Dart，无 FFI |
| Rust FFI | `fsrs-rs-dart` (GitHub) | 支持 | 支持 | 高 | Rust 工具链 + flutter_rust_bridge |

**纯 Dart 版** 无法做参数优化——只能用默认参数排程，不满足"基于个人复习历史本地优化"的需求。

**Rust FFI 版** 支持完整的 `compute_parameters()` 训练，但需要：
- 安装 Rust 工具链（stable channel）
- 安装 `flutter_rust_bridge_codegen`
- 为 Android (arm64-v8a, armeabi-v7a, x86_64) 和 iOS (arm64, x86_64 simulator) 交叉编译 Rust 代码
- 处理 FFI 初始化时序（`await RustLib.init()` 必须在数据库操作之前完成）

**建议**：方案已选"FSRS 的 Rust 实现"方向正确。但 Spec 必须明确：
1. 锁定 `fsrs-rs-dart` 仓库 + commit 版本
2. 交叉编译构建流程文档化
3. 参数优化触发条件：积累 >= 1000 条复习记录后，在 Isolate 中后台运行
4. 优化结果需做回测验证：新参数的预测准确率必须优于旧参数才启用，否则回滚
5. 优化过程不能阻塞 UI，不能在主 Isolate 执行

### 阻断-3: 数据库事务完整性缺失

**问题**：方案未提及事务策略。FSRS 复习评分时需要同时写入两张表：
- 更新 `cards` 表（卡片状态：memory_state, due, stability, difficulty, reps）
- 插入 `review_logs` 表（复习记录：rating, elapsed_days, state, review_time）

如果两步操作之间发生崩溃（如用户杀进程、电量耗尽），会导致卡片状态和复习记录不一致——卡片状态已更新但复习记录丢失，或反过来。FSRS 参数优化依赖完整的复习记录，数据不一致会导致优化结果偏差。

**建议**：
1. 启用 SQLite WAL 模式：`PRAGMA journal_mode=WAL;` 提高并发读写性能和崩溃安全性
2. 复习评分操作必须包裹在单个事务中：`BEGIN TRANSACTION; UPDATE cards...; INSERT INTO review_logs...; COMMIT;`
3. 设置 `PRAGMA synchronous=NORMAL;`（WAL 模式下的推荐设置，兼顾性能和安全）
4. App 启动时执行 `PRAGMA quick_check;` 检测数据库损坏
5. 数据库损坏时的恢复策略：尝试备份恢复 -> 词典重新加载 -> 提示用户导入备份

---

## 三、建议级优化

### 建议-1: 增加文本导入功能（产品）

当前只有手动输入单词。高频场景：用户在阅读英文文章时遇到生词，希望快速批量导入。

**建议**：在"添加单词"页增加"从文本导入"入口。用户粘贴一段英文文本，App 分词后批量匹配词典，展示候选列表，用户勾选后批量加入词库。MVP 阶段可简化为：粘贴文本 -> 正则分词 -> 词典匹配 -> 批量确认。

### 建议-2: 空状态与首次启动体验（UX）

方案未描述首次启动时的空状态。用户打开 App 看到空白词库，会困惑"怎么开始"。

**建议**：
- 首次启动展示引导卡片：说明 App 核心用法（添加单词 -> 复习 -> 评分）
- 空词库状态：今日页显示"还没有单词，点击添加你的第一个单词"
- 可选：提供"入门词包"（如 CET4 高频 50 词），用户一键导入体验完整流程

### 建议-3: 词典数据选型与体积控制（架构）

方案提到"内置离线词典包"但未指定数据源。

**建议**：使用 ECDICT（https://github.com/skywind3000/ECDICT）
- MIT 许可证，可商用、可再分发
- 77 万词条，含音标、词性、中文释义、英文释义、词形变化（exchange 字段）
- 提供 CSV/SQLite 格式
- 包含词频排名（BNC + 当代语料库），可用于排序和推荐

**体积控制**：
- 完整版 SQLite 约 30MB+，对移动端偏大
- 建议只提取高频 2-3 万词 + 基础字段（word, phonetic, pos, translation, exchange），压缩后约 3-5MB
- 或使用 ECDICT mini 版
- 词典以 assets 资源打包，首次启动时解压到应用文档目录

### 建议-4: 词形匹配（数据）

方案提到"支持英文词形搜索"但未说明实现。

**建议**：利用 ECDICT 的 `exchange` 字段。该字段记录了词形变化规则（如 `p:ran/d:run/i:running/3:runs`）。搜索 "running" 时：
1. 先精确匹配 `running`
2. 若无结果，查 exchange 字段反查原型 `run`
3. 展示原型 `run` 的释义，标注"running 是 run 的现在分词"

### 建议-5: 状态管理与依赖注入（架构）

方案未提及状态管理方案。Flutter 状态管理直接影响代码组织。

**建议**：
- 状态管理：Riverpod（编译时安全、可测试、支持异步）
- 依赖注入：Riverpod Provider 天然支持 DI
- 路由：go_router（声明式路由，支持深链接）
- 本地通知：`flutter_local_notifications` + `timezone` 包

### 建议-6: 备份格式增强（数据）

方案写 `.zip` 内含 SQLite + 版本信息。

**建议增强**：
```
backup.zip
  manifest.json     # App版本、词典版本、备份时间、记录数、校验和
  vocabulary.db     # 个人词库 SQLite 数据库（WAL checkpoint 后的完整副本）
  fsrs_params.json  # FSRS 参数（如果已优化）
```
- `manifest.json` 包含 SHA-256 校验和，导入时先验完整性
- 导出前执行 `PRAGMA wal_checkpoint(TRUNCATE);` 确保 WAL 日志合并到主数据库
- 导入时做版本兼容检查：词典版本不匹配时提示"词典版本不同，部分释义可能不一致"

### 建议-7: 隐私验证机制（风险）

方案强调"不申请网络权限、不嵌入分析 SDK、不发起任何网络请求"，但缺少验证手段。

**建议**：
- Android: `AndroidManifest.xml` 中不声明 `INTERNET` 权限（而不是声明了不用）
- iOS: 不在 `Info.plist` 中添加任何网络使用描述
- 测试阶段：用 Charles Proxy / mitmproxy 做网络抓包，确认 App 运行期间无任何网络请求
- CI 门禁：扫描 `pubspec.yaml` 依赖树，禁止引入已知包含网络请求的包（如 `http`, `dio`, `firebase_*` 等）
- 代码审查：全局搜索 `http://`, `https://`, `HttpClient`, `socket` 等关键词

---

## 四、MVP 范围调整建议

### 建议新增（MVP 内）
| 功能 | 理由 | 优先级 |
|------|------|--------|
| 文本批量导入 | 高频场景，无此功能用户体验断裂 | P0 |
| 数据库损坏检测与提示 | 离线 App 数据是唯一副本，必须保护 | P0 |
| 空状态引导 | 首次体验决定留存 | P1 |
| 词形反查 | 搜索"running"找不到是严重的体验缺陷 | P1 |

### 建议后移（v2.0）
| 功能 | 理由 |
|------|------|
| FSRS 参数本地优化 | 需要 1000+ 复习记录才有意义，MVP 阶段用默认参数即可 |
| 连续学习日历热力图 | 统计页展示周/月趋势已够，日历热力图是锦上添花 |
| 词典包替换功能 | MVP 锁定一套 ECDICT 即可，替换功能等有需求再做 |

### 保持不变
- 四档复习反馈（严格匹配 FSRS Rating: Again/Hard/Good/Easy）
- 双层词典设计（只读内置 + 可写个人）
- 底部导航四页结构
- 手动导出/导入备份
- 本地提醒

---

## 五、技术栈补充建议

| 层 | 方案中的选型 | 补充/修正 |
|----|-------------|----------|
| 框架 | Flutter | 锁定 Flutter >= 3.27.3（fsrs-rs-dart 最低要求） |
| 数据库 | SQLite + FTS5 | 改为：sqlite3_flutter_libs + Drift + FTS5（必须捆绑自定义 SQLite） |
| ORM | Drift | 确认：Drift ^2.27.x，build.yaml 中声明 fts5 扩展 |
| 复习引擎 | FSRS Rust 实现 | 锁定：fsrs-rs-dart (GitHub open-spaced-repetition/fsrs-rs-dart) |
| 中文搜索 | 未提及 | 补充：sqlite3_simple 或 LIKE 降级 |
| 状态管理 | 未提及 | 建议：Riverpod ^2.x |
| 路由 | 未提及 | 建议：go_router ^14.x |
| 本地通知 | 系统本地通知 | 锁定：flutter_local_notifications ^17.x + timezone ^0.9.x |
| 词典数据 | 未指定 | 建议：ECDICT (MIT, 提取高频子集) |
| 备份 | .zip | 增强：manifest.json + SHA-256 校验 + WAL checkpoint |

---

## 六、数据模型建议

### 内置词典表（只读，assets 打包）

```sql
CREATE TABLE dict_words (
  word        TEXT PRIMARY KEY,
  phonetic    TEXT,           -- 音标，如 /wɜːd/
  definition  TEXT,           -- 英文释义
  translation TEXT,           -- 中文释义
  pos         TEXT,           -- 词性，如 n. v. adj.
  exchange    TEXT,           -- 词形变化，如 p:ran/d:run/i:running/3:runs
  collins     INTEGER,        -- 柯林斯星级 1-5
  oxford      INTEGER,        -- 牛津3000标记 0/1
  tag         TEXT,           -- 考试标签 cet4 cet6 toefl ielts gre
  bnc         INTEGER,        -- BNC 词频排名
  frq         INTEGER         -- 当代语料库词频排名
);

-- FTS5 虚拟表（英文全文搜索）
CREATE VIRTUAL TABLE dict_words_fts USING fts5(
  word,
  exchange,
  content='dict_words',
  content_rowid='rowid',
  tokenize='unicode61'
);
```

### 个人词库表（可写，应用文档目录）

```sql
-- PRAGMA journal_mode=WAL;
-- PRAGMA synchronous=NORMAL;

CREATE TABLE user_words (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  word          TEXT NOT NULL,              -- 单词（关联词典）
  sense_id      INTEGER,                    -- 选择的义项编号
  custom_def    TEXT,                       -- 用户自定义释义（覆盖词典）
  note          TEXT,                       -- 个人备注
  tags          TEXT,                       -- 标签（逗号分隔）
  is_favorite   INTEGER DEFAULT 0,          -- 收藏
  created_at    TEXT NOT NULL,              -- 添加时间
  -- FSRS 卡片状态
  card_state    TEXT NOT NULL DEFAULT 'new', -- new/learning/review/relearning
  stability     REAL,                       -- FSRS 稳定性
  difficulty    REAL,                       -- FSRS 难度
  reps          INTEGER DEFAULT 0,          -- 复习次数
  lapses        INTEGER DEFAULT 0,          -- 遗忘次数
  due           TEXT NOT NULL,              -- 下次到期时间
  last_review   TEXT                        -- 上次复习时间
);

CREATE TABLE review_logs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_word_id  INTEGER NOT NULL,           -- 关联 user_words
  rating        INTEGER NOT NULL,            -- 1=Again 2=Hard 3=Good 4=Easy
  state         TEXT NOT NULL,              -- 评分时的卡片状态
  elapsed_days  REAL,                       -- 距上次复习的天数
  reviewed_at   TEXT NOT NULL,              -- 复习时间
  FOREIGN KEY (user_word_id) REFERENCES user_words(id)
);

-- 索引
CREATE INDEX idx_user_words_due ON user_words(due);
CREATE INDEX idx_user_words_tags ON user_words(tags);
CREATE INDEX idx_user_words_created ON user_words(created_at);
CREATE INDEX idx_review_logs_word ON review_logs(user_word_id);

-- FTS5（中文释义/备注搜索）
CREATE VIRTUAL TABLE user_words_fts USING fts5(
  word,
  custom_def,
  note,
  tags,
  content='user_words',
  content_rowid='id'
);
```

### FSRS 参数表

```sql
CREATE TABLE fsrs_params (
  id              INTEGER PRIMARY KEY,
  parameters      TEXT NOT NULL,      -- JSON: 21个权重
  desired_retention REAL DEFAULT 0.9,  -- 目标记忆率
  optimized_at    TEXT,                -- 上次优化时间
  review_count    INTEGER DEFAULT 0,   -- 优化时的复习记录数
  is_active       INTEGER DEFAULT 0    -- 是否启用（0=默认参数, 1=已优化）
);
```

---

## 七、复习评分事务伪代码

```dart
Future<void> reviewCard(int userWordId, FsrsRating rating) async {
  await database.transaction(() async {
    // 1. 读取当前卡片状态
    final card = await database.getUserWordById(userWordId);
    
    // 2. FSRS 计算新状态
    final newState = scheduler.reviewCard(card.toFsrsCard(), rating);
    
    // 3. 更新卡片状态
    await database.updateUserWord(userWordId, newState.card.toMap());
    
    // 4. 插入复习记录
    await database.insertReviewLog(ReviewLog(
      userWordId: userWordId,
      rating: rating.index,
      state: card.cardState,
      elapsedDays: calculateElapsedDays(card.lastReview),
      reviewedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  });
}
```

---

## 八、下一步行动

1. **解决 3 个阻断级风险**：确认 FTS5 方案、锁定 FSRS 集成路径、定义事务策略
2. **调整 MVP 范围**：新增文本导入、空状态、损坏检测；后移 FSRS 优化和日历热力图
3. **确认技术栈版本**：Flutter >= 3.27.3, Drift ^2.27.x, sqlite3_flutter_libs, fsrs-rs-dart
4. **选择词典数据源**：确认 ECDICT，决定提取策略（全量 vs 高频子集）
5. **以上确认后**：进入 Phase 1 正式调研，产出 PRD + 架构文档 + UIUX 文档三件套

---

> 本审计基于方案文档 + FSRS/Flutter/SQLite 技术调研。如对任何风险判定有异议，可在进入 Phase 1 前讨论调整。
