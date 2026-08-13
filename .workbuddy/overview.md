# v1.1.3 更新概览

## 版本信息
- **版本**: 1.1.3+11
- **APK**: `词记-v1.1.3-debug.apk`（165MB）
- **编译状态**: 零错误零警告（18 条既有 info）

## 本次更新（5 项）

### 1. 艾宾浩斯曲线新增 3h/8h 检测节点
- 间隔序列 `3小时 → 8小时 → 1天 → 2天 → 4天 → 7天 → 15天 → 30天`
- 前期小时级密集检测，记忆更牢固

### 2. 熟悉度联动降级
- 翻卡阶段选"很轻松"但后续选单词/默写出错 → 自动降低该词熟悉度（回退排程）

### 3. 选单词词典形似选项 + 显示释义
- 干扰项从整个词典挑选形似词（编辑距离相近），考察识别能力
- 提交后每个选项下方显示释义

### 4. 近义词挑战漏选/错选显示释义
- 提交后下方显示漏选、错选单词的释义卡片

### 5. 近义词删除二级确认 + 学习趋势柱状图
- 单词卡近义词删除增加确认对话框
- 学习趋势折线图改柱状图：左侧数量刻度 + 底部日期标签

## 修改/新增文件
| 文件 | 变更 |
|------|------|
| `domain/services/fsrs_service.dart` | 3h/8h 节点 + state 映射 |
| `data/repositories/review_repository.dart` | 新增 demoteWord |
| `data/sources/dict_source.dart` | 新增 lookupSimilar 形似词 |
| `domain/models/word_option.dart` | 新建选项模型 |
| `data/repositories/word_repository.dart` | buildWordOptions 词典形似 |
| `features/review/widgets/quiz_cards.dart` | 选项显示释义 |
| `features/review/review_page.dart` | 熟悉度联动 |
| `features/review/synonym_challenge_page.dart` | 漏选/错选释义 |
| `features/word_detail/word_detail_page.dart` | 删除二级确认 |
| `features/stats/stats_page.dart` | 柱状图 + Y轴 |
