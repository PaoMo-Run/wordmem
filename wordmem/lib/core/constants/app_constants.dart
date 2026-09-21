/// 应用常量
class AppConstants {
  AppConstants._();

  static const String appName = '词记';
  static const String appNameEn = 'WordMem';

  /// 应用版本号（与 pubspec.yaml 保持一致）
  ///
  /// ⚠️ 仅作兜底/元数据用：UI 展示请优先用 PackageInfo 实时读取
  /// （about_page / me_page），避免发版时忘记同步此处。
  static const String appVersion = '2.1.10';

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
  static const String dictProVersion = 'ecdict_pro_v5';
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

  // 出题顺序的「时间权重」（v2.1.7，用户定值）
  //
  // 出题/抽取得分 = w × 时间名次 + (1 − w) × 随机数，按得分升序出题：
  // - 1.0 → 完全按时间排（= v2.1.6 的行为：随机化被时间权重完全覆盖）
  // - 0.5 → 时间倾向与随机各占一半振幅 ← 当前取值
  // - 0.0 → 完全随机
  //
  // 复习队列与熟练词抽检**共用同一个权重**：两者本质是同一个问题（"该先出谁"），
  // 拆成两个常量只会让以后调参时漏掉一处。
  static const double orderTimeWeight = 0.5;

  // 熟练词抽检（v2.1.6：已掌握词的防遗忘抽检机制）
  /// 单次抽检词量
  static const int masteredQuizCount = 5;
  /// 答对后到下次抽检的间隔（天）
  static const int masteredQuizCorrectDays = 15;
  /// 池子不足单次抽检量时，答对后的**缩短冷却期**（v2.1.7 用户定值）
  ///
  /// 已掌握词 < 5 个时一轮抽检就会覆盖全池，再用 15 天会让抽检断档半个月；
  /// 缩短到与「跳过」同档的 7 天。
  static const Duration masteredQuizShortCooldown = Duration(days: 7);
  /// 答错（第 1 次）后的复检间隔
  static const Duration masteredQuizWrongDelay = Duration(days: 3);
  /// 用户跳过后重新进入候选池的间隔（短于答对，保证跳过的词更快被补测）
  static const Duration masteredQuizSkipDelay = Duration(days: 7);

  /// 首页「即将到期」提示的时间窗口（小时）
  static const int upcomingDueWindowHours = 3;

  // 测验作答限时与评分（v2.1.8）
  //
  // 每个词**每轮测验**满分 [quizMaxScore] = 三环节 × 2 分：
  //   每答错一次扣 1 分；每环节作答超过限时再扣 1 分。
  //   未作答（点「下一题」跳过）按**答错**计，同样扣 1 分。
  //   因此 3 环节 × (错 1 + 超时 1) = 最多扣 6 分 → 最低 0 分。
  /// 英译汉 / 选单词的作答限时
  static const Duration quizTimeLimitChoice = Duration(seconds: 5);
  /// 默写的作答限时（要打字，比点选慢，用户实测后放宽到 8 秒）
  static const Duration quizTimeLimitDictation = Duration(seconds: 8);
  /// 单轮测验满分（= 环节数 × 2）
  static const int quizMaxScore = 6;

  // 启动时云端备份探测（v2.1.7）
  /// 冷启动后延迟多久开始探测：不阻塞启动、不显示 loading，失败无感
  static const Duration syncProbeDelay = Duration(seconds: 2);

  // SharedPreferences keys
  static const String keyFirstLaunch = 'first_launch';
  static const String keyReminderHour = 'reminder_hour';
  static const String keyReminderMinute = 'reminder_minute';
  static const String keyReminderEnabled = 'reminder_enabled';
  static const String keyDesiredRetention = 'desired_retention';
  static const String keyWordAudioEnabled = 'word_audio_enabled';

  /// 用户已选「稍后」的云端快照名（v2.1.7）：同一份快照不再重复提示，
  /// 只有云端出现更新的快照时才会再次询问。
  static const String keySyncProbeDismissed = 'sync_probe_dismissed_snapshot';
}
