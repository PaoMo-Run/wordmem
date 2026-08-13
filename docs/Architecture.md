# 架构设计文档 - Lexicon 离线英语词库

> 版本: 1.0  
> 日期: 2026-08-12  
> 平台: Android only (minSdk 26)  
> 关联文档: PRD.md, UIUX.md

---

## 1. 系统架构总览

### 1.1 架构分层

```
┌─────────────────────────────────────────────────┐
│                  Presentation                    │
│  (UI Widgets, Screens, Riverpod Consumers)       │
├─────────────────────────────────────────────────┤
│                  Application                     │
│  (Riverpod Providers, Use Cases, View Models)    │
├─────────────────────────────────────────────────┤
│                    Domain                        │
│  (Models, Repository Interfaces, Services)       │
├─────────────────────────────────────────────────┤
│                    Data                          │
│  (Drift Database, DAOs, Repositories, Sources)   │
├─────────────────────────────────────────────────┤
│               Infrastructure                     │
│  (SQLite, FSRS Engine, Notifications, FS)       │
└─────────────────────────────────────────────────┘
```

### 1.2 数据流

```
用户操作 -> UI Widget -> Riverpod Provider -> Repository -> DAO -> Drift -> SQLite
                                    |               |
                                    v               v
                              FSRS Service    Dict Source (只读)
                              (排程计算)      (词典查询)
```

### 1.3 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 架构模式 | Feature-first + Clean Architecture | 按功能模块组织代码，降低耦合 |
| FSRS 实现 | 纯 Dart `fsrs` 包 (MVP) | 免 Rust 工具链，个人项目优先简化构建 |
| 中文搜索 | LIKE 模糊查询 | 个人词库数据量小（千级），LIKE 性能足够 |
| 词典存储 | SQLite (只读) 打包在 assets | 首次启动复制到文档目录，支持 FTS5 |
| 状态管理 | Riverpod | 编译时安全、可测试、原生支持异步 |
| 路由 | go_router | 声明式路由，支持类型安全导航 |

---

## 2. 技术栈选型与版本锁定

### 2.1 技术栈一览

| 层 | 技术 | 版本 | 说明 |
|----|------|------|------|
| 框架 | Flutter | >= 3.27.3 | stable channel |
| 语言 | Dart | >= 3.6.0 | 随 Flutter 版本 |
| 数据库 | SQLite | (bundled) | 通过 sqlite3_flutter_libs 捆绑，含 FTS5 |
| ORM | Drift | ^2.27.0 | 类型安全，支持 FTS5 代码生成 |
| SQLite 绑定 | sqlite3_flutter_libs | ^0.5.28 | 捆绑自带 FTS5 的 SQLite 原生库 |
| FSRS 引擎 | fsrs (pub.dev) | ^2.0.1 | 纯 Dart FSRS-5 实现，支持排程 |
| 状态管理 | flutter_riverpod | ^2.6.1 | Riverpod 2.x |
| 路由 | go_router | ^14.8.1 | 声明式路由 |
| 通知 | flutter_local_notifications | ^17.2.4 | Android 本地通知 |
| 时区 | timezone | ^0.9.4 | 通知调度时区支持 |
| 文件选择 | file_picker | ^8.3.1 | 导入/导出文件选择 |
| 路径 | path_provider | ^2.1.5 | 应用文档目录访问 |
| 压缩 | archive | ^3.6.1 | 备份 zip 打包/解压 |
| 加密 | crypto | ^3.0.6 | SHA-256 校验和 |
| 共享偏好 | shared_preferences | ^2.3.5 | 轻量配置存储（引导标记等） |

### 2.2 Android 构建配置

```gradle
// android/app/build.gradle
android {
    compileSdk 34

    defaultConfig {
        minSdk 26
        targetSdk 34
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
        }
    }
}
```

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<!-- 不声明 INTERNET 权限 -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.VIBRATE" />
    
    <application
        android:label="Lexicon"
        android:icon="@mipmap/ic_launcher"
        android:requestLegacyExternalStorage="false">
        <activity android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|screenSize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        
        <!-- 通知接收器 -->
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

### 2.3 pubspec.yaml 依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  # Database
  drift: ^2.27.0
  sqlite3_flutter_libs: ^0.5.28
  # FSRS
  fsrs: ^2.0.1
  # State & Routing
  flutter_riverpod: ^2.6.1
  go_router: ^14.8.1
  # Notifications
  flutter_local_notifications: ^17.2.4
  timezone: ^0.9.4
  # Utils
  file_picker: ^8.3.1
  path_provider: ^2.1.5
  archive: ^3.6.1
  crypto: ^3.0.6
  shared_preferences: ^2.3.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.27.0
  build_runner: ^2.4.14
  flutter_lints: ^4.0.0
