import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/database/word_dao.dart';
import '../../data/database/review_dao.dart';
import '../../data/database/stats_dao.dart';
import '../../data/database/settings_dao.dart';
import '../../data/database/story_dao.dart';
import '../../data/database/story_quiz_dao.dart';
import '../../data/sources/dict_source.dart';
import '../../data/sources/synonym_dict_source.dart';
import '../../data/repositories/word_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/backup_repository.dart';
import '../../data/repositories/import_repository.dart';
import '../../data/repositories/story_repository.dart';
import '../../domain/services/fsrs_service.dart';
import '../../domain/services/pronunciation_service.dart';
import '../../domain/services/tts_cache_store.dart';
import '../../domain/services/learning_context_builder.dart';
import '../../domain/services/ai_story_service.dart';
import '../../domain/services/story_quiz_engine.dart';
import '../../infra/audio/audio_file_player.dart';
import '../../infra/audio/tts_player.dart';
import '../../infra/notification_service.dart';
import '../../infra/ai/ai_config.dart';
import '../../infra/ai/ai_config_store.dart';
import '../../infra/ai/ai_service.dart';
import '../../infra/ai/openai_compatible_service.dart';

// ============================================================
// 词库刷新信号 Provider
// ============================================================

/// 词库列表版本号：每次 add/delete/update 操作后自增，
/// LibraryPage 等页面通过 ref.listen 监听此值实现自动刷新。
final wordListVersionProvider = StateProvider<int>((ref) => 0);

/// 近义词群 / 词根群版本号：群挑战通过、群组迁移、手动移出词林/词根后自增，
/// WordGroupMemoryPage 通过 ref.listen 监听此值实现自动刷新。
final groupVersionProvider = StateProvider<int>((ref) => 0);

/// 短文版本号：短文保存/编辑/归档、测验记录写入后自增，
/// StoryCenterPage / StoryMemoryPage 通过 ref.listen 监听此值实现自动刷新。
final storyVersionProvider = StateProvider<int>((ref) => 0);

// ============================================================
// 核心基础设施 Providers
// ============================================================

/// SharedPreferences Provider
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

/// 数据库 Provider
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = AppDatabase();
  await db.init();
  // 加载中文同义词词林（近义词多级匹配 L1 层）
  await SynonymDictSource.instance.load();
  ref.onDispose(() => db.close());
  return db;
});

/// FSRS Service Provider
final fsrsServiceProvider = Provider<FsrsService>((ref) {
  return FsrsService();
});

// ============================================================
// DAO Providers
// ============================================================

final wordDaoProvider = Provider<WordDao>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return WordDao(db);
});

final reviewDaoProvider = Provider<ReviewDao>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return ReviewDao(db);
});

final statsDaoProvider = Provider<StatsDao>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return StatsDao(db);
});

final settingsDaoProvider = Provider<SettingsDao>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return SettingsDao(db);
});

final dictSourceProvider = Provider<DictSource>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return DictSource(db);
});

// ============================================================
// Repository Providers
// ============================================================

final wordRepositoryProvider = Provider<WordRepository>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return WordRepository(
    db,
    WordDao(db),
    DictSource(db),
    ref.watch(fsrsServiceProvider),
  );
});

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return ReviewRepository(
    db,
    WordDao(db),
    ReviewDao(db),
    ref.watch(fsrsServiceProvider),
  );
});

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return BackupRepository(
    db,
    WordDao(db),
    ReviewDao(db),
    SettingsDao(db),
  );
});

final importRepositoryProvider = Provider<ImportRepository>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return ImportRepository(db, WordDao(db), DictSource(db));
});

// ============================================================
// 通知 Provider
// ============================================================

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// ============================================================
// 主题 Provider
// ============================================================

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  return ThemeModeNotifier(prefs);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences? _prefs;

  ThemeModeNotifier(this._prefs)
      : super(_themeModeFromString(_prefs?.getString(AppConstants.keyThemeMode)));

  static ThemeMode _themeModeFromString(String? s) {
    return switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void set(ThemeMode mode) {
    state = mode;
    _prefs?.setString(AppConstants.keyThemeMode, mode.name);
  }
}

// ============================================================
// 目标记忆率 Provider
// ============================================================

final desiredRetentionProvider = StateNotifierProvider<DesiredRetentionNotifier, double>((ref) {
  final dao = ref.watch(settingsDaoProvider);
  return DesiredRetentionNotifier(dao);
});

