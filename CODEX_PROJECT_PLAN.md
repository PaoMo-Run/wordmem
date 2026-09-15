# 词记 WordMem · Codex 重构项目规划

> **用途**：本规划供 Codex 从零重构「词记」时作为唯一事实源。Codex 无本项目历史上下文，一切以本文档为准。
> **版本基线**：功能、词典、UI 概念均以 v2.0.1（已发布、稳定）为等价目标；**已知引擎限制是硬约束，必须遵守，勿重复试错**。
> **日期**：2026-08-31 ｜ **目标设备**：红米 K60 Pro / HyperOS 3.0 / Android 16（一切性能/视觉决策以它为准）

---

## 0. 给 Codex 的第一句话

这是一个**离线优先**的英语词汇学习 Android App（Flutter）。现有 v2.0.1 已稳定发布，但工程历史复杂、试错过多，因此决定**重写**。你的任务：在遵守本文档「红线」的前提下，从零实现一套**功能等价、架构更干净、性能在目标设备上流畅**的新工程。

**最重要的一条红线**：本项目的"玻璃/背景动态效果"在目标设备上受**引擎级限制**，方案已经妥协定稿（见 §5、§6），**不要尝试突破**——那不是实现问题，是引擎限制，重写也不会改变结果。

---

## 1. 项目概述

| 项 | 值 |
|---|---|
| 应用名 | 词记 WordMem |
| 类型 | Flutter Android 离线英语词汇学习 App |
| 核心价值 | 完全离线学习（词典/复习/数据全本地），AI 仅短文生成/陪练时按需联网 |
| 复习算法 | **FSRS**（Free Spaced Repetition Scheduler），非艾宾浩斯——文案勿再写"艾宾浩斯 7 周期" |
| 平台 | Android（minSdk 26 / targetSdk 34） |
| 包名 | com.wordmem.app |

---

## 2. 技术栈与环境

- **框架**：Flutter（引擎 3.44.9，Dart 3.12）
- **状态管理**：Riverpod（flutter_riverpod 2.x）
- **路由**：go_router（5 tab ShellRoute + push 页面）
- **数据库**：sqlite3 / sqflite（**WAL 模式**；备份必须用 SQLite backup API，禁止直接拷贝 db 文件——WAL 未合并会导出残缺库）
- **本地存储**：shared_preferences（设置）、flutter_secure_storage（API Key）
- **其他**：file_picker（导入）、flutter_local_notifications（复习提醒）、url_launcher（GitHub 链接）、package_info_plus（版本）
- **AI**：OpenAI 兼容 Chat Completions（默认内置免费服务 Agens Free，可配自定义 base_url + key）
- **构建环境**：Flutter `D:\flutter`、JDK `D:\jdk-17`、SDK `D:\Android\Sdk`、pub 缓存 `D:\pub-cache`（Windows）

---

## 3. 功能清单（等价实现 v2.0.1）

### 3.1 五大 Tab（底部导航，5 个独立悬浮胶囊 dock）

**今日** `/today`
- 顶部 Hero 卡：问候语（按时段）、副标题（到期/收工/空库文案）、连续天数徽章、进度环（progress 恒 0-100%）、三项统计（待学新词 dueNew / 待复习 dueReview / 已复习）
- 主行动按钮：空库→"添加单词"；有任务→"开始复习"
- 快捷入口网格（8 个，可自定义/拖拽排序，最多 8）：
  添加单词、今日短文、批量导入、自选复习、词群记忆、短文记忆库、词库、统计
- 空词库 EmptyState

**复习中心** `/review-center`
- 任务量卡：`dueNew + dueReview`（**口径：到期待学新词 + 到期待复习熟词，两者互斥**；今日新增不计入任务量）
- 开始复习（进入三段式测验）
- 自由练习区：自选复习、近义词挑战、词根挑战、词群记忆（快捷入口语义色跨页协调）
- 本周复习量柱状图（近 7 日，全 0 显示"本周暂无复习记录"）
- 空词库 EmptyState

