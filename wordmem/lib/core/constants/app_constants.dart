/// 应用常量
class AppConstants {
  AppConstants._();

  static const String appName = '词记';
  static const String appNameEn = 'WordMem';

  /// 应用版本号（与 pubspec.yaml 保持一致，用于"关于"页展示）
  static const String appVersion = '2.0.0';

  // FSRS-5 默认参数（历史遗留，仅用于 fsrs_params 表兼容）。
  // 当前复习算法已切换为艾宾浩斯遗忘曲线，不再使用这组权重。
  static const List<double> defaultFsrsParams = [
    0.4072, 1.1829, 3.1262, 15.4722, 7.2102,
    0.5316, 1.0651, 0.0234, 1.616, 0.1544,
    1.0824, 1.9813, 0.0953, 0.2975, 2.2042,
    0.2407, 2.9466, 0.5034, 0.6567,
  ];

  static const double defaultDesiredRetention = 0.9;
  static const double minDesiredRetention = 0.8;
  static const double maxDesiredRetention = 0.95;

  // 词典文件（唯一内置：专业版，含航空专业词）
  static const String dictProDbName = 'ecdict_pro.db';
  static const String dictProVersion = 'ecdict_pro_v4';
  static const int dictProWordCount = 15529;

  // 个人词库数据库
  static const String vocabDbName = 'vocabulary.db';

  // 备份
  static const String backupVersion = '1.0';

  // 通知
  static const String notificationChannelId = 'wordmem_reminder';
  static const String notificationChannelName = '学习提醒';
  static const String notificationChannelDesc = '每日复习提醒通知';

  // 默认提醒时间
  static const int defaultReminderHour = 20;
  static const int defaultReminderMinute = 0;

  // 分页
  static const int pageSize = 50;
  static const int searchLimit = 100;

  // 批量导入
  static const int batchImportChunkSize = 500;

  // SharedPreferences keys
  static const String keyFirstLaunch = 'first_launch';
  static const String keyReminderHour = 'reminder_hour';
  static const String keyReminderMinute = 'reminder_minute';
  static const String keyReminderEnabled = 'reminder_enabled';
  static const String keyThemeMode = 'theme_mode';
  static const String keyDesiredRetention = 'desired_retention';
}
