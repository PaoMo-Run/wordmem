# v1.1.2 更新概览

## 版本信息
- **版本**: 1.1.2+10
- **APK**: `词记-v1.1.2-debug.apk`（165MB）
- **编译状态**: 零错误零警告（18 条既有 info）
- **Git**: 首次提交 `25fd7cc`

## 本次更新（4 项）

### 1. 复习算法切换为艾宾浩斯遗忘曲线 ✅
- 固定间隔序列 `1 / 2 / 4 / 7 / 15 / 30` 天
- 评分驱动：忘了→回退1天 / 困难→保持 / 正确→下一档 / 轻松→跳一档
- 遗忘曲线 R(t) = e^(-t/S)
- 替换原 FSRS-5 公式（更直观、可预测）

### 2. 导入备份支持覆盖 / 续写模式 ✅
- 覆盖：整库替换（修复 WAL 残留导致的"导入不生效"）
- 续写：只添加当前没有的单词，保留现有数据（按 word 去重 + 外键重建）
- 导入弹窗三选：覆盖 / 续写 / 取消

### 3. 近义词多级匹配（中文词林）✅
- 引入哈工大同义词词林扩展版（4.5 万词条，1.1MB）
- L1 词林义类层（解决"高兴↔愉快"同义不同字漏报）+ L2 义项重叠兜底 + 黑名单

### 4. 翻卡 bug 修复 + 3D 动画 + 版本号 ✅
- 修复第二词直接显示释义（卡片状态残留）
- 翻卡改为 rotateY 3D 翻转动画
- 关于页版本号 1.0.0 → 1.1.2

## 修改/新增文件
| 文件 | 变更 |
|------|------|
| `domain/services/fsrs_service.dart` | 艾宾浩斯算法重写 |
| `data/repositories/backup_repository.dart` | 新增 importMerge 续写 |
| `data/sources/synonym_dict_source.dart` | 新建，词林数据源 |
| `data/repositories/word_repository.dart` | 近义词多级匹配 |
| `assets/dict/synonym_cilin.json` | 词林数据（新增） |
| `features/settings/settings_page.dart` | 导入三选 + 版本号 + 文案 |
| `features/review/widgets/quiz_cards.dart` | 3D 翻卡动画 |
| `core/constants/app_constants.dart` | appVersion 常量 |

## 待办（后续）
- AI 陪练（用户暂缓，接入方案已定：国产大模型直连 + key 可更新）
- Gradle/Kotlin 版本升级预警（非阻塞）