**短文** `/story-center`
- 今日短文入口卡
- 短文记忆库（列表 + 详情 + 测试入口）

**词库** `/library`
- 搜索框（双范围切换：我的词库 / 词典）
- 我的词库：状态/标签/收藏/仅测试 筛选栏；**分页加载：首屏 50 条，滑到底后继续大幅下滑（overscroll > 60px）才加载下一批 50**；列表尾状态提示（加载中/继续大幅下滑加载更多 已 N/M/已加载全部）
- 词典模式：英文前缀 + 中文释义检索内置词典，点击跳转添加页预填
- 短文测试分组视图（按短文折叠展开）
- 底部须留 116px 避让悬浮 dock

**我的** `/me`
- 个人概览卡、学习统计入口、设置入口、AI 设置入口、关于页入口（iOS 设置分组卡样式）

### 3.2 Push 页面

- **添加单词** `/add-word`：输入单词 → 词典匹配卡（内置词典命中）→ 收藏分组选择 → 保存
- **文本批量导入** `/text-import`：粘贴英文文本 → 自动提取并匹配词典
- **单词详情** `/word/:id`：基本信息（词/音标/释义）、掌握状态、收藏、删除、词根展示、进词根挑战
- **复习** `/review`：**三段式测验**——英译汉（选择题）/ 选单词 / 默写；FSRS 评分四档：没想起/困难/正确/轻松（红/琥珀/绿/蓝）
- **自选复习** `/custom-review`：按日期筛选，不影响算法
- **近义词挑战** `/synonym-challenge`、**词根挑战** `/root-challenge`、**近义词群挑战** `/synonym-group-challenge`
- **词群记忆** `/word-group-memory`：近义词群 + 词根群 两个 Tab
- **短文页** `/story`：AI 生成短文（模板兜底）→ 编辑 → 挖空测试（一句一题：理解/巩固/拓展 3 模式）→ 存入记忆库
- **短文编辑** `/story-edit`、**短文测试** `/story-quiz/:id/:mode`、**短文记忆库** `/story-memory`
- **统计** `/stats`：概览（总词数/连续天数）、掌握状态分布、近 7 日、学习趋势折线图
- **设置** `/settings`：目标记忆率（80-95% slider，影响 FSRS 间隔）、复习提醒（开关+时间）、主题（浅/深/跟随系统）、词典信息 + 按新词典刷新释义、数据备份（导出/导入）、关于
- **AI 服务设置** `/ai-config`：内置免费服务一键启用 + 自定义 base_url/key
- **关于** `/about`：版本信息、更新日志（新版本在上）、GitHub 链接、隐私政策
- **快捷入口编辑** `/today-quick-actions`：拖拽排序，最多 8

### 3.3 全局行为

- 底部 5 胶囊悬浮 dock；宽屏（≥840dp）切换 NavigationRail 侧栏
- 复习提醒（本地通知）
- 数据备份导出/导入（SQLite backup API + quick_check 自检 + sha256 校验提示）
- 深色模式一等公民（正文对比度 ≥4.5:1）

---

## 4. 词典资料清单（必须复用，勿重新整理）

| 项 | 值 |
|---|---|
| 内置词典 | `ecdict_pro.db`（**15529 词**，含 **423 航空专业词**，pro_av 标记已净化，见 词典数据导出/词典校对_第二轮_完成报告_20260903.md）——唯一内置词典 |
| 检索主键 | **英文全称 = headword**；缩写大写放释义（例：`迎角（Angle of Attack，缩写 AOA）`） |
| 缩写反查 | 支持按释义 LIKE 反查缩写 |
| 词性格式 | `[n.]` 方括号白名单：n/a/vt/vi/v/adv/num/prep/pron/pl/interj/conj/abbr/aux/pref；异体 adj→a、int→interj；合并式 `vt.vi.`→`[vt.] [vi.]`；字面 `\n` 一律转真换行 |
| 词典版本 | 改库须同步 `dictProVersion`，否则已装 App 不重载 |