```

---

## 3. 项目结构

```
lib/
  main.dart                         # 入口：初始化 DB、FSRS、通知
  app.dart                          # MaterialApp 配置、路由、主题
  
  core/
    constants/
      app_constants.dart            # 常量：默认目标记忆率、短间隔等
      db_constants.dart             # 数据库常量：PRAGMA、版本号
    theme/
      app_theme.dart                # 亮色/暗色主题定义
      colors.dart                   # 颜色常量
      typography.dart               # 字体样式
    utils/
      date_utils.dart               # 日期格式化/计算
      string_utils.dart             # 分词、文本处理
    extensions/
      context_extensions.dart       # BuildContext 扩展
  
  data/
    database/
      app_database.dart             # Drift 数据库定义（个人词库）
      app_database.g.dart           # 生成文件
      tables/
        user_words.dart             # user_words 表定义
        review_logs.dart            # review_logs 表定义
        fsrs_params.dart            # fsrs_params 表定义
      daos/
        word_dao.dart               # 单词 CRUD
        review_dao.dart             # 复习记录 + 卡片状态更新
        stats_dao.dart              # 统计查询
        fsrs_params_dao.dart        # FSRS 参数存取
    sources/
      dict_database.dart            # 只读词典数据库连接
      dict_source.dart              # 词典查询接口
    repositories/
      word_repository.dart          # 单词管理（词典匹配 + 个人词库写入）
      review_repository.dart        # 复习流程（FSRS 排程 + 事务写入）
      stats_repository.dart         # 统计数据聚合
      backup_repository.dart        # 导入导出
      import_repository.dart        # 文本批量导入
  
  domain/
    models/
      word.dart                     # 单词领域模型
      review_card.dart              # 复习卡片模型
      review_rating.dart            # 评分枚举
      word_status.dart              # 掌握状态枚举
      stats.dart                    # 统计数据模型
      backup_info.dart              # 备份元信息
    services/
      fsrs_service.dart             # FSRS 排程封装
      search_service.dart           # 搜索逻辑（FTS5 + LIKE）
      dict_match_service.dart       # 词典匹配 + 词形反查
  
  features/
    today/
      presentation/
        today_page.dart
        widgets/
          today_summary_card.dart
          today_action_buttons.dart
      providers/
        today_providers.dart
    library/
      presentation/
        library_page.dart
        widgets/
          word_list_tile.dart
          filter_bar.dart
          search_bar.dart
      providers/
        library_providers.dart
    review/
      presentation/
        review_page.dart
        widgets/
          review_card.dart
          rating_buttons.dart
          review_summary.dart
      providers/
        review_providers.dart
    stats/
      presentation/
        stats_page.dart
        widgets/
          trend_chart.dart
          status_pie_chart.dart
      providers/
        stats_providers.dart
    settings/
      presentation/
        settings_page.dart
        widgets/
          retention_slider.dart
          reminder_time_picker.dart
          backup_section.dart
      providers/
        settings_providers.dart
    add_word/
      presentation/
        add_word_page.dart
        text_import_page.dart
      providers/
        add_word_providers.dart
    word_detail/
      presentation/
        word_detail_page.dart
      providers/
        word_detail_providers.dart
  
  shared/
    widgets/
      empty_state.dart
      loading_indicator.dart
      error_widget.dart
    providers/
      database_provider.dart        # 全局 DB Provider
      dict_provider.dart            # 词典 Provider
      fsrs_provider.dart            # FSRS 引擎 Provider

assets/
  dict/
    ecdict_mini.db                  # ECDICT 高频子集 SQLite（只读）
```

---

## 4. 数据架构

### 4.1 双层数据库设计

```
┌─────────────────────────────────────┐
│        内置词典库 (只读)              │
│  ecdict_mini.db                     │
│  打包在 assets/，首次启动复制到       │
│  应用文档目录                        │
│  ┌─────────────────────────────┐    │
│  │ dict_words (FTS5 虚拟表)     │    │
│  │ word, phonetic, pos,         │    │
│  │ translation, exchange,       │    │
│  │ collins, tag, bnc, frq       │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
              │ 只读查询
              ▼
