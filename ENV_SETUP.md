# 环境重建指南（重装系统后必读）

> 本文件说明如何在全新 Windows 系统上恢复「词记 (WordMem)」项目的完整开发环境。
> 目标环境基于原机器配置，版本务必一致以避免兼容问题。

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
