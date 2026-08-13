# ===== 词记（WordMem）R8 / ProGuard 规则 =====
# 开启 minifyEnabled + shrinkResources 后生效

# ---- Flutter 引擎（官方推荐保留）----
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---- 插件：本地通知（含反射注册的 Receiver/装饰类）----
-keep class com.dexterous.** { *; }

# ---- 插件：文件选择器（原生 Activity/Provider 反射入口）----
-keep class io.flutter.plugins.filepicker.** { *; }

# ---- 插件：sqlite3（原生库，无 Java 混淆需求，保留以防 AAR 清单引用）----
-keep class com.tekartik.sqflite.** { *; }

# ---- desugar / 通用兜底 ----
-dontwarn java.lang.invoke.**
-dontwarn com.google.errorprone.**
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-keepattributes SourceFile, LineNumberTable

# ---- Google Play Core 动态交付（离线 App 不引入依赖，忽略缺失类，防 R8 报错）----
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