┌─────────────────────────────────────┐
│        个人词库 (可写)                │
│  vocabulary.db                      │
│  应用文档目录，WAL 模式              │
│  ┌─────────────────────────────┐    │
│  │ user_words                   │    │
│  │ user_words_fts (FTS5)        │    │
│  │ review_logs                  │    │
│  │ fsrs_params                   │    │
│  │ app_settings                  │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### 4.2 内置词典表 DDL

```sql
-- ecdict_mini.db (只读，assets 打包)

CREATE TABLE dict_words (
  word        TEXT PRIMARY KEY,
  phonetic    TEXT,           -- 音标，如 /həˈloʊ/
  pos         TEXT,           -- 词性，如 "n. v. adj."
  translation TEXT,           -- 中文释义
  definition  TEXT,           -- 英文释义（可选）
  exchange    TEXT,           -- 词形变化，如 "p:ran/d:run/i:running/3:runs"
  collins     INTEGER DEFAULT 0,  -- 柯林斯星级 0-5
  oxford      INTEGER DEFAULT 0,  -- 牛津3000词标记 0/1
  tag         TEXT,           -- 考试标签，如 "cet4 cet6 toefl ielts gre"
  bnc         INTEGER,        -- BNC 语料库词频排名
  frq         INTEGER         -- 当代语料库词频排名
);

-- FTS5 虚拟表：英文单词全文搜索
CREATE VIRTUAL TABLE dict_words_fts USING fts5(
  word,
  exchange,
  content='dict_words',
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
);

-- 词形反查索引
CREATE INDEX idx_dict_exchange ON dict_words(exchange);
-- 词频排序索引
CREATE INDEX idx_dict_bnc ON dict_words(bnc);
```

### 4.3 个人词库表 DDL

```sql
-- vocabulary.db (可写，WAL 模式)
-- 启动时执行：
-- PRAGMA journal_mode=WAL;
-- PRAGMA synchronous=NORMAL;
-- PRAGMA foreign_keys=ON;

-- 个人单词表
CREATE TABLE user_words (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  word            TEXT NOT NULL,                  -- 单词（关联词典）
  sense_id        INTEGER DEFAULT 0,              -- 选择的义项编号
  custom_def      TEXT,                           -- 用户自定义释义（覆盖词典）
  note            TEXT DEFAULT '',                -- 个人备注
  tags            TEXT DEFAULT '',                -- 标签（逗号分隔）
  is_favorite     INTEGER NOT NULL DEFAULT 0,     -- 收藏 0/1
  
  -- 元数据
  created_at      TEXT NOT NULL,                  -- 添加时间 (ISO8601 UTC)
  updated_at      TEXT NOT NULL,                  -- 最后修改时间
  
  -- FSRS 卡片状态
  card_state      TEXT NOT NULL DEFAULT 'new',    -- new/learning/review/relearning
  stability       REAL DEFAULT 0,                 -- FSRS 稳定性
  difficulty      REAL DEFAULT 0,                 -- FSRS 难度
  reps            INTEGER NOT NULL DEFAULT 0,     -- 总复习次数
  lapses          INTEGER NOT NULL DEFAULT 0,     -- 遗忘次数
  due             TEXT NOT NULL,                  -- 下次到期时间 (ISO8601 UTC)
  last_review     TEXT,                           -- 上次复习时间
  elapsed_days    REAL DEFAULT 0,                 -- 距上次复习天数（评分时计算）
  scheduled_days  REAL DEFAULT 0                  -- 计划间隔天数
);

-- 复习记录表
CREATE TABLE review_logs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  user_word_id    INTEGER NOT NULL,
  rating          INTEGER NOT NULL,               -- 1=Again 2=Hard 3=Good 4=Easy
  state           TEXT NOT NULL,                  -- 评分时卡片状态
  elapsed_days    REAL,                           -- 距上次复习天数
  scheduled_days  REAL,                           -- 当时计划的间隔
  reviewed_at     TEXT NOT NULL,                  -- 复习时间 (ISO8601 UTC)
  FOREIGN KEY (user_word_id) REFERENCES user_words(id) ON DELETE CASCADE
);

-- FSRS 参数表
CREATE TABLE fsrs_params (
  id                INTEGER PRIMARY KEY DEFAULT 1,
  parameters        TEXT NOT NULL,                -- JSON: FSRS-5 的 19 个权重
  desired_retention REAL NOT NULL DEFAULT 0.9,     -- 目标记忆率
  optimized_at      TEXT,                          -- 上次优化时间
  review_count      INTEGER DEFAULT 0,             -- 优化时的复习记录数
  is_active         INTEGER NOT NULL DEFAULT 0,    -- 0=默认参数 1=已优化
  updated_at        TEXT NOT NULL
);

-- 应用设置表（键值对存储）
CREATE TABLE app_settings (
  key             TEXT PRIMARY KEY,
  value           TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

-- 索引
CREATE INDEX idx_user_words_due ON user_words(due);
CREATE INDEX idx_user_words_state ON user_words(card_state);
CREATE INDEX idx_user_words_created ON user_words(created_at);
CREATE INDEX idx_user_words_favorite ON user_words(is_favorite);
CREATE INDEX idx_user_words_tags ON user_words(tags);
CREATE INDEX idx_review_logs_word ON review_logs(user_word_id);
CREATE INDEX idx_review_logs_time ON review_logs(reviewed_at);

-- FTS5 虚拟表：个人词库全文搜索
CREATE VIRTUAL TABLE user_words_fts USING fts5(
  word,
  custom_def,
  note,
  tags,
  content='user_words',
  content_rowid='id',
  tokenize='unicode61 remove_diacritics 2'
);

-- FTS5 触发器：自动同步
CREATE TRIGGER user_words_ai AFTER INSERT ON user_words BEGIN
  INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
  VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
END;
CREATE TRIGGER user_words_ad AFTER DELETE ON user_words BEGIN
  INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
  VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
END;
CREATE TRIGGER user_words_au AFTER UPDATE ON user_words BEGIN
  INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
  VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
  INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
  VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
END;
```