> 词典 db 可直接沿用现有 `assets/dict/ecdict_pro.db`（已定稿校对过），或按上述规范由 Codex 重新生成。**重建成本高、风险大，强烈建议直接复用现有 db 文件。**

---

## 5. UI 与交互设计概念（妥协定稿，勿改方向）

### 5.1 设计语言：静态玻璃世界（v2.0.1 定稿）

背景与玻璃**全部静态**（无动画、无实时模糊），视觉"活"感靠静态材质分层达成：

- **背景**：静态 aurora——6 个代码径向渐变光斑（teal/cyan/mint/indigo/暖琥珀/紫罗兰，浅深两套 alpha），尺寸 200-320 逻辑像素、分散四角/边缘、**独立可辨不重叠成糊**；深色主光斑 alpha ~0.40。
- **玻璃组件**（GlassContainer / GlassButton / GlassSection / GlassNavBar）：
  - 静态磨砂 = 半透明填充（浅色白 0.40→0.13，深色白 0.15→0.06）+ 亮描边 + 顶部高光 + 轻阴影
  - **blur: 0**（无 BackdropFilter）
  - 可点玻璃：交互层必须在 blur 之上（若将来加 blur）；`onTap` 必须接入 InkWell
  - 容器尺寸**内容驱动**（禁止 `StackFit.expand`，装饰层用 `Positioned.fill`）
  - 按钮**必须有横向留白**（`EdgeInsets.symmetric(horizontal: 18)`），否则文字贴边
- **切页过渡**：轻量 `FadeForwardsPageTransitionsBuilder`（450ms，`backgroundColor: Colors.transparent` 防闪屏）
- **页面**：Scaffold/AppBar 透明，背景由路由层全局 ShellRoute `Stack[AppBackground, child]` 提供（全局唯一一份）

### 5.2 色彩 Token 体系（`AppColors`，页面禁止裸色值）

- 品牌种子 `#00897B`（teal）；浅色 primary `#006A60`；深色 primary `#4DB6AC` + **onPrimary `#00332F`（深青字，修复对比度）**
- 表面：lightBg `#FAFBFA` / darkBg `#0F1413`；卡片用 M3 `surfaceContainerLow`
- 次级文本：`onSurfaceVariant`（浅 `#5F6B68` / 深 `#B3BCB9`），**禁止 alpha 叠加文本**
- 评分四色：没想起红 / 困难琥珀 / 正确绿 / 轻松蓝（深色各亮化一版）
- 快捷入口 8 色：添加单词/短文/导入/自选复习/词群记忆/短文记忆库/词库/统计
- 功能色：error/warning/success/info；掌握状态四色（新/学习中/复习/已掌握）
- 反模式红线：禁 AI 蓝渐变（3B6FE0→4F8CFF）、禁 Tailwind 色板硬编码、禁卡片套卡片、禁逐屏手选字号（用 M3 type scale）

### 5.3 妥协替代路径（若需"活"感，不依赖实时渲染）

背景既然静态，动态性改由静态材质分层达成（**均不依赖实时 blur**）：
1. **预烘焙 blur 背景（首选）**：启动时把 aurora 预模糊成 σ=8/16/24 三档静态图；每张玻璃卡按层级叠对应档模糊图做装饰层（对齐坐标+ClipRRect 裁切），每帧只 alpha 混合缓存纹理 → 零重采样零冻结；层叠=顶层用更高档图+更强填充 → 视觉上"顶层更毛"
2. **分层 scrim**：GlassContainer 加 `layer/fog` 参数，顶层更"奶"、底层更透
3. **雾度 veil**：页面顶层叠静态白色 veil，越上层越白

---

## 6. 已知引擎限制（红线，必须遵守）

> 以下均为**已真实验证/官方核实的引擎级事实**，不是实现问题。重写不会改变结果，**勿重复试错**。

