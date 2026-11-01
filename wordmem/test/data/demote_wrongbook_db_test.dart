import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wordmem/data/database/app_database.dart';
import 'package:wordmem/data/database/review_dao.dart';
import 'package:wordmem/data/database/word_dao.dart';
import 'package:wordmem/data/repositories/review_repository.dart';
import 'package:wordmem/domain/models/review_rating.dart';
import 'package:wordmem/domain/services/fsrs_service.dart';

// v2.2.1 三项熟练词功能的 **DB 级** 回归测试：
// 1. demoteMasteredTo 参数化打回：任意 T0–T8、cardState 落点、difficulty 清零、
//    due=now+intervalForReps(targetReps)、越界钳制
// 2. getQuizWrongEntries 抽查错题本聚合：kind='quiz' 且 rating=again 才计入，
//    常规复习的 rating=again（今日忘记）不得混入
//
// 与 `test/data/mastered_settlement_db_test.dart` 共用同一套宿主 sqlite3
// 加载方案（回退 Python DLL，找不到则整组跳过）。

bool _sqliteReady = false;

void _ensureSqliteNative() {
  try {
    final probe = sqlite3.openInMemory();
    probe.dispose();
    _sqliteReady = true;
    return;
  } catch (_) {
    // 默认加载失败 → 尝试已知候选路径
  }
  final candidates = <String>[
    if (Platform.environment['WORDMEM_SQLITE3_DLL'] case final env?) env,
    r'C:\Users\Enece\AppData\Local\Programs\Python\Python313\DLLs\sqlite3.dll',
    r'C:\Users\Enece\.workbuddy\binaries\python\versions\3.13.12\DLLs\sqlite3.dll',
  ];
  for (final path in candidates) {
    if (!File(path).existsSync()) continue;
    open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(path));
    try {
      final probe = sqlite3.openInMemory();
      probe.dispose();
      _sqliteReady = true;
    } catch (_) {
      // 这个候选也不可用，试下一个
    }
    return;
  }
}