### 4.4 Drift 表定义示例

```dart
// data/database/tables/user_words.dart
import 'package:drift/drift.dart';

class UserWords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get word => text().withLength(min: 1)();
  IntColumn get senseId => integer().withDefault(const Constant(0))();
  TextColumn get customDef => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get cardState => text().withDefault(const Constant('new'))();
  RealColumn get stability => real().withDefault(const Constant(0))();
  RealColumn get difficulty => real().withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  TextColumn get due => text()();
  TextColumn get lastReview => text().nullable()();
  RealColumn get elapsedDays => real().withDefault(const Constant(0))();
  RealColumn get scheduledDays => real().withDefault(const Constant(0))();
}
```

---

## 5. FSRS 集成方案

### 5.1 引擎初始化

```dart
// domain/services/fsrs_service.dart
import 'package:fsrs/fsrs.dart';

class FsrsService {
  late final FSRS _scheduler;
  double _desiredRetention = 0.9;

  /// 初始化 FSRS 引擎
  /// MVP 使用默认参数；v2 从数据库加载优化后的参数
  Future<void> init({double? desiredRetention, List<double>? parameters}) async {
    _desiredRetention = desiredRetention ?? 0.9;
    _scheduler = FSRS(
      parameters: parameters ?? defaultParameters, // FSRS-5 默认 19 权重
      desiredRetention: _desiredRetention,
    );
  }

  /// 获取默认参数
  static List<double> get defaultParameters => [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949,
    0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
    1.01925, 1.9395, 0.11, 0.29605, 2.2698,
    0.2315, 2.9898, 0.51655, 0.6621,
  ];
}
```

### 5.2 排程流程

```dart
/// 为新词创建首次复习计划
FsrsCard scheduleNewCard() {
  final card = FsrsCard(); // 新卡片，state = new
  final now = DateTime.now().toUtc();
  final scheduled = _scheduler.repeat(card, now);
  // scheduled 返回 4 个结果，对应 Rating 1-4
  // 新词首次展示时，所有 rating 对应的 due 都是 10 分钟后（FSRS 新词行为）
  return card;
}

/// 根据评分更新卡片状态
FsrsCard reviewCard(FsrsCard card, int rating, DateTime now) {
  final scheduled = _scheduler.repeat(card, now);
  // rating: 1=Again, 2=Hard, 3=Good, 4=Easy
  return scheduled[rating - 1].card;
}

/// 计算预计记忆率（用于统计）
double predictRetention(FsrsCard card, DateTime now) {
  final elapsed = now.difference(card.lastReview ?? now).inSeconds / 86400.0;
  return _scheduler.predictRetention(card, elapsed);
}
```

### 5.3 评分事务