class DesiredRetentionNotifier extends StateNotifier<double> {
  final SettingsDao _dao;

  DesiredRetentionNotifier(this._dao) : super(_dao.getDesiredRetention());

  void set(double value) {
    final clamped = value.clamp(
      AppConstants.minDesiredRetention,
      AppConstants.maxDesiredRetention,
    );
    _dao.setDesiredRetention(clamped);
    state = clamped;
  }
}

// ============================================================
// 提醒设置 Provider
// ============================================================

final reminderEnabledProvider = StateNotifierProvider<ReminderEnabledNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  return ReminderEnabledNotifier(prefs);
});

class ReminderEnabledNotifier extends StateNotifier<bool> {
  final SharedPreferences? _prefs;
  ReminderEnabledNotifier(this._prefs)
      : super(_prefs?.getBool(AppConstants.keyReminderEnabled) ?? false);

  void set(bool value) {
    state = value;
    _prefs?.setBool(AppConstants.keyReminderEnabled, value);
  }
}

final reminderHourProvider = StateNotifierProvider<ReminderHourNotifier, int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  return ReminderHourNotifier(prefs);
});

class ReminderHourNotifier extends StateNotifier<int> {
  final SharedPreferences? _prefs;
  ReminderHourNotifier(this._prefs)
      : super(_prefs?.getInt(AppConstants.keyReminderHour) ??
            AppConstants.defaultReminderHour);

  void set(int value) {
    state = value;
    _prefs?.setInt(AppConstants.keyReminderHour, value);
  }
}

final reminderMinuteProvider = StateNotifierProvider<ReminderMinuteNotifier, int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  return ReminderMinuteNotifier(prefs);
});

class ReminderMinuteNotifier extends StateNotifier<int> {
  final SharedPreferences? _prefs;
  ReminderMinuteNotifier(this._prefs)
      : super(_prefs?.getInt(AppConstants.keyReminderMinute) ??
            AppConstants.defaultReminderMinute);

  void set(int value) {
    state = value;
    _prefs?.setInt(AppConstants.keyReminderMinute, value);
  }
}

// ============================================================
// 首次启动 Provider
// ============================================================

final isFirstLaunchProvider = StateNotifierProvider<FirstLaunchNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
  return FirstLaunchNotifier(prefs);
});

class FirstLaunchNotifier extends StateNotifier<bool> {
  final SharedPreferences? _prefs;
  FirstLaunchNotifier(this._prefs) : super(_prefs?.getBool(AppConstants.keyFirstLaunch) ?? true);

  void complete() {
    state = false;
    _prefs?.setBool(AppConstants.keyFirstLaunch, false);
  }
}

// ============================================================
// AI 服务 Provider（未来短文生成 / AI 陪练的接入端口）
// ============================================================

/// AI 配置存储
final aiConfigStoreProvider = Provider<AiConfigStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  return AiConfigStore(prefs: prefs);
});

/// AI 配置状态（默认 DeepSeek 模板，异步加载已保存配置）
final aiConfigProvider = StateNotifierProvider<AiConfigNotifier, AiConfig>((ref) {
  return AiConfigNotifier(ref.watch(aiConfigStoreProvider));
});

class AiConfigNotifier extends StateNotifier<AiConfig> {
  final AiConfigStore _store;

  AiConfigNotifier(this._store)
      : super(AiConfig(
          providerName: AiPresets.deepseek.name,
          baseUrl: AiPresets.deepseek.baseUrl,
          apiKey: '',
          model: AiPresets.deepseek.defaultModel,
        )) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = await _store.load();
    } catch (_) {
      // 读取失败保持默认值
    }
  }

  /// 保存配置并同步状态（apiKey 为空则保留原 key）
  Future<void> save(AiConfig config) async {
    await _store.save(config);
    state = config;
  }

  /// 清除 API Key
  Future<void> clearApiKey() async {
    await _store.clearApiKey();
    state = state.copyWith(apiKey: '');
  }
}

/// AI 服务实例（配置变化时自动重建，可插拔任意 OpenAI 兼容服务商）
final aiServiceProvider = Provider<AiService>((ref) {
  var config = ref.watch(aiConfigProvider);
  // 未配置用户自己的 API 时，自动回退到内置免费服务（Agens Free）
  if (!config.isConfigured) {
    final preset = AiPresets.agnes;
    config = config.copyWith(
      providerName: preset.name,
      baseUrl: preset.baseUrl,
      apiKey: preset.apiKey ?? '',
      model: preset.defaultModel,
    );
  }
  return OpenAiCompatibleService(config);
});

