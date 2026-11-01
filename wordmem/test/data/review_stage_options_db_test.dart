import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wordmem/data/database/app_database.dart';
import 'package:wordmem/data/database/word_dao.dart';
import 'package:wordmem/data/repositories/word_repository.dart';
import 'package:wordmem/data/sources/dict_source.dart';
import 'package:wordmem/domain/services/fsrs_service.dart';

// v2.2.1 回归：buildReviewStageOptions 两个环节的**全部选项**都要携带
// userWordId，否则测验作答后无法跳详情页手动打回。
//
// 真实 bug：英译汉干扰项在从干扰池重建 WordOption 时丢掉了 userWordId
// → 英译汉环节只有正确项可跳；汉译英是直接 add(cand) 透传，所以没暴露。
//
// 内存词典（initForTest 的 _dictDb=_vocabDb 为空词典）下，干扰池全部来自
// 个人词库 → 所有选项必须带 id；词典兜底词（userWordId=null）的排除逻辑
// 由卡片侧 canOpen 条件处理，不在本测试范围。

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
  late WordRepository repo;

  setUp(() {
    db = AppDatabase()..initForTest();
    // initForTest 的内存库不含词典表（dict_words 属于词典库）；
    // 建一张空表让 DictSource 的兜底查询返回空 → 干扰池全部来自个人词库
    db.vocab.execute(
        'CREATE TABLE IF NOT EXISTS dict_words (id INTEGER PRIMARY KEY, word TEXT, translation TEXT)');
    wordDao = WordDao(db);
    repo = WordRepository(db, wordDao, DictSource(db), FsrsService());
  });

  tearDown(() {
    db.vocab.dispose();
  });

  test('英译汉与汉译英的全部选项都携带 userWordId（回归：英译汉干扰项丢 id）', () {
    final ids = <int>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 6; i++) {
      ids.add(wordDao.insert(
        word: 'w$i-$stamp',
        cardState: 'review',
        customDef: '释义$i 的中文解释',
        due: DateTime.now().toUtc().toIso8601String(),
      ));
    }
    final queue = [for (final id in ids) wordDao.getById(id)!];

    final options = repo.buildReviewStageOptions(queue);

    expect(options.length, queue.length);
    for (final entry in options.entries) {
      final wo = entry.value.wordOptions;
      expect(wo.length, 4, reason: '汉译英应凑满 4 选项');
      for (final o in wo) {
        expect(o.userWordId, isNotNull,
            reason: '汉译英选项 ${o.word} 丢失 userWordId');
      }

      expect(entry.value.enToZhAvailable, isTrue,
          reason: 'custom_def 非空时英译汉必须可用');
      final ez = entry.value.enToZhOptions;
      expect(ez.length, 4, reason: '英译汉应凑满 4 选项');
      for (final o in ez) {
        expect(o.userWordId, isNotNull,
            reason: '英译汉选项 ${o.word} 丢失 userWordId（本次回归 bug）');
      }
    }
  });

  test('正确项的 userWordId 指向该词本身（跳详情页落在正确的词上）', () {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final id = wordDao.insert(
      word: 'self-$stamp',
      cardState: 'review',
      customDef: '自我的释义',
      due: DateTime.now().toUtc().toIso8601String(),
    );
    for (var i = 0; i < 5; i++) {
      wordDao.insert(
        word: 'filler$i-$stamp',
        cardState: 'review',
        customDef: '填充释义$i',
        due: DateTime.now().toUtc().toIso8601String(),
      );
    }
    final queue = wordDao.getAll(limit: 100).where((w) => (w['reps'] as int?) == 0 && w['card_state'] == 'review').toList();

    final options = repo.buildReviewStageOptions(queue);
    final wo = options[id]!.wordOptions;
    final correctOpt = wo.firstWhere((o) => o.word == 'self-$stamp');
    expect(correctOpt.userWordId, id);
  });
}