```dart
// data/repositories/review_repository.dart
Future<void> submitReview(int userWordId, int rating) async {
  await _database.transaction(() async {
    // 1. 读取当前卡片状态
    final word = await _wordDao.getWordById(userWordId);
    if (word == null) throw Exception('Word not found');

    // 2. 构建 FSRS 卡片
    final card = _fsrsService.fromDbModel(word);

    // 3. 计算新状态
    final now = DateTime.now().toUtc();
    final newCard = _fsrsService.reviewCard(card, rating, now);

    // 4. 更新 user_words
    await _wordDao.updateCardState(
      userWordId,
      cardState: newCard.state.name,
      stability: newCard.stability,
      difficulty: newCard.difficulty,
      reps: newCard.reps,
      lapses: newCard.lapses,
      due: newCard.due.toIso8601String(),
      lastReview: now.toIso8601String(),
      elapsedDays: newCard.elapsedDays,
      scheduledDays: newCard.scheduledDays,
    );

    // 5. 插入复习记录
    await _reviewDao.insertReviewLog(
      userWordId: userWordId,
      rating: rating,
      state: card.state.name,
      elapsedDays: newCard.elapsedDays,
      scheduledDays: newCard.scheduledDays,
      reviewedAt: now.toIso8601String(),
    );
  });
}
```

### 5.4 v2 参数优化迁移路径

```
MVP (当前)                          v2 (迁移后)
┌──────────────────┐               ┌──────────────────────┐
│ fsrs (纯 Dart)    │     迁移      │ fsrs-rs-dart (Rust)   │
│ - repeat()        │ ──────────>  │ - repeat()             │
│ - predictRetention│              │ - compute_parameters() │
│ - 默认 19 参数     │              │ - 参数优化 + 回测      │
│ - 无优化           │              │ - Isolate 后台执行     │
└──────────────────┘               └──────────────────────┘
迁移条件：
1. review_logs 记录数 >= 1000
2. 仅 Android 3 ABI 交叉编译（无 iOS）
3. 优化结果回测优于默认参数才启用
```

---

## 6. 搜索架构

### 6.1 双路搜索策略

```
用户输入查询
     │
     ├─ 英文输入？──> FTS5 全文搜索（user_words_fts + dict_words_fts）
     │                 tokenize: unicode61
     │                 支持：前缀匹配、大小写不敏感、变音符号折叠
     │
     └─ 中文输入？──> LIKE 模糊查询
                       WHERE custom_def LIKE '%query%'
                          OR note LIKE '%query%'
                          OR tags LIKE '%query%'
```

### 6.2 搜索实现

```dart
// domain/services/search_service.dart
class SearchService {
  final AppDatabase _db;

  /// 搜索个人词库
  Future<List<UserWord>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // 判断是否包含中文字符
    final isChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed);

    if (isChinese) {
      // 中文：LIKE 模糊查询
      return _searchByChinese(trimmed);
    } else {
      // 英文：FTS5 全文搜索
      return _searchByEnglish(trimmed);
    }
  }

  Future<List<UserWord>> _searchByEnglish(String query) async {
    // FTS5 前缀匹配：输入 "run" 匹配 "run", "running", "runner"
    final ftsQuery = '$query*';
    return _db.customSelect(
      'SELECT uw.* FROM user_words_fts '
      'JOIN user_words uw ON uw.id = user_words_fts.rowid '
      'WHERE user_words_fts MATCH ? '
      'ORDER BY rank LIMIT 100',
      variables: [Variable.withString(ftsQuery)],
    ).map((row) => UserWord.fromData(row.data)).get();
  }

  Future<List<UserWord>> _searchByChinese(String query) async {
    final pattern = '%$query%';
    return _db.customSelect(
      'SELECT * FROM user_words '
      'WHERE custom_def LIKE ? OR note LIKE ? OR tags LIKE ? '
      'ORDER BY created_at DESC LIMIT 100',
      variables: [
        Variable.withString(pattern),
        Variable.withString(pattern),
        Variable.withString(pattern),
      ],
    ).map((row) => UserWord.fromData(row.data)).get();
  }
}
```

### 6.3 词典查询 + 词形反查

