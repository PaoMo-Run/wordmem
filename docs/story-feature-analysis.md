# 「今日短文」功能可行性分析报告

> 项目：词记 WordMem v1.2.0（完全离线英语词汇学习 App）
> 日期：2026-08-15
> 目的：评估"用今日所学单词生成一段短文，用户背诵以加深记忆、锻炼语感"功能的可实现性与改动量

---

## 一、结论（TL;DR）

**✅ 功能可实现，数据层完全支持；改动量中等（新增约 1,100–1,300 行代码，修改 8–9 个文件）。**

唯一的战略级决策点：**是否接受打破「完全离线」硬性约束来接入在线 AI 模型**（见第三节）。若接受，推荐"离线模板兜底 + 在线 AI 增强"双轨方案；若不接受，纯离线模板方案也能落地，但生成质量受限。

---

## 二、现状盘点：数据与架构是否支撑

### 2.1 "今日所学单词"可精确取到 ✅

| 数据需求 | 现有来源 | 状态 |
|----------|----------|------|
| 今日新增单词 | `user_words.created_at`（已有 `countNewToday()` 方法） | ✅ |
| 今日复习过的单词 | `review_logs.reviewed_at`（已有 `countReviewedToday()`） | ✅ |
| 单词的释义/词性/词形 | `user_words.custom_def` + 只读词典 `ecdict_mini.db`（`pos` / `translation` / `exchange` 词形变化） | ✅ |
| 避免近义重复 | 哈工大同义词词林 `synonym_cilin.json`（已有 `SynonymDetector`） | ✅ |

> 现状缺一个 DAO 方法：`getWordsStudiedToday()`（今日新增 UNION 今日复习，JOIN 取释义），约 30 行。

### 2.2 架构兼容性 ✅

- **Clean Architecture**（data / domain / features / shared / core）——新功能按 `features/story/` 落地，与现有 7 个 feature 平级，不破坏分层。
- **Riverpod** 依赖注入——仿照 `reviewRepositoryProvider` 模式新增 provider，零改动现有逻辑。
- **go_router**——新增 `/story` 路由，与 `/review` 等平级。
- **数据库**——`AppDatabase._createSchema()` 增加 `story_logs` 表（存生成历史），不影响现有表。
- **UI 入口**——`TodayActionButtons` 加一个按钮（如"今日短文"），复用现有模式。

---

## 三、核心矛盾：完全离线 vs AI 模型 ⚠️

项目 AGENTS.md 有**硬性约束**：
> AndroidManifest 不得添加 INTERNET 权限；不得引入 http / dio / 任何网络 SDK。

而"接入 AI 模型生成"（DeepSeek / 通义 / 文心等）**必然需要联网 API 调用**。两者直接冲突。移动端本地跑 LLM 不现实（模型数 GB、无 NPU 适配、内存受限），不列入考虑。

### 三条技术路线对比

| 维度 | 路线 A：在线 AI API | 路线 B：纯离线模板引擎 | 路线 C：混合（推荐） |
|------|--------------------|----------------------|--------------------|
| **生成质量**（通畅+事实逻辑） | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **离线定位** | ❌ 打破（需加 INTERNET 权限 + http 依赖） | ✅ 完全保持 | ✅ 默认离线，AI 为可选增强 |
| **实现成本** | 中（网络层 + 错误处理 + API key 管理） | 中（模板库 + 语义槽位匹配） | 高（两者都要做） |
| **稳定性/隐私** | 依赖网络；词句会上传第三方 | 完全本地，零隐私风险 | 离线无风险，AI 需授权 |
| **推荐场景** | 用户明确接受联网 | 定位至上 | **产品最优解** |

**模板方案如何保证"事实逻辑"？** 这是离线方案最大的质疑点。设计思路：
- 预写**主题化事实模板库**（如动物：`In the {forest}, the {fox} chased a {rabbit}.`），模板内部事实恒定正确；
- 用词典词性 + 释义关键词做**语义槽位匹配**（动物名词 → 动物槽位，动作动词 → 动作槽位）；
- 近义词检测避免同义堆叠；
- 结果仍可能略显"模板感"，但语句正确、事实无误。

---

## 四、推荐方案数据流设计（路线 C 第一版：离线模板）

```
今日页面 → 点「今日短文」
   │
   ├─ 1. 取词：getWordsStudiedToday()  → 今日新增+复习的单词（上限 10 个）
   ├─ 2. 富化：查 ECDICT 取 pos / translation / exchange（词形变化）
   ├─ 3. 生成：StoryTemplateEngine
   │        ├─ 按词性+释义关键词 → 匹配主题模板槽位
   │        ├─ 槽位填充 + 词形变化（单复数/时态）
   │        └─ 未匹配的词 → 用"通用句型"兜底
   ├─ 4. 存储：story_logs 表（词集快照 + 短文 + 生成时间 + 引擎版本）
   ├─ 5. 展示：StoryPage
   │        ├─ 全文 + 今日单词高亮
   │        ├─ 挖空背诵模式（今日单词挖空，点击显示释义）
   │        └─ 重新生成 / 换一批词
   └─ 6. （可选增强）设置中开启「AI 生成」→ 调在线 API，失败自动回退模板
```