void main() {
  _ensureSqliteNative();

  if (!_sqliteReady) {
    test('宿主缺少 sqlite3 原生库，DB 级测试跳过', () {
      markTestSkipped(
          'Windows 宿主未找到可用的 sqlite3.dll（可设 WORDMEM_SQLITE3_DLL 指定路径）');
    });
    return;
  }

  late AppDatabase db;
  late WordDao wordDao;
  late ReviewDao reviewDao;
  late ReviewRepository repo;

  setUp(() {
    db = AppDatabase()..initForTest();
    wordDao = WordDao(db);
    reviewDao = ReviewDao(db);
    repo = ReviewRepository(db, wordDao, reviewDao, FsrsService());
  });

  tearDown(() {
    db.vocab.dispose();
  });

  int insertWord({
    String cardState = 'mastered',
    double difficulty = 0,
    int reps = 0,
    int lapses = 0,
  }) =>
      wordDao.insert(
        word: 'demo-${DateTime.now().microsecondsSinceEpoch}',
        cardState: cardState,
        difficulty: difficulty,
        reps: reps,
        lapses: lapses,
        due: DateTime.now().toUtc().toIso8601String(),
      );

  group('demoteMasteredTo 参数化打回', () {
    test('mastered 打回 T2 → learning、reps=2、difficulty 清零、due≈+3h', () {
      final id = insertWord(difficulty: 1, lapses: 3);
      final before = DateTime.now().toUtc();

      repo.demoteMasteredTo(id, targetReps: 2);

      final w = wordDao.getById(id)!;
      expect(w['card_state'], 'learning',
          reason: 'reps<=4 落 learning，与 FsrsService 毕业判据同口径');
      expect(w['reps'], 2);
      expect((w['difficulty'] as num).toDouble(), 0,
          reason: '残留的抽检失败计数必须清零，否则重新毕业后会被立即再打回');
      expect(w['lapses'], 3, reason: '遗忘次数保留，不因打回清零');
      final dueHours =
          DateTime.parse(w['due'] as String).difference(before).inMinutes;
      expect(dueHours, inInclusiveRange(175, 185),
          reason: 'intervalForReps(2) = 间隔表第 2 档（默认 3 小时）');
    });

    test('mastered 打回 T6 → review、due≈+1 天', () {
      final id = insertWord(difficulty: 1);
      final before = DateTime.now().toUtc();

      repo.demoteMasteredTo(id, targetReps: 6);

      final w = wordDao.getById(id)!;
      expect(w['card_state'], 'review');
      expect(w['reps'], 6);
      expect((w['difficulty'] as num).toDouble(), 0);
      final dueHours =
          DateTime.parse(w['due'] as String).difference(before).inHours;
      expect(dueHours, inInclusiveRange(23, 25),
          reason: 'intervalForReps(6) = 间隔表第 6 档（默认 1 天）');
    });

    test('mastered 打回后离开抽检池（card_state 不再是 mastered）', () {
      final id = insertWord(cardState: 'mastered', difficulty: 1);
      repo.demoteMasteredTo(id, targetReps: 5);
      final w = wordDao.getById(id)!;
      expect(w['card_state'], isNot('mastered'),
          reason: '抽检候选=card_state=mastered AND due<=now，打回即出池');
    });

    test('越界钳制：targetReps=9 → 落 T8（review、due≈+2 天）', () {
      final id = insertWord(difficulty: 1);
      final before = DateTime.now().toUtc();

      repo.demoteMasteredTo(id, targetReps: 9);

      final w = wordDao.getById(id)!;
      expect(w['reps'], 8);
      expect(w['card_state'], 'review');
      final dueHours =
          DateTime.parse(w['due'] as String).difference(before).inHours;
      expect(dueHours, inInclusiveRange(47, 49),
          reason: 'intervalForReps(8) = 间隔表第 8 档（默认 2 天）');
    });

    test('打回 T0 → learning、due≈now（立即出现在复习队列首）', () {
      final id = insertWord(difficulty: 1);
      final before = DateTime.now().toUtc();

      repo.demoteMasteredTo(id, targetReps: 0);

      final w = wordDao.getById(id)!;
      expect(w['card_state'], 'learning');
      expect(w['reps'], 0);
      final dueSeconds =
          DateTime.parse(w['due'] as String).difference(before).inSeconds;
      expect(dueSeconds.abs(), lessThan(60),
          reason: 'intervalForReps(0)=0 → due=now，词立即可复习');
    });

    test('在途词（review）同样可打回 —— 功能2 测试题跳转打回的数据前提', () {
      final id = insertWord(cardState: 'review', reps: 4, difficulty: 0);
      final before = DateTime.now().toUtc();

      repo.demoteMasteredTo(id, targetReps: 1);

      final w = wordDao.getById(id)!;
      expect(w['card_state'], 'learning');
      expect(w['reps'], 1);
      final dueHours =
          DateTime.parse(w['due'] as String).difference(before).inMinutes;
      expect(dueHours, inInclusiveRange(55, 65),
          reason: 'intervalForReps(1) = 间隔表第 1 档（默认 1 小时）');
    });
  });

  group('getQuizWrongEntries 抽查错题本聚合', () {
    test('只统计 kind=quiz 的 again，常规复习的 again 不混入；附带当前状态字段', () {
      final a = insertWord(cardState: 'mastered', difficulty: 1);
      final b = insertWord(cardState: 'mastered', difficulty: 1);
      final c = insertWord(cardState: 'mastered');

      // A：抽检答错两次；B：答错一次；C：抽检答对
      repo.logMasteredQuiz(a, correct: false);
      repo.logMasteredQuiz(a, correct: false);
      repo.logMasteredQuiz(b, correct: false);
      repo.logMasteredQuiz(c, correct: true);

      // A 的常规复习答错（rating=again、kind=review）——不得计入错题本
      reviewDao.insert(
        userWordId: a,
        rating: ReviewRating.again.value,
        state: 'review',
        reviewedAt: DateTime.now().toUtc().toIso8601String(),
      );

      final entries = repo.getQuizWrongEntries();
      final byId = {for (final e in entries) e['id'] as int: e};

      expect(entries.length, 2, reason: 'C 从未答错、A 的常规复习 again 不计入');
      expect(byId.containsKey(a), isTrue);
      expect(byId.containsKey(b), isTrue);

      expect(byId[a]!['wrong_count'], 2);
      expect(byId[a]!['word'], isNotNull, reason: 'JOIN user_words 带回词信息');
      expect(byId[a]!['card_state'], 'mastered',
          reason: '附带当前学习状态（打回后标签会变）');
      expect(byId[b]!['wrong_count'], 1);

      final lastWrongA = DateTime.parse(byId[a]!['last_wrong_at'] as String);
      expect(lastWrongA.isAfter(DateTime.now().toUtc().subtract(const Duration(minutes: 5))),
          isTrue, reason: 'last_wrong_at = 最近一次答错时间');
    });

    test('无答错记录时返回空列表', () {
      insertWord(cardState: 'mastered');
      expect(repo.getQuizWrongEntries(), isEmpty);
    });
  });
}