/// 学习上下文构建器（把用户学习数据喂给 AI 的端口）
final learningContextBuilderProvider = Provider<LearningContextBuilder>((ref) {
  return LearningContextBuilder(
    wordDao: ref.watch(wordDaoProvider),
    reviewDao: ref.watch(reviewDaoProvider),
    statsDao: ref.watch(statsDaoProvider),
  );
});

// ============================================================
// 今日短文 Providers
// ============================================================

/// 短文仓库（取词 / 富化 / AI 生成 / 剪贴板导入 / 记忆库持久化）
final storyRepositoryProvider = Provider<StoryRepository>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  final dict = ref.watch(dictSourceProvider);
  final aiService = ref.watch(aiServiceProvider);
  final aiConfig = ref.watch(aiConfigProvider);
  return StoryRepository(
    storyDao: StoryDao(db),
    wordDao: WordDao(db),
    dict: dict,
    aiService: AiStoryService(aiService,
        enableThinking: aiConfig.enableThinking,
        thinkingLevel: aiConfig.thinkingLevel),
  );
});

// ============================================================
// 短文记忆测试 Providers
// ============================================================

/// 短文记忆测试 DAO
final storyQuizDaoProvider = Provider<StoryQuizDao>((ref) {
  final db = ref.watch(databaseProvider).maybeWhen(
        data: (d) => d,
        orElse: () => throw StateError('Database not ready'),
      );
  return StoryQuizDao(db);
});

/// 短文记忆测试出题引擎
final storyQuizEngineProvider = Provider<StoryQuizEngine>((ref) {
  return StoryQuizEngine();
});

// ============================================================
// 单词发音 Providers
// ============================================================

/// TTS 本地缓存存储（目录来自应用文档目录，持久化）
final ttsCacheStoreProvider = FutureProvider<TtsCacheStore>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return TtsCacheStore(cacheDir: p.join(dir.path, 'tts_cache'));
});

/// 本地音频文件播放器（单例，Provider 销毁时释放）
final audioFilePlayerProvider = Provider<AudioFilePlayer>((ref) {
  final player = AudioPlayersFilePlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// 系统 TTS 播放器（懒初始化，Provider 销毁时释放）
final ttsPlayerProvider = Provider<TtsPlayer>((ref) {
  final player = FlutterTtsPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// 发音级联服务：本地缓存 → 有道 → 百度 → 系统 TTS
final pronunciationServiceProvider = Provider<PronunciationService>((ref) {
  final cache = ref.watch(ttsCacheStoreProvider).maybeWhen(
        data: (c) => c,
        orElse: () => null,
      );
  return PronunciationCascade(
    cache: cache ?? _VoidTtsCacheStore(),
    client: http.Client(),
    filePlayer: ref.watch(audioFilePlayerProvider),
    ttsPlayer: ref.watch(ttsPlayerProvider),
  );
});

/// 单词发音开关（默认开启，持久化到 SharedPreferences）
final wordAudioEnabledProvider =
    StateNotifierProvider<WordAudioEnabledNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  return WordAudioEnabledNotifier(prefs);
});

class WordAudioEnabledNotifier extends StateNotifier<bool> {
  final SharedPreferences? _prefs;
  WordAudioEnabledNotifier(this._prefs)
      : super(_prefs?.getBool(AppConstants.keyWordAudioEnabled) ?? true);

  void set(bool value) {
    state = value;
    _prefs?.setBool(AppConstants.keyWordAudioEnabled, value);
  }
}

/// 缓存目录未就绪时的退化实现：get 恒 null（走在线源），
/// put 写系统临时文件（本次可播，不持久缓存）。
class _VoidTtsCacheStore implements TtsCacheStore {
  @override
  File? get(String word) => null;

  @override
  Future<File> put(String word, List<int> bytes) async {
    final tmp = await Directory.systemTemp.createTemp('tts_fallback');
    final f = File(p.join(tmp.path, 'audio.mp3'));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  @override
  Future<void> trim({int maxBytes = TtsCacheStore.defaultMaxBytes}) async {}

  @override
  Directory get directory => Directory.systemTemp;

  @override
  String fileName(String word) => '';
}
