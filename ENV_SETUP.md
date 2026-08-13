# 环境重建指南（重装系统后必读）

> 本文件说明如何在全新 Windows 系统上恢复「词记 (WordMem)」项目的完整开发环境。
> 目标环境基于原机器配置，版本务必一致以避免兼容问题。

---

## 〇、第一步：网络环境自检（重要，先做）

> **核心结论：本项目编译不依赖代理（Clash），走国内镜像直连即可。**
> 之前反复出现的「编译卡死 / Gradle 下载失败」根因是「系统配置了 `127.0.0.1:7890` 代理但代理没运行」，而非「没有代理」。

### 决策流程

```
重装后网络是干净的（无代理）
        │
        ├─ 只编译本项目 ──> 无需装 Clash，直接走国内镜像（见下）
        │                     ✓ 项目已内置：Gradle 腾讯云镜像 + 阿里云 Maven + 禁用系统代理
        │
        ├─ 需要访问 GitHub（clone/push）──> 可选装 Clash
        │
        └─ 装了 Clash 但可能不常开 ──> 也安全：项目已用 -Djava.net.useSystemProxies=false 规避
```

### 自检命令

```bash
# 1. 检查是否残留代理环境变量（重装后应为空，若装了 Clash 会有）
env | grep -i proxy

# 2. 直连国内镜像是否可达（应返回 200）
curl --noproxy "*" -sI https://maven.aliyun.com/repository/central | head -1
curl --noproxy "*" -sI https://mirrors.cloud.tencent.com/gradle/gradle-8.9-all.zip | head -1
```

### Flutter/Dart 国内镜像（可选，加速 pub get 和 SDK 下载）

```bash
# 永久设置（Windows 系统环境变量）
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
PUB_HOSTED_URL=https://pub.flutter-io.cn

# 或临时（当前会话）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

> 项目内的 Gradle 镜像（`android/gradle-wrapper.properties`、`settings.gradle`、`build.gradle`、`gradle.properties`）**已经配好**，重装后无需改动。

### 关键原则

1. **编译 ≠ 需要 Clash**。所有依赖都有国内镜像，直连即可。
2. **Clash 仅用于 GitHub/Google 等站点**，与编译无关。
3. **最危险的状态是「代理配了但没开」**，本项目已通过「禁用系统代理 + 国内镜像」规避该问题。
4. 若装了 Clash 后遇到编译卡死，先关掉 Clash 或确认代理端口未注入环境变量。

---

## 一、组件清单（版本锁定）

| 组件 | 版本 | 原安装路径 | 说明 |
|------|------|-----------|------|
| Flutter SDK | **3.44.9**（stable） | `C:\flutter` | 含 Dart 3.12.2 |
| Android SDK | platform 36 | `C:\Android\Sdk` | 含 NDK、build-tools |
| NDK | **29.0.14206865** | SDK 内 | Flutter 指定的 NDK 版本 |
| JDK | **17** | 随 Android Studio 或独立安装 | Gradle 8.9 需要 JDK 17 |
| Gradle | **8.9** | 项目 wrapper 自动下载 | 已配置镜像，见下文 |
| Python | 3.13.x | 系统 | 仅用于 `scripts/` 工具脚本 |
| Git | 最新 | 系统 | Flutter 必需 |

---

## 二、安装步骤

### 1. Flutter SDK

```bash
# 下载 stable 版 Flutter，解压到 C:\flutter（务必用稳定版）
git clone -b stable https://github.com/flutter/flutter.git C:\flutter
# 或从官网下载 zip 解压

# 验证
flutter --version   # 应显示 Flutter 3.44.9 / Dart 3.12.2
```

> 若无法访问 GitHub，可用国内镜像：设置环境变量 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`，或使用 Gitee 镜像的 Flutter SDK。

### 2. Android SDK + NDK

推荐通过 Android Studio 安装（SDK Manager），或命令行：

```bash
# 通过 sdkmanager 安装（需先装 command-line tools）
sdkmanager "platforms;android-36" "build-tools;34.0.0" "ndk;29.0.14206865" "platform-tools"
```

在项目 `wordmem/android/local.properties` 中指定路径：

```properties
sdk.dir=C:/Android/Sdk
flutter.sdk=C:/flutter
```

> 原项目 `local.properties` 不纳入版本控制（gitignore），重装后需按上述格式重建。

### 3. JDK 17

安装 OpenJDK 17 或 JDK 17，确保 `JAVA_HOME` 指向 JDK 17。Gradle 8.9 与 AGP 8.7.0 要求 JDK 17。

---

## 三、Gradle 依赖与镜像（重要）

原项目已为**国内网络**配置好镜像，重装后无需改动，但需理解其作用：