```dart
// domain/services/dict_match_service.dart
class DictMatchService {
  final DictDatabase _dictDb;

  /// 精确查询单词
  Future<DictWord?> lookup(String word) async {
    final result = await _dictDb.select(_dictDb.dictWords)
      ..where((t) => t.word.lower().equals(word.toLowerCase()))
      ..limit(1);
    return result.getSingleOrNull();
  }

  /// 词形反查
  /// 输入 "running" -> 返回 "run"（通过 exchange 字段反查）
  Future<DictWord?> lookupWithExchange(String word) async {
    // 1. 先精确匹配
    var result = await lookup(word);
    if (result != null) return result;

    // 2. 通过 exchange 字段反查
    // exchange 格式: "p:ran/d:run/i:running/3:runs"
    // 查找 exchange 中包含 "i:running" 或 "p:running" 等的记录
    final pattern = '%$word%';
    final exchangeResult = await _dictDb.customSelect(
      'SELECT * FROM dict_words WHERE exchange LIKE ? LIMIT 1',
      variables: [Variable.withString(pattern)],
    ).get();

    if (exchangeResult.isNotEmpty) {
      return DictWord.fromData(exchangeResult.first.data);
    }

    return null;
  }

  /// 解析词形关系
  String? parseExchangeRelation(String exchange, String input) {
    // 解析 "p:ran/d:run/i:running/3:runs" 格式
    // 返回 "running 是 run 的现在分词" 类似信息
    final parts = exchange.split('/');
    for (final part in parts) {
      final segments = part.split(':');
      if (segments.length == 2 && segments[1].toLowerCase() == input.toLowerCase()) {
        final type = segments[0];
        final typeMap = {
          'p': '过去式', 'd': '过去式', 'i': '现在分词',
          '3': '第三人称单数', 's': '复数', 'r': '比较级',
          't': '最高级', 'f': '第三人称单数',
        };
        return typeMap[type] ?? type;
      }
    }
    return null;
  }
}
```

---

## 7. 备份与恢复

### 7.1 备份文件结构

```
backup.zip
  ├── manifest.json          # 元信息 + 校验和
  ├── vocabulary.db          # 个人词库 SQLite（WAL checkpoint 后的完整副本）
  └── fsrs_params.json       # FSRS 参数快照（冗余备份）
```

### 7.2 manifest.json 格式

```json
{
  "version": "1.0",
  "app_version": "1.0.0",
  "dict_version": "ecdict_mini_v1",
  "dict_word_count": 30000,
  "backup_time": "2026-08-12T14:30:00Z",
  "user_word_count": 1234,
  "review_log_count": 5678,
  "streak_days": 15,
  "files": {
    "vocabulary.db": {
      "sha256": "a1b2c3d4e5f6...",
      "size": 456789
    },
    "fsrs_params.json": {
      "sha256": "f6e5d4c3b2a1...",
      "size": 234
    }
  }
}
```

### 7.3 导出流程

```dart
// data/repositories/backup_repository.dart
Future<String> exportBackup() async {
  final dbPath = await _getDbPath();
  final now = DateTime.now().toUtc();

  // 1. WAL checkpoint：将 WAL 日志合并到主数据库
  await _database.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');

  // 2. 读取数据库文件字节
  final dbFile = File(dbPath);
  final dbBytes = await dbFile.readAsBytes();

  // 3. 读取 FSRS 参数
  final params = await _fsrsParamsDao.getActiveParams();
  final paramsJson = jsonEncode(params);

  // 4. 计算校验和
  final dbSha256 = sha256.convert(dbBytes).toString();
  final paramsSha256 = sha256.convert(utf8.encode(paramsJson)).toString();

  // 5. 统计信息
  final wordCount = await _wordDao.count();
  final reviewCount = await _reviewDao.count();
  final streak = await _statsDao.getCurrentStreak();

  // 6. 生成 manifest
  final manifest = {
    'version': '1.0',
    'app_version': appVersion,
    'dict_version': 'ecdict_mini_v1',
    'dict_word_count': 30000,
    'backup_time': now.toIso8601String(),
    'user_word_count': wordCount,
    'review_log_count': reviewCount,
    'streak_days': streak,
    'files': {
      'vocabulary.db': {'sha256': dbSha256, 'size': dbBytes.length},
      'fsrs_params.json': {'sha256': paramsSha256, 'size': paramsJson.length},
    },
  };

  // 7. 打包 zip
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson))
    ..addFile(ArchiveFile('vocabulary.db', dbBytes.length, dbBytes))
    ..addFile(ArchiveFile('fsrs_params.json', paramsJson.length, utf8.encode(paramsJson)));

  final zipBytes = ZipEncoder().encode(archive)!;

  // 8. 保存到用户选择的路径
  final outputPath = await _saveToUserPath(zipBytes, now);
  return outputPath;
}
```