---

## 五、改动量清单（按推荐路线 C 第一版估算）

### 新增文件（约 8 个，≈1,100–1,300 行）

| 文件 | 职责 | 估算行数 |
|------|------|---------|
| `domain/models/story.dart` | Story / StorySentence 模型 | ~60 |
| `domain/services/story_template_engine.dart` | **核心**：主题模板库 + 槽位匹配 + 词形变换 | ~350–450 |
| `domain/services/ai_story_service.dart` | AI 服务接口（抽象）+ 可选在线实现 | ~120–180 |
| `data/database/story_dao.dart` | story_logs 增查删 | ~80 |
| `data/repositories/story_repository.dart` | 取今日词→富化→生成→存→取 编排 | ~100 |
| `features/story/presentation/story_page.dart` | 生成/展示/背诵页 | ~250–300 |
| `features/story/presentation/widgets/story_card.dart` | 高亮/挖空卡片（参考 quiz_cards） | ~150 |
| `features/story/presentation/widgets/story_generate_button.dart` | 生成按钮组 | ~60 |

### 修改文件（约 8 个）

| 文件 | 改动 | 估算 |
|------|------|------|
| `data/database/app_database.dart` | 新增 `story_logs` 表 + 索引（CREATE TABLE ~15 行） | +20 |
| `data/database/word_dao.dart` | 新增 `getWordsStudiedToday()`（今日新增 UNION 复习） | +30 |
| `shared/providers/app_providers.dart` | story 相关 provider（3 个） | +40 |
| `shared/router/app_router.dart` | 新增 `/story` 路由 | +8 |
| `features/today/presentation/widgets/today_action_buttons.dart` | 「今日短文」入口按钮 | +20 |
| `features/settings/presentation/settings_page.dart` | （若做 AI）API Key / 开关设置项 | +60 |
| `pubspec.yaml` | （若做 AI）`http` 依赖；否则零改动 | 0 / +1 |
| `AndroidManifest.xml` | （若做 AI）`INTERNET` 权限；**否则不动** | 0 / +1 |

### 不动的东西
- 现有 7 个 feature 页面的业务逻辑、复习算法（fsrs_service）、近义词检测、备份/导入 —— **零改动**。
- 数据库结构向后兼容（只增表，不改表）。

---

## 六、风险与对策

| 风险 | 等级 | 对策 |
|------|------|------|
| 模板生成"语句通顺但生硬/模板感" | 中 | 模板库持续扩充；多套随机变体；展示时提示"AI 可生成更自然版本" |
| 模板事实逻辑错误（语义槽位错配） | 中 | 槽位按主题封闭设计；词性+释义关键词双条件匹配；未匹配词走通用句型不硬塞 |
| 单词过少（今日 <3 词） | 低 | 不足时并入最近 1–2 天单词，或提示"先学几个词再生成" |
| AI 调用失败/超时/无网 | 中 | 自动回退模板引擎；UI 明示生成来源（模板/AI） |
| API key 明文存本地 | 低 | 存 SharedPreferences 可接受；设置页提示隐私 |
| 破坏离线定位（若选纯 AI 路线） | 高 | **建议选路线 C**：默认离线，AI 需用户显式开启 |

---

## 七、分期建议

- **阶段 1（保底）**：离线模板引擎 + 今日短文页 + 挖空背诵 → 不碰任何网络约束，可随下个版本发布。
- **阶段 2（增值）**：设置页加「AI 增强生成」（API key + 开关 + 隐私说明），INTERNET 权限仅在开启该功能时生效（或用独立 manifest 变体）。

---

## 八、需要你拍板的决策点

1. **是否接受打破「完全离线」约束接入在线 AI？**
   - A. 接受 → 直接做 AI 路线（质量最高，改 INTERNET 权限 + http 依赖）
   - B. 不接受 → 纯离线模板方案（保持定位，质量有限）
   - **C. 混合（推荐）** → 先离线模板，AI 作为可选增强
2. 背诵交互形态：全文高亮背诵 / 挖空填空背诵 / 两者都要？
3. 短文语言：纯英文（推荐，练语感）/ 英中对照？

> 备注：AGENTS.md「版本号更新清单」要求改版本号同步 3 处（pubspec / app_constants / settings_page），本功能上线发布时按清单执行。

---

## 九、方案 v2：剪切板中转 AI（用户提议，已采纳 ⭐）

**核心思路：App 不联网，把生成提示词写入系统剪切板 → 用户粘贴到已安装的 AI 软件（豆包 / DeepSeek / GPT 等）生成 → 复制结果 → 回 App 粘贴导入。**

### 9.1 可行性验证 ✅（已实测代码）

