import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wordmem/data/database/app_database.dart';
import 'package:wordmem/data/database/review_dao.dart';
import 'package:wordmem/data/database/word_dao.dart';
import 'package:wordmem/data/repositories/review_repository.dart';
import 'package:wordmem/domain/services/fsrs_service.dart';

// 抽检结算的 **DB 级** 回归测试（v2.2.0 阶段 B/C 参数调整 + 打回 T5）。
//
// 与 `test/domain/mastered_quiz_test.dart`（纯静态函数）互补：这里用
// `AppDatabase.initForTest()` 内存库跑真实仓库方法，证明写库语义：
// 1. 首次答错 → 保留 mastered + difficulty=1 + due≈+2d + quiz 历史落库
// 2. 第二次答错 → 打回 T5（card_state=review、reps=5、due≈+1d、difficulty 清零）
// 3. 重测答对（hold）→ 不洗白：difficulty 仍 1，due 推到 2 天后
// 4. settleMasteredQuizRetries 的 failedIds / hold 双分支
//
// 宿主测试需要 sqlite3 原生库：默认加载失败时回退到已知的 Python 安装目录
// （可用环境变量 WORDMEM_SQLITE3_DLL 覆盖）。找不到则整组跳过而不是失败。

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
    test('宿主缺少 sqlite3 原生库，DB 级结算测试跳过', () {
      markTestSkipped(
          'Windows 宿主未找到可用的 sqlite3.dll（可设 WORDMEM_SQLITE3_DLL 指定路径）');
    });
    return;
  }

  late AppDatabase db;
  late WordDao wordDao;
  late ReviewRepository repo;

  setUp(() {
    db = AppDatabase()..initForTest();
    wordDao = WordDao(db);
    repo = ReviewRepository(db, wordDao, ReviewDao(db), FsrsService());
  });

  tearDown(() {
    db.vocab.dispose();
  });

  int insertMastered({double difficulty = 0}) => wordDao.insert(
        word: 'settle-${DateTime.now().microsecondsSinceEpoch}',
        cardState: 'mastered',
        difficulty: difficulty,
        due: DateTime.now().toUtc().toIso8601String(),
      );

  test('首次答错：保留 mastered、difficulty=1、due≈+2 天，quiz 历史落库', () {
    final id = insertMastered();
    final before = DateTime.now().toUtc();

    repo.submitMasteredQuiz(id, correct: false);

    final w = wordDao.getById(id)!;
    expect(w['card_state'], 'mastered', reason: '第 1 次答错不移出 mastered');
    expect((w['difficulty'] as num).toDouble(), 1);
    final dueHours = DateTime.parse(w['due'] as String)
        .difference(before)
        .inHours;
    expect(dueHours, inInclusiveRange(47, 49),
        reason: '答错复检窗口默认 2 天');

    final logs = repo.getReviewHistory(id);
    expect(
      logs.any((l) => (l['kind'] as String?) == 'quiz'),
      isTrue,
      reason: '抽检结果必须写进 review_logs（kind=quiz）',
    );
  });

  test('第二次答错：打回 T5 —— card_state=review、reps=5、due≈+1 天、difficulty 清零', () {
    // difficulty=1 = 已错过一次（真实链路里由首次答错写入，这里直接摆好状态）
    final id = insertMastered(difficulty: 1);
    final before = DateTime.now().toUtc();

    repo.submitMasteredQuiz(id, correct: false);

    final w = wordDao.getById(id)!;
    expect(w['card_state'], 'review', reason: '第 2 次答错必须移出 mastered');
    expect(w['reps'], 5, reason: 'v2.2.0 打回目标改为 T5');
    expect((w['difficulty'] as num).toDouble(), 0,
        reason: 'difficulty 必须清零，否则毕业后第一次答错会被立即再打回');
    final dueHours =
        DateTime.parse(w['due'] as String).difference(before).inHours;
    expect(dueHours, inInclusiveRange(23, 25),
        reason: 'T5 节点间隔 = 间隔表第 5 档（默认档 1 天）');
  });

  test('重测答对（hold 结算）：不洗白 —— difficulty 仍 1，due 推到 2 天后', () {
    final id = insertMastered(difficulty: 1);

    repo.settleMasteredQuizRetries([id], failedIds: {});

    final w = wordDao.getById(id)!;
    expect(w['card_state'], 'mastered');
    expect((w['difficulty'] as num).toDouble(), 1,
        reason: '重测答对不得清除失败标记（一次侥幸不算过关）');
    final dueHours = DateTime.parse(w['due'] as String)
        .difference(DateTime.now().toUtc())
        .inHours;
    expect(dueHours, inInclusiveRange(47, 49),
        reason: 'hold 的复检窗口走答错路径（默认 2 天）');
  });

  test('结算双分支：failedIds 打回 T5，其余走 hold', () {
    final a = insertMastered(difficulty: 1);
    final b = insertMastered(difficulty: 1);

    repo.settleMasteredQuizRetries([a, b], failedIds: {a});

    final wa = wordDao.getById(a)!;
    expect(wa['card_state'], 'review');
    expect(wa['reps'], 5);

    final wb = wordDao.getById(b)!;
    expect(wb['card_state'], 'mastered');
    expect((wb['difficulty'] as num).toDouble(), 1);
  });
}