### 7.4 导入流程

```dart
Future<ImportResult> importBackup(String zipPath) async {
  // 1. 解压 zip
  final zipBytes = await File(zipPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes);

  final manifestFile = archive.findFile('manifest.json');
  final dbFile = archive.findFile('vocabulary.db');

  // 2. 解析 manifest
  final manifest = jsonDecode(utf8.decode(manifestFile!.content));

  // 3. 校验文件完整性
  final dbBytes = dbFile!.content as List<int>;
  final dbSha256 = sha256.convert(dbBytes).toString();
  if (dbSha256 != manifest['files']['vocabulary.db']['sha256']) {
    return ImportResult(success: false, error: '数据库文件校验失败');
  }

  // 4. 版本兼容检查
  final dictVersion = manifest['dict_version'] as String;
  if (dictVersion != currentDictVersion) {
    // 提示但不阻止
    _showVersionWarning(dictVersion);
  }

  // 5. 关闭当前数据库连接
  await _database.close();

  // 6. 备份当前数据库（以防导入失败）
  final currentDbPath = await _getDbPath();
  final backupPath = '$currentDbPath.bak';
  await File(currentDbPath).copy(backupPath);

  // 7. 写入新数据库
  await File(currentDbPath).writeAsBytes(dbBytes);

  // 8. 重新打开数据库并验证
  try {
    await _database.verifyIntegrity();
    await File(backupPath).delete(); // 成功，删除临时备份
  } catch (e) {
    // 恢复
    await File(backupPath).copy(currentDbPath);
    return ImportResult(success: false, error: '导入的数据库文件已损坏');
  }

  return ImportResult(
    success: true,
    wordCount: manifest['user_word_count'],
    reviewCount: manifest['review_log_count'],
  );
}
```

---

## 8. 本地通知

### 8.1 通知架构

```dart
// shared/providers/notification_provider.dart
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Android 初始化
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 创建通知渠道
    await _createChannel();
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      'lexicon_reminder',
      '学习提醒',
      description: '每日复习提醒通知',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 调度每日提醒
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required int pendingCount,
  }) async {
    await _plugin.zonedSchedule(
      0, // notification id
      pendingCount > 0 ? '该复习单词了' : '今天还没学习',
      pendingCount > 0
          ? '你有 $pendingCount 个单词待复习'
          : '来添加新单词或复习已学内容吧',
      _nextInstanceOfTime(hour, minute),
      const AndroidNotificationDetails(
        'lexicon_reminder',
        '学习提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// 通知点击 -> 打开 App 到今日页面
  void _onNotificationTap(NotificationResponse response) {
    // 通过 go_router 导航到今日页面
    _router.go('/today');
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
```

---

## 9. 事务与数据安全

### 9.1 数据库初始化

```dart
// data/database/app_database.dart
@DriftDatabase(tables: [UserWords, ReviewLogs, FsrsParams, AppSettings], daos: [...])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _initPragmas();
      await _initDefaultData();
    },
    onOpen: (_) async {
      await _initPragmas();
      await _verifyIntegrity();
    },
  );

  Future<void> _initPragmas() async {
    await customStatement('PRAGMA journal_mode=WAL;');
    await customStatement('PRAGMA synchronous=NORMAL;');
    await customStatement('PRAGMA foreign_keys=ON;');
    await customStatement('PRAGMA temp_store=MEMORY;');
  }

  Future<void> _verifyIntegrity() async {
    final result = await customSelect('PRAGMA quick_check;').getSingle();
    final ok = result.data['quick_check'] == 'ok';
    if (!ok) {
      // 触发恢复流程
      throw DatabaseCorruptedException();
    }
  }

  Future<void> _initDefaultData() async {
    // 插入默认 FSRS 参数
    await into(fsrsParams).insert(FsrsParamsCompanion.insert(
      parameters: jsonEncode(FsrsService.defaultParameters),
      desiredRetention: const Constant(0.9),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }
}
```

### 9.2 数据库损坏恢复策略

```
App 启动
  │
  ├─ PRAGMA quick_check == 'ok'?
  │   ├─ YES ──> 正常启动
  │   └─ NO ───> 进入恢复流程
  │                │
  │                ├─ 有自动备份? (v2: 每次导出时记录路径)
  │                │   ├─ YES ──> 尝试恢复 ──> 验证 ──> 成功? 启动 : 继续向下
  │                │   └─ NO ───> 继续向下
  │                │
  │                ├─ 提示用户："数据库损坏，请选择备份文件恢复"
  │                │   ├─ 用户选择文件 ──> 导入流程
  │                │   └─ 用户取消 ────> 重置个人词库（保留词典）
  │                │
  │                └─ 重置后展示："词库已重置，词典仍可用"
```

