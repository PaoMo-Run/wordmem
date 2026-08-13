# 词记（WordMem）开发环境搭建与首次编译 — 工作汇报

## 一、本次完成事项

按用户要求，从零完成「词记」离线英语词汇 App 的开发环境搭建与首次编译：

| 步骤 | 结果 |
|------|------|
| 阅读项目文档 | ✅ 已读 AGENTS.md / README.md / ENV_SETUP.md |
| 网络环境检测 | ✅ 国内镜像全部直连可达，无需 Clash 代理 |
| Flutter SDK 3.44.9 | ✅ 安装到 `D:\flutter`（Dart 3.12.2，与锁定版本一致） |
| JDK 17 | ✅ 安装到 `D:\jdk-17`（Temurin 17.0.20） |
| Android SDK | ✅ 安装到 `D:\Android\Sdk`（platform 36 / build-tools 34.0.0 / NDK 29.0.14206865 / platform-tools / cmdline-tools） |
| 环境变量 | ✅ 已写入用户级（JAVA_HOME / ANDROID_HOME / GRADLE_USER_HOME / PUB_CACHE / 国内镜像 / PATH） |
| local.properties | ✅ 已重建，指向 D 盘路径 |
| flutter pub get | ✅ 成功（74 依赖） |
| flutter analyze | ✅ 0 error 0 warning（18 个 info 级建议可忽略） |
| flutter build apk --debug | ✅ 成功，产物 `app-debug.apk` 约 157MB |

## 二、交付物

- **`词记-v1.1.3-debug.apk`**（项目根目录，164,931,782 字节）

## 三、环境路径汇总（均在非系统盘 D）

- Flutter SDK：`D:\flutter`
- JDK 17：`D:\jdk-17`
- Android SDK：`D:\Android\Sdk`
- Gradle 缓存：`D:\Android\.gradle`（GRADLE_USER_HOME）
- pub 缓存：`D:\pub-cache`（PUB_CACHE）

## 四、关键决策与踩坑记录

1. **curl 路径问题**：Windows 原生 curl 不识别 Git Bash 的 `/d/` 路径，需用 `D:/` 风格，否则报 `write error`。
2. **Flutter SDK 下载限流**：`storage.flutter-io.cn` 限流（HTTP 429），改用 Google 官方源 `storage.googleapis.com` + 断点续传，速度 50+MB/s。
3. **编译走国内镜像**：腾讯云 Gradle + 阿里云 Maven 直连成功，全程未依赖 Clash。
4. **Flutter 自动补充 SDK 组件**：编译时自动安装了 NDK 28.2 / Platform 34、35 / CMake 3.22.1（故首次编译约 15 分钟）。

## 五、后续注意事项

- 项目 Kotlin 版本有升级提示（Flutter 建议 ≥2.2.20），当前为 warning 不影响编译，后续可评估升级。
- 编译产物较大（约 157MB）符合预期，与 AGENTS.md 记录一致。