1. **Gradle 发行版镜像**（`android/gradle/wrapper/gradle-wrapper.properties`）：
   ```properties
   distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.9-all.zip
   ```

2. **Maven 仓库镜像**（`android/settings.gradle` + `android/build.gradle`）：
   ```gradle
   maven { url 'https://maven.aliyun.com/repository/google' }
   maven { url 'https://maven.aliyun.com/repository/central' }
   ```

3. **禁用系统代理**（`android/gradle.properties`）：
   ```properties
   -Djava.net.useSystemProxies=false
   ```

---

## 四、网络代理注意事项（原机器的坑）

原机器曾配置系统代理 `127.0.0.1:7890`（Clash 类工具），代理未运行时会导致：

- Gradle 下载依赖 SSL 握手失败
- `curl` 走代理连接失败

**处理方式**：
- 若新系统有代理工具，请保持其运行；
- 若没有，确保已按上文配置「禁用系统代理 + 国内镜像」；
- 若 `flutter` 命令无响应，删除 `C:\flutter\bin\cache\lockfile`、`flutter.bat.lock` 及 `%APPDATA%\.dart-tool\dart-flutter-telemetry-session.json` 后重试。

---

## 五、依赖与首次编译

```bash
cd wordmem

# 拉取 pub 依赖（可配置 PUB_HOSTED_URL 国内镜像加速）
flutter pub get

# 静态分析（目标 0 error 0 warning）
flutter analyze

# 首次编译较慢（需下载 Gradle 发行版 + 依赖，约 5~15 分钟）
flutter build apk --debug
```

首次 `flutter pub get` 若慢，可临时设置：
```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

## 六、验证清单

编译成功标志：

- `flutter analyze`：0 error 0 warning（若干 `info` 级建议可忽略）
- `flutter build apk --debug`：输出 `wordmem/build/app/outputs/flutter-apk/app-debug.apk`（约 165MB）

产物复制到项目根目录并命名 `词记-vX.Y.Z-debug.apk` 即可交付。

---

## 七、项目恢复

若项目源码以 zip 形式保存（本打包），解压后：

1. 按上文安装 Flutter + Android SDK + JDK
2. 重建 `wordmem/android/local.properties`
3. `cd wordmem && flutter pub get && flutter build apk --debug`

Git 历史（`.git`）已随源码打包，解压后可直接 `git log` 查看历史；远程仓库为 `https://github.com/PaoMo-Run/wordmem`（如仍有效，可 `git remote -v` 确认）。

---

## 八、在 WorkBuddy 中续接项目（重装后完整步骤）

### 第 1 步：解压项目到固定目录

解压 `词记-wordmem-源码-v1.1.3.zip` 到一个稳定目录（建议专用开发盘，如 `D:\Projects\`）：

```
D:\Projects\词记项目\
  ├─ wordmem\          ← Flutter 源码（实际代码在这里）
  ├─ README.md         ← 项目说明
  ├─ AGENTS.md         ← AI 代理项目约定（Codex 也读这个）
  ├─ ENV_SETUP.md      ← 本文件
  ├─ docs\             ← 设计文档
  └─ .git\             ← 完整 git 历史
```

### 第 2 步：搭建开发环境

按本文件「〇 ~ 五」章节操作：网络自检 → 国内镜像 → Flutter 3.44.9 + Android SDK + JDK 17。

### 第 3 步：重建 local.properties（关键，打包时已排除）

`wordmem/android/local.properties` 含本机 SDK 路径，打包时被排除。解压后**手动创建**该文件，内容：

```properties
sdk.dir=C:/Android/Sdk
flutter.sdk=C:/flutter
```

> 路径按你实际的 Android SDK 与 Flutter 安装位置修改。

### 第 4 步：在 WorkBuddy 中打开项目

1. 打开 WorkBuddy，点击新建任务
2. 点击输入框左下角的 **「选择工作空间」**，选择解压后的**项目根目录**（即包含 `wordmem/`、`README.md` 的那一层，不是 `wordmem/` 子目录）
3. 在任务描述里说明意图，例如：
   > 「继续开发词记（WordMem）Flutter 项目，先读 AGENTS.md 了解项目，然后跑 flutter analyze 验证环境」
4. 可选：用 `@` 引用 `AGENTS.md` / `README.md` 作为上下文，让 AI 更快进入状态

### 第 5 步：验证环境

让 WorkBuddy 执行 `flutter analyze`（或 `flutter --version`），确认环境就绪后即可继续开发。

---

> **一句话总结重装后流程**：解压项目 → 装 Flutter/Android SDK/JDK → 重建 local.properties → WorkBuddy 里「选择工作空间」指向项目根目录 → 让 AI 读 AGENTS.md 开工。