| 环节 | 技术 | 依赖 | 状态 |
|------|------|------|------|
| 写入提示词 | Flutter SDK `Clipboard.setData`（flutter/services 内置） | 零依赖 | ✅ |
| 读取生成结果 | `Clipboard.getData` 或 App 内文本框粘贴 | 零依赖 | ✅ |
| 唤起 AI 软件 | 手动引导（提示"请打开豆包粘贴"），不自动跳转 | 零依赖 | ✅（暂不引入 url_launcher） |
| （可选增强）系统分享导入 | Activity 加 `ACTION_SEND text/plain` intent-filter | 无网络权限 | 🔧 可选 |

### 9.2 方案评价

**优点（完美契合离线定位）**
- App 保持**零网络**：不加 INTERNET 权限、不引 http 依赖、无需 API key —— 硬约束零破坏
- 无隐私争议：词句由用户**自己决定**发给哪个 AI，App 不知情
- 实现成本最低：AI 服务退化为"提示词生成 + 文本解析"（约 100 行），比调 API 更简单
- 兼容任意 AI 软件，用户按喜好选

**缺点（体验上的取舍）**
- 手动中转：复制→粘贴→生成→复制→粘贴回来，多 3–4 步
- 生成质量取决于用户所选 AI，App 无法控制
- 无 AI 软件的用户只能退回离线模板

### 9.3 与用户确认的产品形态（最终定型）

1. **生成环节**：离线模板一键生成（即时可用）；「AI 协助」按钮 → 剪切板写入提示词（要求输出：英文短文 + 中文对照 + 单词列表）→ 引导用户去 AI 软件生成 → 回来粘贴导入
2. **展示环节**：中英对照排版；**点词释义**（点击文中任意词弹出 ECDICT 释义，复用词典查询）
3. **背诵检测**：挖空填空，**用户纯英文填写**，App 自动判对（大小写/时态容错）

### 9.4 改动量更新（方案 v2）

相比原推荐路线 C：
- **删去**：http 依赖、INTERNET 权限、API key 设置页、ai_story_service 的 API 调用部分
- **新增**：`ai_prompt_service.dart`（提示词模板 + AI 结果解析，替代原 API service，更简单）
- **净效果**：新增代码从 ~1,100–1,300 行降至 **~950–1,100 行**；涉及文件仍约 8 新增 + 8 修改；`pubspec.yaml` 与 `AndroidManifest.xml` **零改动**（除非做分享导入增强）

---

## 十、决策更新（2026-08-15）：放弃完全离线，AI 端口已落地 ⭐

**用户拍板**：预见到未来需要 AI 陪练（需 AI 感知用户学习数据），**放弃「完全离线」要求，先铺好 AI 接入基础设施**。分析方案 v2 的剪切板中转调整为直接接入 AI 服务。

### 已落地的 AI 基础设施（本次交付，全部通过 analyze 0 error 0 warning）

| 端口 | 文件 | 说明 |
|------|------|------|
| 配置模型 + 服务商预设 | `lib/infra/ai/ai_config.dart` | DeepSeek / GLM / Kimi / 通义 / 豆包 / OpenAI 预设 |
| 服务抽象接口 | `lib/infra/ai/ai_service.dart` | `chat()` / `chatStream()`（流式预留）/ `testConnection()` |
| OpenAI 兼容实现 | `lib/infra/ai/openai_compatible_service.dart` | 非流式 + SSE 流式 + 错误分类（auth/rateLimit/server/timeout…） |
| 配置持久化 | `lib/infra/ai/ai_config_store.dart` | API Key 走 Keystore 加密，其余 SharedPreferences |
| **学习上下文** | `lib/domain/services/learning_context_builder.dart` | `DailyLearningContext`：今日新增/复习/错词/掌握分布 → `toPromptText()` / `toJson()` |
| 数据补充 | `review_dao.dart` | `getReviewedWordsToday()` / `getMissedWordsToday()` |
| 全局注册 | `app_providers.dart` | `aiConfigProvider` / `aiServiceProvider` / `learningContextBuilderProvider` |
| 配置 UI | `ai_config_page.dart` + 设置页入口 + `/ai-config` 路由 | 服务商下拉 / Key 输入 / 测试连接 / 保存 |

### 变更的约束（已同步 AGENTS.md）
- 「完全离线」→「**本地优先**」：核心功能仍离线，AI 可选联网
- `AndroidManifest.xml` 已加 `INTERNET` 权限（仅 AI 功能使用）
- 新依赖：`http`（OpenAI 兼容协议）、`flutter_secure_storage`（Key 加密）
- 新增约定：所有 AI prompt 必须先注入 `LearningContextBuilder` 的学习上下文；网络调用只走 `infra/ai/` 抽象层

### 下一步（今日短文功能本体，待开发）
1. `StoryTemplateEngine`（离线模板兜底，主题化事实模板库）
2. `StoryPage`（中英对照 + 点词释义 + 纯英文挖空背诵）
3. 直接调 `aiServiceProvider` 生成（替换剪切板中转）