1. **玻璃实时 `BackdropFilter` 对滚动内容采样滞后**：悬浮 dock 或滚动列表条目上开真 blur 会"滑动冻结、停下才刷新"。
2. **Flutter 3.44 Android = Only Impeller**：Android 16（API 36）上 `io.flutter.embedding.android.EnableImpeller=false` 是 **no-op**（无 Skia 兜底）。不要依赖"关 Impeller"。
3. **背景动画与真 blur 互斥**：背景一旦流动，任何 blur 的成本模型不可接受。**背景保持静态 = 玻璃可行的前提**。
4. **层叠模糊（顶层比底层更毛）**：机制上引擎自底向上合成天然支持（顶层采样底层已模糊输出）。但受限于第 1 条（滚动场景）；若在"静态大卡"上做，**禁用 `BackdropGroup`**（共享 backdrop key 破坏累加）。
5. **性能纪律**：每屏真实 blur ≤5 处、σ≤20；dock 与列表条目永远 blur:0；避免每帧 `ValueListenableBuilder`/`Transform` 重建的动画（=切页卡顿根因）。

---

## 7. 数据模型（概念层，Codex 可自行设计表结构）

- **Word**（词条，含复习调度字段）：id、word（主键索引）、translation、phonetic、pos、tags、favorite、state（new/learning/review/mastered）、due、reps、interval、ease、created_at、updated_at；航空专业词标记
- **ReviewLog**：word_id、timestamp、rating（again/hard/good/easy）、elapsed
- **DictWord**（词典检索）：headword、translation、pos、pro_av（航空标记）
- **Story**（短文）：id、title、content、translation、source（ai/template）、created_at
- **StoryQuiz**（挖空测试）：story_id、word、填空信息
- **DailyStats**（或由复习日志聚合）：date、new_words、reviews
- **QuickActions**（配置）：8 个入口顺序
- **Settings**（SharedPreferences）：desiredRetention、themeMode、reminder、AI config

---

## 8. 架构建议

- 分层：`features/<域>/presentation/` + `core/theme/` + `shared/{widgets,router,providers}` + `data/`（DAO/Repository）+ `domain/`（模型/服务，如 FSRS、RootMatcher）
- 状态：Riverpod（Provider/Notifier），词库版本号驱动列表自动刷新（wordListVersion）
- 路由：go_router，外层 ShellRoute 全局背景壳（`Stack[AppBackground, child]`），5 tab 内层 ShellRoute
- 玻璃组件库：`shared/widgets/glass.dart`（GlassContainer/Button/Section/NavBar 四件套，静态配方）
- 备份：SQLite **backup API**（非文件拷贝）+ 导出后 `quick_check` 自检
- 测试：widget 回归测试（玻璃布局/点击/分页），`flutter analyze` 0 issue 为门槛

---

## 9. 验收标准

1. 功能与 v2.0.1 等价（§3 清单逐项可操作）
2. 内置词典复用 `ecdict_pro.db`（15529 词 + 423 航空词），检索/缩写反查/词性格式符合 §4
3. **目标设备（K60 Pro）流畅**：5 tab 切换 + push 进出无"冻结后刷新"；列表滚动流畅；450ms 过渡不闪屏
4. 深色模式对比度达标（正文 ≥4.5:1）
5. `flutter analyze` 0 issue；widget 测试全过
6. 遵守 §6 全部红线（无实时 blur 于滚动元素、无背景动画、无 BackdropGroup 滥用）

---

## 10. 参考资料索引（如 Codex 可访问旧工程）

- 旧工程：`D:\program\wordmem\wordmem`（可参考功能实现，但勿复制其复杂历史）
- 交接文档：`2.0发行准备/UI改版_交接文档.md`（v2.0.1 状态 + 勿重蹈覆辙清单）
- 词典构建：`D:\WorkBuddyData\词记开发\_vocab_extract\`（如需重建词典）
- 发布说明：`2.0发行准备/词记2.0发布说明.md`
