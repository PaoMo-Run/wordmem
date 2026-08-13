# 词记（WordMem）正式发布 v1.2.0 — 工作汇报

## 一、本次完成事项（v1.2.0 正式发布优化）

| 步骤 | 结果 |
|------|------|
| 版本号重写 | ✅ `pubspec.yaml` → **1.2.0+12**（原 1.1.3+11） |
| Release 构建 | ✅ `flutter build apk --release` 成功 |
| **APK 体积优化** | ✅ **61.4MB**（debug 157MB → 压缩 **61%**，目标 <100MB 达成） |
| R8 优化 | ✅ `minifyEnabled` + `shrinkResources` + `proguard-rules.pro`（修复 Play Core 缺失类） |
| ABI 裁剪 | ✅ arm64-v8a + armeabi-v7a（去掉 x86_64） |
| 正式签名 | ✅ 独立 keystore（30 年有效，`wordmem-release.keystore`） |
| .gitignore | ✅ 补全（签名/密钥/构建产物不入库） |
| CHANGELOG | ✅ 新建，记录 1.1.2 → 1.2.0 变更 |
| GitHub 推送 | ✅ master + **release/1.2.0** 分支 + **v1.2.0** tag |
| GitHub Release | ✅ 已创建，上传 APK 资产 `wordmem-v1.2.0-release.apk` |

## 二、交付物

- **`词记-v1.2.0-release.apk`**（项目根目录，61.4MB，正式签名）
- **GitHub Release**：https://github.com/PaoMo-Run/wordmem/releases/tag/v1.2.0
- **发行版分支**：`release/1.2.0`（commit `7613bbf`）

## 三、体积优化明细

| 项 | 说明 |
|----|------|
| debug → release | 157MB → 61.4MB（-61%） |
| R8 代码压缩 | 移除未用 Java/Kotlin 代码 |
| 资源收缩 | shrinkResources 删除无用资源 |
| 字体树摇 | MaterialIcons 1.6MB → 9KB（-99.5%） |
| ABI 裁剪 | 去掉 x86_64（约省 15-20MB） |

## 四、关键决策与踩坑记录

1. **R8 缺失类**：Flutter 引擎引用 `com.google.android.play.core.*`（离线 App 无此依赖）→ `-dontwarn` + keep 规则解决。
2. **沙箱清除 `.git/refs`**：导致 git 仓库短暂损坏，通过 `git fetch` + `reset --hard FETCH_HEAD` + 手动写 ref 恢复；推送改用 commit hash 直推。
3. **GitHub 资产名限制**：上传文件名不支持中文（被替换为 `.`），最终用 `wordmem-v1.2.0-release.apk`。
4. **GitHub 推送认证**：本地无凭据，用 Token（`repo` 权限）+ HTTP header 方式推送，Token 未写入项目文件。

## 五、后续注意事项

- **签名密钥请妥善保存**：keystore 在 `wordmem/android/app/wordmem-release.keystore`，密码见本地 `wordmem/android/key.properties`（不入库）。
- Kotlin 2.0.0 与 AGP 8.7.0 有升级提示（Flutter 建议 Kotlin ≥2.2.20 / AGP ≥8.11.1），当前仅 warning，不影响发布。