---

## 10. 隐私保障机制

### 10.1 权限声明

仅声明以下权限，不含 INTERNET：

| 权限 | 用途 |
|------|------|
| SCHEDULE_EXACT_ALARM | 精确闹钟（复习提醒） |
| POST_NOTIFICATIONS | 发送通知（Android 13+） |
| RECEIVE_BOOT_COMPLETED | 开机后恢复通知调度 |
| VIBRATE | 通知振动 |

### 10.2 依赖审查规则

```
# CI 检查脚本 (伪代码)
禁止依赖列表:
  - http
  - dio
  - socket_io_client
  - firebase_*
  - cloud_firestore
  - cloud_functions
  - google-analytics
  - sentry
  - firebase_analytics
  - amplitude

检查方式:
  1. 解析 pubspec.lock
  2. 遍历所有依赖（含传递依赖）
  3. 匹配禁止列表
  4. 发现匹配则 CI 失败
```

### 10.3 验证清单

| 验证项 | 方法 | 频率 |
|--------|------|------|
| 无网络请求 | mitmproxy 抓包，运行全功能流程 | 每个版本发布前 |
| 无网络权限 | 检查 AndroidManifest.xml 不含 INTERNET | CI 自动检查 |
| 无分析 SDK | 依赖树扫描 | CI 自动检查 |
| 代码中无网络调用 | 全局搜索 `http://`, `https://`, `HttpClient`, `Socket`, `WebSocket` | CI 自动检查 |
| 数据仅本地 | 检查所有文件操作路径在应用私有目录 | 代码审查 |

---

## 11. 构建与部署

### 11.1 构建命令

```bash
# 生成 Drift 代码
dart run build_runner build --delete-conflicting-outputs

# Debug 构建
flutter build apk --debug

# Release 构建（含所有 ABI）
flutter build apk --release --split-per-abi

# 或打包为单个 APK
flutter build apk --release
```

### 11.2 词典数据准备

```bash
# 从 ECDICT 源数据提取高频子集
# 前置条件：下载 ECDICT 完整 CSV

python3 scripts/prepare_dict.py \
  --input ecdict.csv \
  --output assets/dict/ecdict_mini.db \
  --limit 30000 \
  --sort-by bnc

# prepare_dict.py 逻辑：
# 1. 读取 CSV
# 2. 按 BNC 词频排序
# 3. 取前 30000 条
# 4. 提取字段：word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq
# 5. 创建 SQLite 数据库 + FTS5 虚拟表 + 索引
# 6. 输出到 assets/dict/ecdict_mini.db
```

### 11.3 首次启动流程

```
App 首次启动
  │
  ├─ 检查应用文档目录是否有 ecdict_mini.db
  │   ├─ 无 ──> 从 assets 复制到文档目录
  │   │         （显示加载进度）
  │   └─ 有 ──> 跳过
  │
  ├─ 打开词典数据库（只读）
  ├─ 创建/打开个人词库数据库
  │   ├─ 新建 ──> 执行 DDL + 初始化默认数据
  │   └─ 已有 ──> PRAGMA 设置 + 完整性检查
  │
  ├─ 初始化 FSRS 引擎
  ├─ 初始化通知服务
  ├─ 恢复通知调度
  │
  └─ 进入今日页面
```

---

## 12. 性能优化策略

| 场景 | 优化策略 |
|------|----------|
| 词库列表加载 | 分页加载，每页 50 条；使用 Drift 的 `watch()` 流式更新 |
| 搜索 | 防抖 300ms；结果限制 100 条；FTS5 使用 `ORDER BY rank` |
| 批量导入 | 分词和匹配在 Isolate 中执行；进度回调更新 UI |
| 复习卡片 | 预加载下一张卡片数据；使用 PageView 缓存 |
| 数据库迁移 | 使用 Drift 的 schema 版本管理；迁移在事务中执行 |
| 词典复制 | 使用流式复制，避免一次性加载大文件到内存 |
| 通知调度 | 开机后重新调度（RECEIVE_BOOT_COMPLETED） |

---

> 本文档为技术架构基线。开发过程中如需变更技术选型或数据模型，需更新版本号并记录变更原因。
